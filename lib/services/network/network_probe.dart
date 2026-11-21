import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// "Can this device reach Google right now?" Used to choose between the
/// Gemini audio pipeline (online) and offline dictation (Airplane Mode), and
/// to tell "offline" from "Gemini did not answer" in error messages.
class NetworkProbe {
  NetworkProbe._();

  /// Replace in tests.
  static Future<bool> Function() check = _lookup;

  static Future<bool> _lookup() async {
    if (kIsWeb) return true; // the browser's own errors surface on the call
    // A slow mobile DNS answer must not look like "offline": two tries.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final hosts = await InternetAddress.lookup(
          'firebasevertexai.googleapis.com',
        ).timeout(const Duration(seconds: 3));
        if (hosts.isNotEmpty && hosts.first.rawAddress.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }
}
