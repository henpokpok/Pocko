import 'dart:convert';

import '../../features/trip/trip_state.dart';
import '../../models/expense_item.dart';
import '../../models/settlement_payment.dart';
import '../../models/trip.dart';
import '../../models/trip_member.dart';
import 'squad_sync_service.dart';

/// One field-level change to the shared trip document.
class CloudChange {
  /// Path inside the document, e.g. `['expenseMap', 'exp_17']` or
  /// `['memberMap', 'mem_3', 'name']`.
  final List<String> path;
  final Object? value;
  final bool delete;

  const CloudChange(this.path, this.value) : delete = false;
  const CloudChange.delete(this.path) : value = null, delete = true;

  @override
  String toString() =>
      delete ? 'delete ${path.join('.')}' : 'set ${path.join('.')}';
}

/// The shared trip document (schema 2) as plain maps, plus the diff that turns
/// one version into the next.
///
/// **Why field-level writes:** the first version replaced the whole document
/// (`set(payload)`) on every edit, so two devices editing at once silently
/// erased each other (a join, a rename or an expense could be lost). Schema 2
/// stores members, expenses and repayments as **maps keyed by their immutable
/// id**, and each device writes only the entries it actually changed
/// (`expenseMap.<id>`, `memberMap.<id>.name`...). Changes to different entries
/// never conflict, and a rename touches nothing but one `name` field.
class CloudTripView {
  static const int schema = 2;

  final Map<String, Object?> scalars;

  /// id -> name.
  final Map<String, String> memberNames;

  /// id -> position (only written when a member is created).
  final Map<String, int> memberOrder;
  final Map<String, Map<String, dynamic>> expenses;
  final Map<String, Map<String, dynamic>> settlements;

  const CloudTripView({
    required this.scalars,
    required this.memberNames,
    required this.memberOrder,
    required this.expenses,
    required this.settlements,
  });

  /// The cloud copy of a local [state] (photos too big for the document are
  /// left out, see [SquadSyncService.fitImagesToDocument]).
  factory CloudTripView.fromState(TripState state) {
    final fitted = SquadSyncService.fitImagesToDocument(
      expenses: state.trip.expenses.map((e) => e.toJson()).toList(),
      settlements: state.settlements.map((s) => s.toJson()).toList(),
    );
    final t = state.trip;
    return CloudTripView(
      scalars: {
        'id': t.id,
        'name': t.name,
        'baseCurrency': t.baseCurrency,
        'homeCurrency': t.homeCurrency,
        'squadCode': state.squadCode.trim(),
        'createdAt': t.createdAt.toIso8601String(),
        'startDate': t.startDate.toIso8601String(),
        'hostUid': t.hostUid,
        'lockGuestEdits': t.lockGuestEdits,
      },
      memberNames: {for (final m in t.members) m.id: m.name},
      memberOrder: {
        for (var i = 0; i < t.members.length; i++) t.members[i].id: i,
      },
      expenses: _byId(fitted['expenses'] as List),
      settlements: _byId(fitted['settlements'] as List),
    );
  }

  /// Reads a snapshot. Returns `null` for documents that are not schema 2
  /// (legacy array documents are replaced by a full write on the next sync).
  static CloudTripView? fromDoc(Map<String, dynamic> data) {
    if (data['schema'] != schema) return null;
    final names = <String, String>{};
    final order = <String, int>{};
    final memberMap = data['memberMap'];
    if (memberMap is Map) {
      memberMap.forEach((k, v) {
        if (v is Map) {
          names[k.toString()] = v['name']?.toString() ?? 'Friend';
          order[k.toString()] = (v['order'] as num?)?.toInt() ?? 0;
        }
      });
    }
    Map<String, Map<String, dynamic>> entries(Object? raw) {
      final out = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) out[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
      return out;
    }

    return CloudTripView(
      scalars: {for (final k in _scalarKeys) k: data[k]},
      memberNames: names,
      memberOrder: order,
      expenses: entries(data['expenseMap']),
      settlements: entries(data['settlementMap']),
    );
  }

  static const List<String> _scalarKeys = [
    'id',
    'name',
    'baseCurrency',
    'homeCurrency',
    'squadCode',
    'createdAt',
    'startDate',
    'hostUid',
    'lockGuestEdits',
  ];

  static Map<String, Map<String, dynamic>> _byId(List list) => {
    for (final e in list)
      if (e is Map && e['id'] != null)
        e['id'].toString(): Map<String, dynamic>.from(e),
  };

  /// Canonical text of a JSON value (sorted keys) so a document read back from
  /// Firestore compares equal to what the app serialized.
  static String canon(Object? v) => jsonEncode(_sortKeys(v));

  static Object? _sortKeys(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _sortKeys(v[k])};
    }
    if (v is List) return [for (final e in v) _sortKeys(e)];
    return v;
  }

  /// The full v2 document (used when a trip is created).
  Map<String, Object?> toDocument() => {
    ...scalars,
    'schema': schema,
    'memberMap': {
      for (final id in memberNames.keys)
        id: {'name': memberNames[id], 'order': memberOrder[id] ?? 0},
    },
    'expenseMap': expenses,
    'settlementMap': settlements,
  };

  /// Field-level changes that turn [before] into this view. Entries that did
  /// not change are not written, so they cannot clobber a concurrent edit.
  List<CloudChange> diffFrom(CloudTripView before) {
    final out = <CloudChange>[];

    scalars.forEach((k, v) {
      final old = before.scalars[k];
      if (canon(old) == canon(v)) return;
      out.add(v == null ? CloudChange.delete([k]) : CloudChange([k], v));
    });

    // Members: created, renamed (one `name` field), removed.
    memberNames.forEach((id, name) {
      if (!before.memberNames.containsKey(id)) {
        out.add(
          CloudChange(
            ['memberMap', id],
            {'name': name, 'order': memberOrder[id] ?? memberNames.length},
          ),
        );
      } else if (before.memberNames[id] != name) {
        out.add(CloudChange(['memberMap', id, 'name'], name));
      }
    });
    for (final id in before.memberNames.keys) {
      if (!memberNames.containsKey(id)) {
        out.add(CloudChange.delete(['memberMap', id]));
      }
    }

    void entities(
      String field,
      Map<String, Map<String, dynamic>> now,
      Map<String, Map<String, dynamic>> then,
    ) {
      now.forEach((id, json) {
        final old = then[id];
        if (old == null || canon(old) != canon(json)) {
          out.add(CloudChange([field, id], json));
        }
      });
      for (final id in then.keys) {
        if (!now.containsKey(id)) out.add(CloudChange.delete([field, id]));
      }
    }

    entities('expenseMap', expenses, before.expenses);
    entities('settlementMap', settlements, before.settlements);
    return out;
  }

  /// First write for a document that already exists but whose baseline is
  /// unknown (e.g. right after an app restart): **additive only**. Entries the
  /// cloud already has are left alone (the cloud wins), entries it lacks are
  /// added, and nothing is deleted, so a stale device can never wipe the group.
  List<CloudChange> additiveFrom(CloudTripView remote) {
    final out = <CloudChange>[];
    memberNames.forEach((id, name) {
      if (!remote.memberNames.containsKey(id)) {
        out.add(
          CloudChange(
            ['memberMap', id],
            {'name': name, 'order': memberOrder[id] ?? memberNames.length},
          ),
        );
      }
    });
    expenses.forEach((id, json) {
      if (!remote.expenses.containsKey(id)) {
        out.add(CloudChange(['expenseMap', id], json));
      }
    });
    settlements.forEach((id, json) {
      if (!remote.settlements.containsKey(id)) {
        out.add(CloudChange(['settlementMap', id], json));
      }
    });
    return out;
  }

  /// This view with [changes] applied (the new baseline after a write).
  CloudTripView applying(List<CloudChange> changes) {
    final s = Map<String, Object?>.from(scalars);
    final names = Map<String, String>.from(memberNames);
    final order = Map<String, int>.from(memberOrder);
    final ex = {for (final e in expenses.entries) e.key: e.value};
    final st = {for (final e in settlements.entries) e.key: e.value};
    for (final c in changes) {
      final p = c.path;
      if (p.length == 1) {
        if (c.delete) {
          s[p[0]] = null;
        } else {
          s[p[0]] = c.value;
        }
      } else if (p[0] == 'memberMap') {
        if (p.length == 2) {
          if (c.delete) {
            names.remove(p[1]);
            order.remove(p[1]);
          } else {
            final v = c.value as Map;
            names[p[1]] = v['name'].toString();
            order[p[1]] = (v['order'] as num?)?.toInt() ?? 0;
          }
        } else if (p.length == 3 && p[2] == 'name') {
          names[p[1]] = c.value.toString();
        }
      } else if (p[0] == 'expenseMap') {
        c.delete
            ? ex.remove(p[1])
            : ex[p[1]] = Map<String, dynamic>.from(c.value as Map);
      } else if (p[0] == 'settlementMap') {
        c.delete
            ? st.remove(p[1])
            : st[p[1]] = Map<String, dynamic>.from(c.value as Map);
      }
    }
    return CloudTripView(
      scalars: s,
      memberNames: names,
      memberOrder: order,
      expenses: ex,
      settlements: st,
    );
  }

  /// Reads either schema (2 = maps, legacy = arrays) into a trip update.
  static TripStateUpdate deserialize(
    Map<String, dynamic> data,
    String fallbackCode, {
    bool hasPendingWrites = false,
  }) {
    List<TripMember> members;
    List<ExpenseItem> expenses;
    List<SettlementPayment> settlements;

    if (data['schema'] == schema) {
      final memberMap = (data['memberMap'] as Map?) ?? const {};
      final entries =
          <({String id, String name, int order})>[
            for (final e in memberMap.entries)
              if (e.value is Map)
                (
                  id: e.key.toString(),
                  name: (e.value as Map)['name']?.toString() ?? 'Friend',
                  order: ((e.value as Map)['order'] as num?)?.toInt() ?? 0,
                ),
          ]..sort((a, b) {
            final c = a.order.compareTo(b.order);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
      members = [for (final m in entries) TripMember(id: m.id, name: m.name)];
      expenses =
          [
            for (final v in ((data['expenseMap'] as Map?) ?? const {}).values)
              if (v is Map) ExpenseItem.fromJson(Map<String, dynamic>.from(v)),
          ]..sort((a, b) {
            final c = a.createdAt.compareTo(b.createdAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
      settlements =
          [
            for (final v
                in ((data['settlementMap'] as Map?) ?? const {}).values)
              if (v is Map)
                SettlementPayment.fromJson(Map<String, dynamic>.from(v)),
          ]..sort((a, b) {
            final c = a.paidAt.compareTo(b.paidAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    } else {
      members = ((data['members'] as List?) ?? const []).whereType<Map>().map((
        m,
      ) {
        final map = Map<String, dynamic>.from(m);
        return TripMember(
          id: map['id']?.toString() ?? 'unknown',
          name: map['name']?.toString() ?? 'Friend',
        );
      }).toList();
      expenses = ((data['expenses'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ExpenseItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      settlements = ((data['settlements'] as List?) ?? const [])
          .whereType<Map>()
          .map((s) => SettlementPayment.fromJson(Map<String, dynamic>.from(s)))
          .toList();
    }

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
