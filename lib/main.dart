import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:aero_drop/app_colors.dart';
import 'package:aero_drop/clipboard_service.dart';
import 'package:aero_drop/liquid_ring.dart';
import 'package:aero_drop/providers.dart';
import 'package:aero_drop/qr_scanner_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'helpers.dart';

void main() {
  runApp(const ProviderScope(child: MaterialApp(home: RadarScreen())));
}

class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen>
    with WidgetsBindingObserver {
  String? myDeviceRealName;
  List<String?> files = [];
  late StreamSubscription _intentDataFromOtherApps;
  String? qrPayload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _intentDataFromOtherApps = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (value) {
            _handleIncomingSharedFiles(value);
          },
          onError: (err) {
            print("Intent Stream Error: $err");
          },
        );

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _handleIncomingSharedFiles(value);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = ref.read(discoveryServiceProvider);
      final tcpService = ref.read(tcpServiceProvider);
      final fetchedName = await Helpers.getDeviceName();
      qrPayload = await Helpers.generateQRPayload(fetchedName);
      setState(() {
        myDeviceRealName = fetchedName;
      });

      service.startBroadcasting(myDeviceName: fetchedName, port: 8080);
      service.startDiscovering();
      tcpService.startListening();
    });
  }

  void _handleIncomingSharedFiles(List<SharedMediaFile> sharedFiles) {
    if (sharedFiles.isEmpty) return;

    List<File> filesToSend = sharedFiles
        .map((file) => File(file.path))
        .toList();

    ref.read(tcpServiceProvider).pendingFiles = filesToSend;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Loaded ${filesToSend.length} files. Tap a device to send",
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _intentDataFromOtherApps.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (AppLifecycleState.resumed == state) {
      final newText = await ClipboardService.getNewDataToSync();
      final targetIp = ref.read(selectedDeviceIpProvider);

      if (newText != null && targetIp != null) {
        ref.read(tcpServiceProvider).sendClipboardData(targetIp, newText);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Copied text synced to $targetIp"),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodesAsyncValue = ref.watch(discoveredNodesProvider);
    final progressState = ref.watch(transferProgressProvider);
    final progressFileName = ref.watch(activeFileNameProvider);
    ref.listen<AsyncValue<Map<String, dynamic>>>(incomingHandshakesProvider, (
      previous,
      next,
    ) {
      next.whenData((handshakeData) {
        final senderName = handshakeData['senderName'] ?? "Unknown Device";
        final List<Map<String, dynamic>> filesInfoList = 
            (handshakeData['filesInfo'] as List).cast<Map<String, dynamic>>();

        files = [];
        for (int i = 0; i < filesInfoList.length; i++) {
          files.add(filesInfoList[i]['fileName']);
        }
        ref.read(activeFileNameProvider.notifier).state = List.from(files);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              "Incoming File",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "$senderName wants to send you some files. Do you want to accept this transfer?",
              style: const TextStyle(color: AppColors.textDim),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  final targetIp = handshakeData['senderIp'];
                  ref
                      .read(tcpServiceProvider)
                      .sendHandshakeResponse(
                        targetIp,
                        'decline',
                        filesInfoList,
                      );
                },
                child: const Text(
                  "Decline",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final targetIp = handshakeData['senderIp'];
                  if (Platform.isAndroid) {
                    var status = await Permission.manageExternalStorage
                        .request();
                    if (!status.isGranted) {
                      print("❌ User denied file manager permission. Aborting.");
                      ref
                          .read(tcpServiceProvider)
                          .sendHandshakeResponse(
                            targetIp,
                            'decline',
                            filesInfoList,
                          );
                      return;
                    }
                  }

                  await ref
                      .read(tcpServiceProvider)
                      .acceptFileTransfer(filesInfoList);
                  await ref
                      .read(tcpServiceProvider)
                      .sendHandshakeResponse(targetIp, "accept", filesInfoList);
                },
                child: const Text(
                  "Accept",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      });
    });

    ref.listen<AsyncValue<String>>(incomingClipBoardProvider, (
      previous,
      incomingText,
    ) {
      incomingText.whenData((incomingClipboardText) {
        if (incomingClipboardText.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Incoming text: ${incomingClipboardText.length > 15 ? incomingClipboardText.substring(0, 15) + '...' : incomingClipboardText}",
              ),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: "Sync to clipboard",
                onPressed: () async {
                  await ClipboardService.write(incomingClipboardText);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Copied to system clipboard"),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          );
        }
      });
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryLight,
                    AppColors.primaryLight.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.blobYellow.withOpacity(0.3),
                    AppColors.blobYellow.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.transparent),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: EdgeInsetsGeometry.symmetric(
                horizontal: 28.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40.0,
                        height: 40.0,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14.0),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.08),
                              blurRadius: 30.0,
                              offset: Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text("👋", style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      SizedBox(width: 12.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "YOU ARE VISIBLE AS",
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            myDeviceRealName ?? "Loading...",
                            style: TextStyle(
                              color: AppColors.textMain,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    "Nearby Devices",
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          LiquidRing(
                            size: 280,
                            durationSeconds: 12,
                            reverse: true,
                          ),
                          LiquidRing(
                            size: 360,
                            durationSeconds: 8,
                            reverse: false,
                          ),
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 35,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.near_me,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 8.0, bottom: 12.0),
                          child: Text(
                            "DISCOVERED NODES",
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        Expanded(
                          child: nodesAsyncValue.when(
                            data: (nodes) {
                              if (nodes.isEmpty) {
                                return const Center(
                                  child: Text("Scanning nearby devices..."),
                                );
                              }
                              return GridView.count(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                physics: BouncingScrollPhysics(),
                                children: nodes.map((service) {
                                  return _buildNodeCard(
                                    icon: Icons.smartphone,
                                    name: service.name ?? "UNKNOWN DEVICE",
                                    deviceType: service.host ?? "CONNECTING..",
                                    onTap: () async {
                                      final targetIP = service.host;
                                      if (targetIP == null) return;

                                      ref
                                              .read(
                                                selectedDeviceIpProvider
                                                    .notifier,
                                              )
                                              .state =
                                          targetIP;

                                      final newText =
                                          await ClipboardService.read();
                                      if (newText != null &&
                                          newText.isNotEmpty) {
                                        ref
                                            .read(tcpServiceProvider)
                                            .sendClipboardData(
                                              targetIP,
                                              newText,
                                            );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Clipboard synced to ${service.name}",
                                            ),
                                            backgroundColor: Colors.blue,
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                      final tcpService = ref.read(
                                        tcpServiceProvider,
                                      );

                                      List<File>? filesToSend =
                                          tcpService.pendingFiles;

                                      if (filesToSend == null ||
                                          filesToSend.isEmpty) {
                                        FilePickerResult? result =
                                            await FilePicker.pickFiles(
                                              allowMultiple: true,
                                            );

                                        if (result != null &&
                                            result.files.isNotEmpty) {
                                          filesToSend = result.files
                                              .map((f) => File(f.path!))
                                              .toList();
                                        }
                                      }

                                      // 5. Send Handshake if we have files
                                      if (filesToSend != null &&
                                          filesToSend.isNotEmpty) {
                                        List<Map<String, dynamic>>
                                        filesInfoList = [];

                                        for (var file in filesToSend) {
                                          filesInfoList.add({
                                            "fileName": file.path
                                                .split(Platform.pathSeparator)
                                                .last,
                                            "fileSize": await file.length(),
                                          });
                                        }

                                        tcpService.pendingFiles = filesToSend;
                                        await tcpService.sendHandshake(
                                          targetIP,
                                          myDeviceRealName ?? "Unknown device",
                                          filesInfoList,
                                        );
                                      }
                                    },
                                  );
                                }).toList(),
                              );
                            },
                            error: (error, stack) =>
                                Center(child: Text("Error : $error")),
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        _buildActiveTransferCard(
                          progressState,
                          progressFileName,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.flash_on,
        activeIcon: Icons.close,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,

        overlayColor: Colors.black,
        overlayOpacity: 0.6,
        spaceBetweenChildren: 12,
        spacing: 12,

        children: [
          SpeedDialChild(
            child: const Icon(Icons.qr_code_scanner, color: Colors.black),
            label: "Scan to connect",
            backgroundColor: AppColors.surface,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QrScannerScreen(
                    myDeviceRealName: myDeviceRealName ?? "Unknown device",
                  ),
                ),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.qr_code, color: Colors.black),
            backgroundColor: AppColors.surface,
            label: 'Receive via QR Code',
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
            onTap: () {
              showMyQRCode(context, qrPayload);
            },
          ),
        ],
      ),
    );
  }
}

Widget _buildNodeCard({
  required IconData icon,
  required String name,
  required String deviceType,
  required VoidCallback onTap,
}) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.05),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                deviceType,
                style: const TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    "Send File",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildActiveTransferCard(
  AsyncValue<List<double?>> progressState,
  List<String?> progressFileName,
) {
  return progressState.when(
    data: (progress) {
      final shouldShow =
          progress.isNotEmpty && progress.any((p) => (p ?? 0.0) < 1.0);

      if (shouldShow) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.textMain,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.textMain.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "TRANSFERRING...",
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "STOP",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text("📁", style: TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: progressFileName.length,
                        itemBuilder: (BuildContext context, int index) {
                          var currentFileName = progressFileName[index];
                          var currentProgress = (index < progress.length)
                              ? (progress[index] ?? 0.0)
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentFileName ?? "Unknown file",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: currentProgress,
                                          backgroundColor: Colors.white10,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(Colors.white),
                                          minHeight: 6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${(currentProgress * 100).toInt()}%",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    },
    error: (err, stack) => Text(
      "Transfer Failed: $err",
      style: const TextStyle(color: Colors.red),
    ),
    loading: () => const SizedBox.shrink(),
  );
}

void showMyQRCode(BuildContext context, String? payload) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text("Scan to Connect", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 250,
        height: 250,
        child: QrImageView(
          data: payload ?? "",
          backgroundColor: Colors.white,
          version: QrVersions.auto,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text("Close"),
        ),
      ],
    ),
  );
}
