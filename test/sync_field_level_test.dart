import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/settlement_payment.dart';
import 'package:travmate/models/trip_member.dart';
import 'package:travmate/services/sync/cloud_trip_view.dart';

/// A tiny stand-in for the Firestore server: applies field-path changes to a
/// document map exactly like `DocumentReference.update` does.
Map<String, dynamic> _apply(
  Map<String, dynamic> doc,
  List<CloudChange> changes,
) {
  final out = _deep(doc);
  for (final c in changes) {
    Map<String, dynamic> node = out;
    for (var i = 0; i < c.path.length - 1; i++) {
      node = (node[c.path[i]] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    if (c.delete) {
      node.remove(c.path.last);
    } else {
      node[c.path.last] = _deep(c.value);
    }
  }
  return out;
}

dynamic _deep(dynamic v) {
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): _deep(e.value)};
  }
  if (v is List) return [for (final e in v) _deep(e)];
  return v;
}

ExpenseItem _exp(String id, {double amount = 1000, String title = 'Item'}) =>
    ExpenseItem(
      id: id,
      title: '$title $id',
      amount: amount,
      currency: 'JPY',
      payerId: 'you',
      splitWithMemberIds: const ['you', 'maya'],
      customSplits: id == 'e_custom' ? {'you': 400.0, 'maya': 600.0} : null,
      createdAt: DateTime(2026, 11, 16, 12),
      inferenceSource: InferenceSource.manual,
    );

final TripState _base = TripState.initial(squadCode: '123-456');

TripState _state({
  List<TripMember>? members,
  List<ExpenseItem>? expenses,
  List<SettlementPayment> settlements = const [],
  String tripName = 'Tokyo',
}) {
  return _base.copyWith(
    trip: _base.trip.copyWith(
      name: tripName,
      members:
          members ??
          const [
            TripMember(id: 'you', name: 'You'),
            TripMember(id: 'maya', name: 'Maya'),
          ],
      expenses: expenses ?? [_exp('e1'), _exp('e2')],
    ),
    settlements: settlements,
  );
}

String _paths(List<CloudChange> c) =>
    (c.map((e) => e.toString()).toList()..sort()).join(' | ');

void main() {
  group('Field-level diff (no more whole-document overwrites)', () {
    test('an unchanged state writes nothing', () {
      final v = CloudTripView.fromState(_state());
      expect(CloudTripView.fromState(_state()).diffFrom(v), isEmpty);
    });

    test('adding one expense writes only that expense entry', () {
      final before = CloudTripView.fromState(_state());
      final after = CloudTripView.fromState(
        _state(expenses: [_exp('e1'), _exp('e2'), _exp('e3')]),
      );
      expect(_paths(after.diffFrom(before)), 'set expenseMap.e3');
    });

    test(
      'editing one expense writes only that entry; deleting removes only it',
      () {
        final before = CloudTripView.fromState(_state());
        final edited = CloudTripView.fromState(
          _state(expenses: [_exp('e1', amount: 2500), _exp('e2')]),
        );
        expect(_paths(edited.diffFrom(before)), 'set expenseMap.e1');
        final deleted = CloudTripView.fromState(_state(expenses: [_exp('e2')]));
        expect(_paths(deleted.diffFrom(before)), 'delete expenseMap.e1');
      },
    );

    test('a rename writes exactly one name field and nothing else', () {
      final before = CloudTripView.fromState(_state());
      final renamed = CloudTripView.fromState(
        _state(
          members: const [
            TripMember(id: 'you', name: 'Pong'),
            TripMember(id: 'maya', name: 'Maya'),
          ],
        ),
      );
      final changes = renamed.diffFrom(before);
      expect(_paths(changes), 'set memberMap.you.name');
      expect(changes.single.value, 'Pong');
    });

    test('a join writes only the new member entry, with its position', () {
      final before = CloudTripView.fromState(_state());
      final joined = CloudTripView.fromState(
        _state(
          members: const [
            TripMember(id: 'you', name: 'You'),
            TripMember(id: 'maya', name: 'Maya'),
            TripMember(id: 'mem_9', name: 'Pong'),
          ],
        ),
      );
      final changes = joined.diffFrom(before);
      expect(_paths(changes), 'set memberMap.mem_9');
      expect(changes.single.value, {'name': 'Pong', 'order': 2});
    });

    test('repayments and trip fields are targeted too', () {
      final before = CloudTripView.fromState(_state());
      final after = CloudTripView.fromState(
        _state(
          tripName: 'Osaka',
          settlements: [
            SettlementPayment(
              id: 'p1',
              fromMemberId: 'maya',
              toMemberId: 'you',
              amount: 100,
              currency: 'JPY',
              paidAt: DateTime(2026, 11, 17),
            ),
          ],
        ),
      );
      expect(_paths(after.diffFrom(before)), 'set name | set settlementMap.p1');
    });
  });

  group('Two devices editing at the same time never erase each other', () {
    test(
      'a join, a rename and a new expense from three devices all survive',
      () {
        final base = _state();
        final baseline = CloudTripView.fromState(base);
        var server = baseline.toDocument();

        // Device A (still on the old state) adds an expense.
        final a = CloudTripView.fromState(
          _state(expenses: [_exp('e1'), _exp('e2'), _exp('a_new')]),
        );
        // Device B joins the group.
        final b = CloudTripView.fromState(
          _state(
            members: const [
              TripMember(id: 'you', name: 'You'),
              TripMember(id: 'maya', name: 'Maya'),
              TripMember(id: 'mem_b', name: 'Bee'),
            ],
          ),
        );
        // Device C renames Maya.
        final c = CloudTripView.fromState(
          _state(
            members: const [
              TripMember(id: 'you', name: 'You'),
              TripMember(id: 'maya', name: 'Mayuree'),
            ],
          ),
        );

        // All three changes reach the server in an arbitrary order.
        for (final changes in [
          c.diffFrom(baseline),
          a.diffFrom(baseline),
          b.diffFrom(baseline),
        ]) {
          server = _apply(server, changes);
        }

        final merged = CloudTripView.deserialize(server, '123-456');
        expect(merged.trip.members.map((m) => '${m.id}:${m.name}'), [
          'you:You',
          'maya:Mayuree',
          'mem_b:Bee',
        ]);
        expect(
          merged.trip.expenses.map((e) => e.id),
          containsAll(['e1', 'e2', 'a_new']),
        );
      },
    );

    test(
      'the OLD whole-document write would have lost them (why this matters)',
      () {
        final baseline = CloudTripView.fromState(_state());
        final joinedOnServer = _apply(baseline.toDocument(), [
          const CloudChange(
            ['memberMap', 'mem_b'],
            {'name': 'Bee', 'order': 2},
          ),
        ]);
        // A stale device re-uploading its full document replaces members.
        final stale = CloudTripView.fromState(
          _state(expenses: [_exp('e1'), _exp('e2'), _exp('a_new')]),
        ).toDocument();
        final overwritten = CloudTripView.deserialize(stale, 'x');
        expect(overwritten.trip.members.any((m) => m.id == 'mem_b'), isFalse);
        // ...while the field-level update keeps the joiner.
        final fieldLevel = _apply(
          joinedOnServer,
          CloudTripView.fromState(
            _state(expenses: [_exp('e1'), _exp('e2'), _exp('a_new')]),
          ).diffFrom(baseline),
        );
        expect(
          CloudTripView.deserialize(
            fieldLevel,
            'x',
          ).trip.members.any((m) => m.id == 'mem_b'),
          isTrue,
        );
      },
    );

    test('a restarted device only ADDS what the cloud lacks (never deletes or overwrites)', () {
      final remote = CloudTripView.fromState(
        _state(
          members: const [
            TripMember(id: 'you', name: 'Pong'), // renamed elsewhere
            TripMember(id: 'maya', name: 'Maya'),
            TripMember(id: 'mem_x', name: 'Xi'),
          ],
          expenses: [_exp('e1', amount: 9999), _exp('e2'), _exp('theirs')],
        ),
      );
      // Stale local copy: old name, old amount, no 'theirs', one new expense.
      final local = CloudTripView.fromState(
        _state(expenses: [_exp('e1'), _exp('mine')]),
      );
      final adds = local.additiveFrom(remote);
      expect(_paths(adds), 'set expenseMap.mine');
      final merged = _apply(remote.toDocument(), adds);
      final result = CloudTripView.deserialize(merged, 'x');
      expect(
        result.trip.members.first.name,
        'Pong',
        reason: 'cloud rename kept',
      );
      expect(
        result.trip.expenses.firstWhere((e) => e.id == 'e1').amount,
        9999,
        reason: 'cloud edit kept',
      );
      expect(result.trip.expenses.any((e) => e.id == 'theirs'), isTrue);
      expect(result.trip.expenses.any((e) => e.id == 'mine'), isTrue);
    });
  });

  group('Document schema', () {
    test(
      'a v2 document round-trips and keeps member order and custom splits',
      () {
        final state = _state(
          members: const [
            TripMember(id: 'you', name: 'You'),
            TripMember(id: 'zed', name: 'Zed'),
            TripMember(id: 'amy', name: 'Amy'),
          ],
          expenses: [_exp('e_custom')],
        );
        final doc = CloudTripView.fromState(state).toDocument();
        final back = CloudTripView.deserialize(doc, '123-456');
        expect(back.trip.members.map((m) => m.id), ['you', 'zed', 'amy']);
        final e = back.trip.expenses.single;
        expect(e.customSplits, {'you': 400.0, 'maya': 600.0});
        expect(e.payerId, 'you');
      },
    );

    test('canonical comparison ignores key order from Firestore', () {
      final view = CloudTripView.fromState(_state());
      // Firestore returns maps in its own key order.
      final reordered = <String, dynamic>{
        for (final k in (view.toDocument().keys.toList().reversed))
          k: view.toDocument()[k],
      };
      final read = CloudTripView.fromDoc(reordered)!;
      expect(CloudTripView.fromState(_state()).diffFrom(read), isEmpty);
    });

    test(
      'legacy array documents are still readable and flagged for migration',
      () {
        final legacy = {
          'id': 't',
          'name': 'Old',
          'members': [
            {'id': 'you', 'name': 'You'},
            {'id': 'amy', 'name': 'Amy'},
          ],
          'expenses': [_exp('e1').toJson()],
          'settlements': [],
        };
        expect(CloudTripView.fromDoc(legacy), isNull);
        final read = CloudTripView.deserialize(legacy, '000-000');
        expect(read.trip.members.length, 2);
        expect(read.trip.expenses.single.id, 'e1');
      },
    );
  });
}
