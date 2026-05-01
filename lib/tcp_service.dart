import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';

class TcpService {
  final int port;
  ServerSocket? _serverSocket;

  List<File>? pendingFiles;
  List<Map<String, dynamic>> _incomingFilesQueue = [];

  final StreamController<Map<String, dynamic>> _incomingHandshake =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get incomingHandshakes =>
      _incomingHandshake.stream;

  final StreamController<String> _incomingClipboard =
      StreamController.broadcast();
  Stream<String> get incomingClipboard => _incomingClipboard.stream;

  TcpService({this.port = 8080});

  final StreamController<List<double?>> _transferProgress =
      StreamController.broadcast();
  Stream<List<double?>> get transferProgress => _transferProgress.stream;

  Future<Map<String, int>> calculateResumeData(
    List<Map<String, dynamic>> filesInfoList,
  ) async {
    int resumeIndex = 0;
    int resumeOffset = 0;

    String saveDir = Platform.isAndroid
        ? '/storage/emulated/0/Download'
        : (await getApplicationDocumentsDirectory()).path;

    for (int i = 0; i < filesInfoList.length; i++) {
      String fileName = filesInfoList[i]['fileName'];
      int fileSize = filesInfoList[i]['fileSize'];

      File completedFile = File('$saveDir/$fileName');
      File partialFile = File('$saveDir/$fileName.part');

      if (completedFile.existsSync() &&
          completedFile.lengthSync() == fileSize) {
        resumeIndex = i + 1;
      } else if (partialFile.existsSync()) {
        resumeIndex = i;
        resumeOffset = partialFile.lengthSync();
        break;
      } else {
        resumeIndex = i;
        resumeOffset = 0;
        break;
      }
    }
    return {'resumeIndex': resumeIndex, 'resumeOffset': resumeOffset};
  }

  Future<void> acceptFileTransfer(
    List<Map<String, dynamic>> filesInfoList,
  ) async {
    try {
      final resumeData = await calculateResumeData(filesInfoList);
      int resumeIndex = resumeData['resumeIndex']!;
      int resumeOffset = resumeData['resumeOffset']!;

      print("📂 Starting acceptance flow. Resume at index $resumeIndex, offset $resumeOffset");

      _incomingFilesQueue = List<Map<String, dynamic>>.from(
        filesInfoList.sublist(resumeIndex),
      );
      List<double?> progressList = List<double?>.filled(
        filesInfoList.length,
        0.0,
      );
      for (int i = 0; i < resumeIndex; i++) {
        progressList[i] = 1.0;
      }

      int receivedCount = resumeIndex;

      final dataServer = await ServerSocket.bind(InternetAddress.anyIPv4, 8081);
      print("🚰 AeroDrop: Data Drain open on port 8081. Ready for incoming chunks...");

      dataServer.listen((Socket client) async {
        print("🔗 Data connection established from: ${client.remoteAddress.address}");
        if (_incomingFilesQueue.isEmpty) {
          print("⚠️ Connection received but queue is empty!");
          client.close();
          return;
        }

        final currentFileInfo = _incomingFilesQueue.removeAt(0);
        final fileName = currentFileInfo['fileName'];
        final expectedFileSize = currentFileInfo['fileSize'];
        final int fileIndex = receivedCount++;

        print("📦 Receiving file [$fileIndex]: $fileName ($expectedFileSize bytes)");

        String saveDir = Platform.isAndroid
            ? '/storage/emulated/0/Download'
            : (await getApplicationDocumentsDirectory()).path;

        final partialFile = File('$saveDir/$fileName.part');
        final sink = partialFile.openWrite(mode: FileMode.append);

        int bytesReceived = (fileIndex == resumeIndex) ? resumeOffset : 0;

        client.listen(
          (List<int> chunk) {
            sink.add(chunk);
            bytesReceived = bytesReceived + chunk.length;
            final progress = bytesReceived / expectedFileSize;
            progressList[fileIndex] = progress;
            _transferProgress.sink.add(List.from(progressList));
          },
          onDone: () async {
            print("🏁 Finished receiving chunks for: $fileName");
            await sink.close();
            await client.close();

            final completedFile = File('$saveDir/$fileName');
            if (await completedFile.exists()) {
              await completedFile.delete();
            }
            await partialFile.rename(completedFile.path);

            progressList[fileIndex] = 1.0;
            _transferProgress.sink.add(List.from(progressList));

            print("✅ File saved successfully: ${completedFile.path}");

            if (Platform.isAndroid) {
              MediaScanner.loadMedia(path: completedFile.path);
            }

            if (_incomingFilesQueue.isEmpty) {
              print("🛑 All files received. Closing Data Drain.");
              await dataServer.close();
            }
          },
          onError: (error) {
            print("🚨 Transfer stream error: $error");
            sink.close();
            client.close();
          },
        );
      });
    } catch (e) {
      print("🚨 Failed to open data drain: $e");
    }
  }

  Future<void> sendFiles(
    String targetIP,
    List<File> files,
    int resumeIndex,
    int resumeOffset,
  ) async {
    print("🚀 Initiating file send to $targetIP. Resuming from index $resumeIndex");
    try {
      List<double?> progressList = List<double?>.filled(files.length, 0.0);

      for (int i = 0; i < resumeIndex; i++) {
        progressList[i] = 1.0;
      }
      _transferProgress.sink.add(List.from(progressList));

      for (int i = resumeIndex; i < files.length; i++) {
        final currentFile = files[i];
        final fileName = currentFile.path.split(Platform.pathSeparator).last;
        print("🔌 Connecting to $targetIP:8081 for file: $fileName");
        
        final socket = await Socket.connect(targetIP, 8081);
        print("📡 Connected! Starting stream for: $fileName");
        
        final totalSize = await currentFile.length();
        int startByte = (i == resumeIndex) ? resumeOffset : 0;
        
        int bytesSent = startByte;
        final stream = currentFile.openRead(startByte);

        final completer = Completer<void>();
        
        stream.listen(
          (List<int> chunk) {
            socket.add(chunk);
            bytesSent += chunk.length;
            final progress = bytesSent / totalSize;
            progressList[i] = progress;
            _transferProgress.sink.add(List.from(progressList));
          },
          onDone: () async {
            print("📤 Finished sending: $fileName");
            await socket.flush();
            await socket.close();
            progressList[i] = 1.0;
            _transferProgress.sink.add(List.from(progressList));
            completer.complete();
          },
          onError: (error) {
            print("🚨 Error during file stream: $error");
            socket.close();
            completer.completeError(error);
          },
        );

        await completer.future;
      }
      print("🎊 Batch transfer complete!");
      pendingFiles = [];
    } catch (e) {
      print("🚨 SendFiles error: $e");
    }
  }

  Future<void> startListening() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      print("🎧 AeroDrop Listening on port $port...");

      _serverSocket?.listen((Socket client) {
        String buffer = "";
        client.listen(
          (List<int> data) {
            buffer += utf8.decode(data);
            try {
              // Try to see if we have a complete JSON object
              final jsonMap = jsonDecode(buffer);
              
              print("📥 Incoming message: ${jsonMap['type']}");

              if (jsonMap['type'] == 'batch_request') {
                jsonMap['senderIp'] = client.remoteAddress.address;
                _incomingHandshake.sink.add(jsonMap);
              } else if (jsonMap['type'] == 'handshake_response') {
                if (jsonMap['status'] == 'accept' && pendingFiles != null) {
                  int resIndex = jsonMap['resumeIndex'] ?? 0;
                  int resOffset = jsonMap['resumeOffset'] ?? 0;

                  sendFiles(
                    client.remoteAddress.address,
                    pendingFiles!,
                    resIndex,
                    resOffset,
                  );
                  pendingFiles = null;
                } else {
                  pendingFiles = null;
                }
              }

              if (jsonMap['type'] == 'clipboard_sync') {
                final incomingText = jsonMap['text'];
                _incomingClipboard.sink.add(incomingText);
              }
              
              // Clear buffer after successful parse
              buffer = ""; 
            } catch (e) {
              // Not a full JSON yet, continue buffering
            }
          },
          onDone: () => client.close(),
          onError: (e) => print("🚨 Control socket error: $e"),
        );
      });
    } catch (e) {
      print("🚨 Server start failed: $e");
    }
  }

  Future<void> sendHandshake(
    String targetIP,
    String myDeviceName,
    List<Map<String, dynamic>> filesInfoList,
  ) async {
    try {
      final socket = await Socket.connect(
        targetIP,
        port,
        timeout: const Duration(seconds: 5),
      );

      final handshakePayload = {
        "type": "batch_request",
        "senderName": myDeviceName,
        "filesInfo": filesInfoList,
      };

      socket.add(utf8.encode(jsonEncode(handshakePayload)));

      await socket.flush();
      await socket.close();

      print("✅ Handshake sent successfully!");
    } catch (e) {
      print("🚨 Failed to send handshake to $targetIP: $e");
    }
  }

  Future<void> sendClipboardData(String targetIp, String text) async {
    try {
      final Socket socket = await Socket.connect(targetIp, port);
      final clipboardPayload = {"type": "clipboard_sync", "text": text};
      socket.add(utf8.encode(jsonEncode(clipboardPayload)));

      await socket.flush();
      await socket.close();
    } catch (e) {
      print("Failed to send clipboard data: $e");
    }
  }

  Future<void> sendHandshakeResponse(
    String targetIp,
    String status,
    List<Map<String, dynamic>>? filesInfoList,
  ) async {
    try {
      int resumeIndex = 0;
      int resumeOffset = 0;

      if (status == 'accept' && filesInfoList != null) {
        final resumeData = await calculateResumeData(filesInfoList);
        resumeIndex = resumeData['resumeIndex']!;
        resumeOffset = resumeData['resumeOffset']!;
      }

      final Socket socket = await Socket.connect(targetIp, port);
      final responsePayload = {
        "type": "handshake_response",
        "status": status,
        "resumeIndex": resumeIndex,
        "resumeOffset": resumeOffset,
      };

      socket.add(utf8.encode(jsonEncode(responsePayload)));
      await socket.flush();
      await socket.close();
      print("✉️ Response '$status' sent back to $targetIp");
    } catch (e) {
      print("🚨 Failed to send response: $e");
    }
  }

  void dispose() {
    _serverSocket?.close();
    _incomingHandshake.close();
  }
}
