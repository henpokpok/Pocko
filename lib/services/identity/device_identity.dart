import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who is holding this device: the Firebase anonymous-auth uid, or a stable
/// per-launch local id when Firebase is not available (tests, offline builds).
///
/// The uid is stamped on everything this device creates (`createdByUid`) and on
/// the trip it hosts (`hostUid`), which drives the host / creator permissions.
class DeviceIdentity {
  DeviceIdentity._();

  static String? _fallback;

  static String currentUid() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {
      // Firebase not initialized: fall through to the local id.
    }
    return _fallback ??= 'local_${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// The current device's uid. Override in tests to simulate other people.
final currentUidProvider = Provider<String>(
  (ref) => DeviceIdentity.currentUid(),
);
