import 'dart:convert';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/trip/trip_state.dart';
import '../../models/settlement_payment.dart';
import '../../models/trip.dart';
import 'cloud_trip_view.dart';

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

  /// What this device knows the cloud document to contain, per group code:
  /// updated from every server snapshot, every fetch and every write of ours.
  /// Writes are the *difference* between this and the new local state.
  final Map<String, CloudTripView> _baselines = {};

  /// Publishes local trip state to Cloud Firestore under the 6-digit Group Code.
  ///
  /// Concurrency-safe: only the entries that changed since the last known
  /// cloud state are written (`expenseMap.<id>`, `memberMap.<id>.name`...), so a
  /// join, a rename or an expense from another device is never overwritten.
  /// A trip that does not exist yet is created with one full write; an
  /// existing document of unknown state (just after a restart) only receives
  /// the entries it is missing (additive, in a transaction).
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
      final after = CloudTripView.fromState(state);
      final meta = <String, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
        'writerId': writerId,
      };
      final baseline = _baselines[code];

      if (baseline == null) {
        _baselines[code] = await _firstWrite(docRef, after, meta);
      } else {
        final changes = after.diffFrom(baseline);
        if (changes.isEmpty) return;
        await docRef.update({
          for (final c in changes)
            FieldPath(c.path): c.delete ? FieldValue.delete() : c.value,
          ...meta,
        });
        _baselines[code] = baseline.applying(changes);
      }
      debugPrint('[SquadSyncService] Synced trip to cloud for code: $code');
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // The document vanished: recreate it from scratch.
        _baselines.remove(state.squadCode.trim());
        return syncTripToCloud(state, writerId: writerId);
      }
      debugPrint('[SquadSyncService] Sync failed (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint(
        '[SquadSyncService] Offline or unconfigured Firestore sync: $e',
      );
    }
  }

  Future<CloudTripView> _firstWrite(
    DocumentReference<Map<String, dynamic>> docRef,
    CloudTripView after,
    Map<String, Object?> meta,
  ) async {
    try {
      return await _firestore!.runTransaction<CloudTripView>((tx) async {
        final snap = await tx.get(docRef);
        final remote = snap.exists ? CloudTripView.fromDoc(snap.data()!) : null;
        if (remote == null) {
          // New trip (or an old array-style document): one full write.
          tx.set(docRef, {...after.toDocument(), ...meta});
          return after;
        }
        final adds = after.additiveFrom(remote);
        if (adds.isNotEmpty) {
          tx.update(docRef, {
            for (final c in adds) FieldPath(c.path): c.value,
            ...meta,
          });
        }
        return remote.applying(adds);
      });
    } on FirebaseException catch (e) {
      // Transactions need a connection. Offline-first: queue a merging write
      // instead (entries are added or replaced by id; nothing is deleted), so
      // a trip created offline still reaches the cloud later.
      if (e.code != 'unavailable' && e.code != 'deadline-exceeded') rethrow;
      await docRef.set({
        ...after.toDocument(),
        ...meta,
      }, SetOptions(merge: true));
      return after;
    }
  }

  /// Firestore documents are limited to 1 MiB; keep a safe margin.
  static const int maxDocumentBytes = 900 * 1024;

  /// Receipt / slip photos travel inside the trip document so they work
  /// offline and sync cleanly, but they must never push it past Firestore's
  /// limit. When the JSON would be too large the biggest photos are left out
  /// of the *cloud copy* (every device keeps its own local photos, and the
  /// controller merges them back when a snapshot arrives).
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
              _baselines.remove(code);
              return null;
            }
            // Pending local snapshots already contain our own writes, whose
            // baseline was updated when they were issued.
            if (!snapshot.metadata.hasPendingWrites) {
              final view = CloudTripView.fromDoc(data);
              if (view == null) {
                _baselines.remove(code);
              } else {
                _baselines[code] = view;
              }
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
      // Remember the cloud state we joined, so our first write is a small
      // field-level update instead of a full overwrite.
      final view = CloudTripView.fromDoc(data);
      if (view == null) {
        _baselines.remove(code);
      } else {
        _baselines[code] = view;
      }
      return deserializeTrip(data, code);
    } catch (e) {
      debugPrint('[SquadSyncService] Fetch trip error: $e');
      return null;
    }
  }

  /// Pure deserializer (public for unit tests). Tolerates missing fields and
  /// reads both document schemas (2 = maps keyed by id, 1 = legacy arrays).
  @visibleForTesting
  static TripStateUpdate deserializeTrip(
    Map<String, dynamic> data,
    String fallbackCode, {
    bool hasPendingWrites = false,
  }) => CloudTripView.deserialize(
    data,
    fallbackCode,
    hasPendingWrites: hasPendingWrites,
  );
}
