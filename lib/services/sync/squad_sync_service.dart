import 'dart:convert';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/trip/trip_state.dart';
import '../../models/expense_item.dart';
import '../../models/settlement_payment.dart';
import '../../models/trip.dart';
import '../../models/trip_member.dart';

class TripStateUpdate {
  final Trip trip;
  final List<SettlementPayment> settlements;

  /// Random id of the controller instance that wrote this document. Used to
  /// ignore the echo of our own writes.
  final String? writerId;

  /// `true` while the snapshot only reflects a local, not-yet-acknowledged write.
  final bool hasPendingWrites;

  const TripStateUpdate({
    required this.trip,
    this.settlements = const [],
    this.writerId,
    this.hasPendingWrites = false,
  });
}

/// Real-time Multi-Device Synchronization Service using Cloud Firestore.
/// Enables S26+ Android, iPad Air M4, and Chrome Web to sync live keyed by the 6-digit Group Code.
///
/// Privacy note: bank slips and receipt text are never uploaded — only the
/// expenses themselves, members and paid settlements.
class SquadSyncService {
  FirebaseFirestore? _firestoreInstance;

  SquadSyncService({FirebaseFirestore? firestore})
    : _firestoreInstance = firestore;

  FirebaseFirestore? get _firestore {
    if (_firestoreInstance != null) return _firestoreInstance;
    try {
      _firestoreInstance = FirebaseFirestore.instance;
      return _firestoreInstance;
    } catch (e) {
      return null;
    }
  }

  /// Whether Firebase/Firestore is configured on this build.
  bool get isAvailable => _firestore != null;

  CollectionReference<Map<String, dynamic>>? get _tripsCollection =>
      _firestore?.collection('trips');

  /// Publishes local trip state to Cloud Firestore under the 6-digit Group Code
  Future<void> syncTripToCloud(TripState state, {String? writerId}) async {
    final code = state.squadCode.trim();
    if (code.isEmpty) return;

    try {
      final trips = _tripsCollection;
      if (trips == null) {
        debugPrint(
          '[SquadSyncService] Firestore not initialized; skipping sync',
        );
        return;
      }
      final docRef = trips.doc(code);
      final payload = {
        'id': state.trip.id,
        'name': state.trip.name,
        'baseCurrency': state.trip.baseCurrency,
        'homeCurrency': state.trip.homeCurrency,
        'squadCode': code,
        'createdAt': state.trip.createdAt.toIso8601String(),
        'startDate': state.trip.startDate.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'writerId': writerId,
        'members': state.trip.members
            .map((m) => {'id': m.id, 'name': m.name})
            .toList(),
        'hostUid': state.trip.hostUid,
        'lockGuestEdits': state.trip.lockGuestEdits,
        ...fitImagesToDocument(
          expenses: state.trip.expenses.map((e) => e.toJson()).toList(),
          settlements: state.settlements.map((s) => s.toJson()).toList(),
        ),
      };

      // Full replace (no merge) so deleted expenses/members really disappear.
      await docRef.set(payload);
      debugPrint('[SquadSyncService] Synced trip to cloud for code: $code');
    } catch (e) {
      debugPrint(
        '[SquadSyncService] Offline or unconfigured Firestore sync: $e',
      );
    }
  }

  /// Firestore documents are limited to 1 MiB; keep a safe margin.
  static const int maxDocumentBytes = 900 * 1024;

  /// Receipt / slip photos travel inside the trip document so they work
  /// offline and sync cleanly, but they must never push it past Firestore's
  /// limit. When the JSON would be too large the biggest photos are left out
  /// of the *cloud copy* (every device keeps its own local photos, and the
  /// controller merges them back when a snapshot arrives).
  @visibleForTesting
  static Map<String, dynamic> fitImagesToDocument({
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> settlements,
    int maxBytes = maxDocumentBytes,
  }) {
    // Mutable copies so the caller's maps are never touched.
    final ex = [for (final e in expenses) Map<String, dynamic>.from(e)];
    final st = [for (final s in settlements) Map<String, dynamic>.from(s)];

    int size() => jsonEncode(ex).length + jsonEncode(st).length;

    if (size() > maxBytes) {
      final photos =
          <
            ({List<Map<String, dynamic>> list, int index, String key, int len})
          >[];
      for (var i = 0; i < ex.length; i++) {
        final img = ex[i]['receiptImageBase64'];
        if (img is String) {
          photos.add((
            list: ex,
            index: i,
            key: 'receiptImageBase64',
            len: img.length,
          ));
        }
      }
      for (var i = 0; i < st.length; i++) {
        final img = st[i]['slipImageBase64'];
        if (img is String) {
          photos.add((
            list: st,
            index: i,
            key: 'slipImageBase64',
            len: img.length,
          ));
        }
      }
      photos.sort((a, b) => b.len.compareTo(a.len));
      for (final p in photos) {
        if (size() <= maxBytes) break;
        p.list[p.index].remove(p.key);
      }
    }
    return {'expenses': ex, 'settlements': st};
  }

  /// Streams real-time updates for the given 6-digit Group Code.
  /// Emits `null` when the document does not exist yet.
  Stream<TripStateUpdate?> streamTripUpdates(String squadCode) {
    final code = squadCode.trim();
    if (code.isEmpty) return const Stream.empty();

    try {
      final trips = _tripsCollection;
      if (trips == null) return const Stream.empty();
      return trips
          .doc(code)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            final data = snapshot.data();
            if (!snapshot.exists || data == null) {
              return null;
            }
            return deserializeTrip(
              data,
              code,
              hasPendingWrites: snapshot.metadata.hasPendingWrites,
            );
          })
          .handleError((Object e) {
            debugPrint('[SquadSyncService] Stream error for code $code: $e');
          });
    } catch (e) {
      debugPrint('[SquadSyncService] Failed to attach stream: $e');
      return const Stream.empty();
    }
  }

  /// Fetches a trip by 6-digit group code (for "Join Group")
  Future<TripStateUpdate?> fetchTrip(String squadCode) async {
    final code = squadCode.trim();
    if (code.isEmpty) return null;

    try {
      final trips = _tripsCollection;
      if (trips == null) return null;
      final snapshot = await trips
          .doc(code)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return deserializeTrip(data, code);
    } catch (e) {
      debugPrint('[SquadSyncService] Fetch trip error: $e');
      return null;
    }
  }

  /// Pure deserializer (public for unit tests). Tolerates missing fields.
  @visibleForTesting
  static TripStateUpdate deserializeTrip(
    Map<String, dynamic> data,
    String fallbackCode, {
    bool hasPendingWrites = false,
  }) {
    final members = ((data['members'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          return TripMember(
            id: map['id']?.toString() ?? 'unknown',
            name: map['name']?.toString() ?? 'Friend',
          );
        })
        .toList();

    final expenses = ((data['expenses'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ExpenseItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final settlements = ((data['settlements'] as List?) ?? const [])
        .whereType<Map>()
        .map((s) => SettlementPayment.fromJson(Map<String, dynamic>.from(s)))
        .toList();

    final trip = Trip(
      id: data['id']?.toString() ?? 'trip_$fallbackCode',
      name: data['name']?.toString() ?? 'Shared Trip',
      baseCurrency: data['baseCurrency']?.toString() ?? 'JPY',
      homeCurrency: data['homeCurrency']?.toString() ?? 'USD',
      members: members,
      expenses: expenses,
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      startDate: DateTime.tryParse(data['startDate']?.toString() ?? ''),
      hostUid: data['hostUid']?.toString(),
      lockGuestEdits: data['lockGuestEdits'] == true,
    );

    return TripStateUpdate(
      trip: trip,
      settlements: settlements,
      writerId: data['writerId']?.toString(),
      hasPendingWrites: hasPendingWrites,
    );
  }
}
