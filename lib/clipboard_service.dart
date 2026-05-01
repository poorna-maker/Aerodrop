import 'package:flutter/services.dart';

class ClipboardService {
  static String _lastKnownClipboard = "";

  static Future<String?> read() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  static Future<void> write(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _lastKnownClipboard = text;
  }

  static Future<String?> getNewDataToSync() async {
    String? data = await read();
    if (data != null && data.isNotEmpty && data != _lastKnownClipboard) {
      _lastKnownClipboard = data;
      return _lastKnownClipboard;
    }
    return null;
  }
}
