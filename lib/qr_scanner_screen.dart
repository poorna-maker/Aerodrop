import 'dart:io';

import 'package:aero_drop/providers.dart';
import 'package:aero_drop/tcp_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  final String myDeviceRealName;

  const QrScannerScreen({super.key, required this.myDeviceRealName});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Aerodrop code")),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (Barcode barcode in barcodes) {
            final rawValue = barcode.rawValue;
            if (rawValue != null && rawValue.startsWith("aero-drop:")) {
              List<String> parts = rawValue.split(":");
              String targetIp = parts[1];
              String targetName = parts[3];

              // 1. Capture everything we need BEFORE popping or awaiting
              final tcpService = ref.read(tcpServiceProvider);
              final myDeviceName = widget.myDeviceRealName;

              // 2. Set the active peer for clipboard sync
              ref.read(selectedDeviceIpProvider.notifier).state = targetIp;

              // 3. Close the scanner
              Navigator.pop(context);

              // 4. Trigger the transfer flow using captured references
              _triggerhandshake(tcpService, targetIp, targetName, myDeviceName);
            }
          }
        },
      ),
    );
  }

  void _triggerhandshake(
    TcpService tcpService,
    String targetIP,
    String targetName,
    String deviceName,
  ) async {
    FilePickerResult? result = await FilePicker.pickFiles(allowMultiple: true);

    if (result != null && result.files.isNotEmpty) {
      List<File> selectedFiles = result.files
          .map((file) => File(file.path!))
          .toList();

      List<Map<String, dynamic>> filesInfoList = result.files
          .map(
            (file) => <String, dynamic>{
              "fileName": file.name,
              "fileSize": file.size,
            },
          )
          .toList();

      tcpService.pendingFiles = selectedFiles;
      await tcpService.sendHandshake(targetIP, deviceName, filesInfoList);
    }
  }
}
