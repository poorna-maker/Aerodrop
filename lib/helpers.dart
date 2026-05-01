import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class Helpers {
  static Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.model;
    }
    return "UNKNOWN DEVICE";
  }

  static Future<String> generateQRPayload(String deviceName) async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    if (ip == null) throw Exception("Not Connected to wifi");
    return "aero-drop:$ip:8080:$deviceName";
  }
}
