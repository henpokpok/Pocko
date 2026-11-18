import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/trip/trip_state.dart';
import '../../models/settlement_payment.dart';
import '../../models/trip.dart';

/// What survives an app restart: the trip this device is in, who it is inside
/// it, and the repayments. Everything else is derived.
class PersistedSession {
  final Trip trip;
  final List<SettlementPayment> settlements;
  final String squadCode;
  final String currentMemberId;
  final bool hasTrip;

  const PersistedSession({
    required this.trip,
    required this.settlements,
    required this.squadCode,
    required this.currentMemberId,
    required this.hasTrip,
  });
}

/// Small `SharedPreferences` wrapper for the things that must outlive a launch:
///
/// * `has_seen_landing`: the illustrated Landing Page is only shown on the very
///   first launch (or when it is replayed from Settings);
/// * the display name the user chose (pre-fills the Join Group sheet);
/// * the current trip session, so the next launch opens straight on Home.
///
/// Resetting the landing flag never touches the session, the Firebase
/// anonymous user or the App Check debug token, so demo takes can replay the
/// landing without wiping app storage.
class SessionStore {
  static const String hasSeenLandingKey = 'has_seen_landing';
  static const String displayNameKey = 'display_name';
  static const String sessionKey = 'session_v1';

  final SharedPreferences _prefs;
  SessionStore(this._prefs);

  bool get hasSeenLanding => _prefs.getBool(hasSeenLandingKey) ?? false;

  Future<void> setHasSeenLanding(bool value) =>
      _prefs.setBool(hasSeenLandingKey, value);

  String? get displayName {
    final v = _prefs.getString(displayNameKey)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setDisplayName(String name) =>
      _prefs.setString(displayNameKey, name.trim());

  /// The saved session, or `null` when none exists (or it is unreadable).
  PersistedSession? loadSession() {
    final raw = _prefs.getString(sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final trip = Trip.fromJson(Map<String, dynamic>.from(map['trip'] as Map));
      return PersistedSession(
        trip: trip,
        settlements: [
          for (final s in (map['settlements'] as List? ?? const []))
            SettlementPayment.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        squadCode: map['squadCode'] as String? ?? '',
        currentMemberId: map['currentMemberId'] as String? ?? 'you',
        hasTrip: map['hasTrip'] as bool? ?? true,
      );
    } catch (e) {
      debugPrint('[SessionStore] Ignoring unreadable saved session: $e');
      return null;
    }
  }

  Future<void> saveSession(TripState s) {
    return _prefs.setString(
      sessionKey,
      jsonEncode({
        'trip': s.trip.toJson(),
        'settlements': s.settlements.map((p) => p.toJson()).toList(),
        'squadCode': s.squadCode,
        'currentMemberId': s.currentMemberId,
        'hasTrip': s.hasTrip,
      }),
    );
  }

  Future<void> clearSession() => _prefs.remove(sessionKey);
}

/// `null` in tests and headless runs (nothing is persisted and the controller
/// starts from the built-in demo trip); the real store in `main()`.
final sessionStoreProvider = Provider<SessionStore?>((ref) => null);
