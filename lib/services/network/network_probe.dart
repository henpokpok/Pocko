import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// "Can this device reach Google right now?" Used to choose between the
/// Gemini audio pipeline (online) and offline dictation (Airplane Mode).
class NetworkProbe {
  NetworkProbe._();

  /// Replace in tests.
  static Future<bool> Function() check = _lookup;

  static Future<bool> _lookup() async {
    if (kIsWeb) return true; // the browser's own errors surface on the call
    try {
      final hosts = await InternetAddress.lookup(
        'firebasevertexai.googleapis.com',
      ).timeout(const Duration(milliseconds: 1500));
      return hosts.isNotEmpty && hosts.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
