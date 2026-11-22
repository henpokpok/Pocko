import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/settlement/pair_breakdown.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/trip_member.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';
import 'package:travmate/services/identity/device_identity.dart';
import 'package:travmate/services/session/session_store.dart';
import 'package:travmate/services/sync/squad_sync_service.dart';

import 'test_helpers.dart';

/// Records what the controller pushes and serves a canned remote group.
class _FakeSync extends SquadSyncService {
  TripStateUpdate? remote;
  final pushes = <TripState>[];

  @override
  bool get isAvailable => true;

  @override
  Stream<TripStateUpdate?> streamTripUpdates(String squadCode) =>
      const Stream.empty();

  @override
  Future<TripStateUpdate?> fetchTrip(String squadCode) async => remote;

  @override
  Future<void> syncTripToCloud(TripState state, {String? writerId}) async {
    pushes.add(state);
  }
}

TripStateUpdate _remoteGroup() {
  final base = TripState.initial();
  return TripStateUpdate(
    trip: base.trip.copyWith(hostUid: 'host_uid'),
    writerId: 'host',
  );
}

Future<SessionStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SessionStore(await SharedPreferences.getInstance());
}

ProviderContainer _container({SessionStore? store, SquadSyncService? sync}) {
  final c = ProviderContainer(
    overrides: [
      if (store != null) sessionStoreProvider.overrideWithValue(store),
      tripControllerProvider.overrideWith(
        () => TripController(syncService: sync),
      ),
      currentUidProvider.overrideWith((ref) => 'host_uid'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Records the member names handed to the AI on every capture.
class _SpyAi extends HybridAiService {
  _SpyAi() : super(isMockEnabled: true, simulateLatency: false);
  final seenNames = <List<String>>[];
  final seenPayers = <String>[];

  @override
  Future<HybridAiResult> parseExpenseText({
    required String text,
    InferenceMode? mode,
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
    bool hasReceipt = false,
    bool fromSpeech = false,
  }) {
    seenNames.add(List.of(memberNames));
    seenPayers.add(defaultPayer);
    return super.parseExpenseText(
      text: text,
      mode: mode,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
      hasReceipt: hasReceipt,
    );
  }
}

void main() {
  group('Renaming keeps every bill intact (ids, not names)', () {
    test(
      'a rename changes the name only: expenses, splits, repayments, balances',
      () {
        final c = _container();
        final n = c.read(tripControllerProvider.notifier);
        n.addExpense(
          ExpenseItem(
            id: 'itemized',
            title: 'Sushiro',
            amount: 3950,
            currency: 'JPY',
            payerId: 'alex',
            splitWithMemberIds: const ['you', 'alex', 'maya'],
            customSplits: const {'you': 1200.0, 'alex': 950.0, 'maya': 1800.0},
            createdAt: DateTime.now(),
          ),
        );
        n.recordRepayment(
          fromMemberId: 'maya',
          toMemberId: 'alex',
          amount: 500,
        );

        final before = c.read(tripControllerProvider);
        final expensesBefore = jsonEncode(
          before.trip.expenses.map((e) => e.toJson()).toList(),
        );
        final paymentsBefore = jsonEncode(
          before.settlements.map((s) => s.toJson()).toList(),
        );
        final netBefore = Map.of(before.netBalances);
        final transfersBefore = before.simplifiedTransfers
            .map((t) => '${t.fromMemberId}>${t.toMemberId}:${t.amount}')
            .toList();

        expect(n.renameMember('alex', 'Pong'), isNull);

        final after = c.read(tripControllerProvider);
        expect(after.nameOf('alex'), 'Pong');
        expect(
          jsonEncode(after.trip.expenses.map((e) => e.toJson()).toList()),
          expensesBefore,
          reason: 'no expense field changes: payerId / customSplits are ids',
        );
        expect(
          jsonEncode(after.settlements.map((s) => s.toJson()).toList()),
          paymentsBefore,
        );
        expect(after.netBalances, netBefore);
        expect(
          after.simplifiedTransfers
              .map((t) => '${t.fromMemberId}>${t.toMemberId}:${t.amount}')
              .toList(),
          transfersBefore,
        );
        // Views that print names pick the new one up at once.
        final b = computePairBreakdown(after, 'maya', 'alex');
        expect(b.aId, 'maya');
        expect(after.nameOf(b.bId), 'Pong');
        // And no stored reference holds the old display name.
        expect(expensesBefore.contains('"Alex"'), isFalse);
      },
    );

    test(
      'validation: blank, too long, duplicate, reserved words, unknown member',
      () {
        final c = _container();
        final n = c.read(tripControllerProvider.notifier);
        expect(n.renameMember('alex', '   '), 'Enter a name.');
        expect(
          n.renameMember('alex', 'x' * 25),
          contains('under ${TripController.maxNameLength}'),
        );
        expect(
          n.renameMember('alex', 'maya'),
          'Someone in this group already uses that name.',
        );
        expect(n.renameMember('alex', 'Me'), contains('other than'));
        expect(n.renameMember('ghost', 'Pong'), contains('no longer'));
        expect(c.read(tripControllerProvider).nameOf('alex'), 'Alex');
        // Same name again is a harmless no-op; case-only changes are allowed.
        expect(n.renameMember('alex', 'Alex'), isNull);
        expect(n.renameMember('alex', 'ALEX'), isNull);
        expect(c.read(tripControllerProvider).trip.members[1].name, 'ALEX');
        // Extra spaces are collapsed.
        expect(n.renameMember('maya', '  Ma   Ya '), isNull);
        expect(c.read(tripControllerProvider).trip.members[2].name, 'Ma Ya');
      },
    );

    test('guests rename only themselves; the Host renames anyone', () {
      var uid = 'host_uid';
      final c = ProviderContainer(
        overrides: [currentUidProvider.overrideWith((ref) => uid)],
      );
      addTearDown(c.dispose);
      final n = c.read(tripControllerProvider.notifier);
      expect(n.renameMember('maya', 'Mayuree'), isNull, reason: 'host');

      uid = 'guest_uid';
      c.invalidate(currentUidProvider);
      // This device is member "you" in the test trip.
      expect(n.renameMember('you', 'Gus'), isNull, reason: 'self');
      expect(
        n.renameMember('liam', 'Lee'),
        'Only you or the Trip Host can rename this traveler.',
      );
    });

    test('renaming yourself remembers the name for the next group', () async {
      final store = await _store();
      final c = _container(store: store);
      final n = c.read(tripControllerProvider.notifier);
      n.startNewTrip(name: 'Trip', currency: 'JPY', friends: ['Maya']);
      expect(n.renameMember('you', 'Pong'), isNull);
      expect(store.displayName, 'Pong');
    });
  });

  group('The AI always sees the latest names', () {
    test('the offline parser maps a renamed friend to the same member id', () {
      final c = _container();
      final n = c.read(tripControllerProvider.notifier);
      n.renameMember('alex', 'Pong');
      final s = c.read(tripControllerProvider);
      final names = s.trip.members.map((m) => m.name).toList();
      expect(names, contains('Pong'));
      expect(names, isNot(contains('Alex')));

      final items = LocalExpenseParser.parseExpenses(
        'Taxi 900 yen with Pong',
        tripCurrency: 'JPY',
        memberNames: names,
        defaultPayer: 'You',
      );
      expect(items.single['splitWith'], contains('Pong'));
    });

    testWidgets('the capture sheet sends the renamed roster on every capture', (
      tester,
    ) async {
      final ai = _SpyAi();
      final container = await pumpPocko(
        tester,
        const AiExpenseCaptureSheet(enableSpeechRecognition: false),
        size: const Size(390, 1100),
        ai: ai,
      );
      final n = container.read(tripControllerProvider.notifier);

      Future<void> capture(String text) async {
        await tester.enterText(
          find.byKey(const ValueKey('capture_text_field')),
          text,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await settle(tester, 1500);
      }

      await capture('Ramen 1200 yen with Alex');
      expect(ai.seenNames.last, contains('Alex'));

      // Back to the input, rename, capture again: no stale cached names.
      await tester.tap(find.byKey(const ValueKey('back_button')));
      await settle(tester, 400);
      expect(n.renameMember('alex', 'Pong'), isNull);
      await capture('Ramen 1200 yen with Pong');
      expect(ai.seenNames.last, contains('Pong'));
      expect(ai.seenNames.last, isNot(contains('Alex')));
      // The reading resolves to the same immutable member id.
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final added = container.read(tripControllerProvider).trip.expenses.last;
      expect(added.splitWithMemberIds, contains('alex'));
      await settle(tester, 1200);
    });
  });

  group('Join Group: set a name first, rename any time', () {
    test('joins as a new traveler with the chosen display name', () async {
      final sync = _FakeSync()..remote = _remoteGroup();
      final c = _container(sync: sync);
      final n = c.read(tripControllerProvider.notifier);
      final r = await n.joinSquad('782 901', displayName: '  Pong  ');
      expect(r, JoinSquadResult.joined);
      final s = c.read(tripControllerProvider);
      expect(s.hasTrip, isTrue);
      expect(s.squadCode, '782-901');
      final me = s.memberById(s.currentMemberId)!;
      expect(me.name, 'Pong');
      expect(me.id, startsWith('mem_'));
      expect(s.trip.members.length, 5);
      expect(
        sync.pushes,
        hasLength(1),
        reason: 'one push: the diff adds this member',
      );
    });

    test('the name is made unique and defaults sensibly', () async {
      final sync = _FakeSync()..remote = _remoteGroup();
      final c = _container(sync: sync);
      final n = c.read(tripControllerProvider.notifier);
      await n.joinSquad('782-901', displayName: 'Maya');
      final s = c.read(tripControllerProvider);
      expect(s.memberById(s.currentMemberId)!.name, 'Maya 2');

      final c2 = _container(sync: sync);
      await c2.read(tripControllerProvider.notifier).joinSquad('782-901');
      final s2 = c2.read(tripControllerProvider);
      expect(s2.memberById(s2.currentMemberId)!.name, 'Traveler 5');
    });

    test('a saved display name is used when none is typed', () async {
      final store = await _store({SessionStore.displayNameKey: 'Pong'});
      final sync = _FakeSync()..remote = _remoteGroup();
      final c = _container(store: store, sync: sync);
      await c.read(tripControllerProvider.notifier).joinSquad('782-901');
      final s = c.read(tripControllerProvider);
      expect(s.memberById(s.currentMemberId)!.name, 'Pong');
    });

    test('invite links and pasted messages work', () async {
      expect(normalizeSquadCode('pocko://join/782901'), '782-901');
      expect(
        normalizeSquadCode('https://pocko.app/join/782-901?x=1'),
        '782-901',
      );
      expect(
        normalizeSquadCode(
          'Join my Pocko trip "Tokyo": pocko://join/782901 (group code 782-901)',
        ),
        '782-901',
      );
      expect(normalizeSquadCode('12345'), isNull);
      expect(normalizeSquadCode('7829011'), isNull);
      expect(squadInviteLink('782-901'), 'pocko://join/782901');

      final sync = _FakeSync()..remote = _remoteGroup();
      final c = _container(sync: sync);
      final r = await c
          .read(tripControllerProvider.notifier)
          .joinSquad('Join me: pocko://join/782901', displayName: 'Pong');
      expect(r, JoinSquadResult.joined);
    });

    test('an unknown code is "not found" and changes nothing when asked not to create', () async {
      final sync = _FakeSync(); // no remote group
      final c = _container(sync: sync);
      final n = c.read(tripControllerProvider.notifier);
      final before = c.read(tripControllerProvider).squadCode;
      final r = await n.joinSquad('555-555', createIfMissing: false);
      expect(r, JoinSquadResult.notFound);
      expect(c.read(tripControllerProvider).squadCode, before);
      expect(sync.pushes, isEmpty);
    });

    test(
      'a device with no trip can join one (placeholder becomes a trip)',
      () async {
        final store = await _store();
        final sync = _FakeSync()..remote = _remoteGroup();
        final c = _container(store: store, sync: sync);
        expect(c.read(tripControllerProvider).hasTrip, isFalse);
        await c
            .read(tripControllerProvider.notifier)
            .joinSquad('782-901', displayName: 'Pong');
        expect(c.read(tripControllerProvider).hasTrip, isTrue);
      },
    );

    test(
      'the name can be changed after joining and the change is pushed',
      () async {
        final sync = _FakeSync()..remote = _remoteGroup();
        final c = _container(sync: sync);
        final n = c.read(tripControllerProvider.notifier);
        await n.joinSquad('782-901', displayName: 'Pong');
        final me = c.read(tripControllerProvider).currentMemberId;
        sync.pushes.clear();
        expect(n.renameMember(me, 'Pongsakorn'), isNull);
        expect(c.read(tripControllerProvider).nameOf(me), 'You');
        expect(
          c.read(tripControllerProvider).memberById(me)!.name,
          'Pongsakorn',
        );
        expect(sync.pushes, hasLength(1));
      },
    );
  });

  group('Local session (first-launch flag and trip survive restarts)', () {
    test('has_seen_landing defaults to false and persists', () async {
      final store = await _store();
      expect(store.hasSeenLanding, isFalse);
      await store.setHasSeenLanding(true);
      expect(store.hasSeenLanding, isTrue);
      final again = SessionStore(await SharedPreferences.getInstance());
      expect(again.hasSeenLanding, isTrue);
    });

    test(
      'a fresh install starts on a harmless placeholder, never a null trip',
      () async {
        final c = _container(store: await _store());
        final s = c.read(tripControllerProvider);
        expect(s.hasTrip, isFalse);
        expect(s.hasNoActiveTrip, isTrue);
        expect(s.trip.members, isNotEmpty);
        expect(s.trip.baseCurrency, isNotEmpty);
        expect(s.trip.expenses, isEmpty);
        // Nothing can be added to it.
        c
            .read(tripControllerProvider.notifier)
            .addExpense(
              ExpenseItem(
                id: 'x',
                title: 'x',
                amount: 5,
                currency: 'USD',
                payerId: 'you',
                splitWithMemberIds: const ['you'],
                createdAt: DateTime.now(),
              ),
            );
        expect(c.read(tripControllerProvider).trip.expenses, isEmpty);
      },
    );

    test(
      'the trip, who you are and repayments come back after a restart',
      () async {
        final store = await _store();
        final first = _container(store: store);
        final n = first.read(tripControllerProvider.notifier);
        n.startNewTrip(name: 'Osaka', currency: 'JPY', friends: ['Maya']);
        n.addExpense(
          ExpenseItem(
            id: 'e1',
            title: 'Takoyaki',
            amount: 800,
            currency: 'JPY',
            payerId: 'you',
            splitWithMemberIds: const ['you'],
            createdAt: DateTime.now(),
          ),
        );
        n.renameMember('you', 'Pong');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final saved = first.read(tripControllerProvider);

        final second = _container(
          store: SessionStore(await SharedPreferences.getInstance()),
        );
        final s = second.read(tripControllerProvider);
        expect(s.hasTrip, isTrue);
        expect(s.trip.name, 'Osaka');
        expect(s.squadCode, saved.squadCode);
        expect(s.currentMemberId, 'you');
        expect(s.trip.members.map((m) => m.name), ['Pong', 'Maya']);
        expect(s.trip.expenses.single.title, 'Takoyaki');
      },
    );

    test('unreadable saved data falls back to the placeholder', () async {
      final store = await _store({SessionStore.sessionKey: '{not json'});
      expect(store.loadSession(), isNull);
      expect(
        _container(store: store).read(tripControllerProvider).hasTrip,
        isFalse,
      );
    });

    test('upcoming trips are flagged (and today is active)', () {
      final base = TripState.initial(squadCode: '111-111');
      final future = base.copyWith(
        trip: base.trip.copyWith(
          startDate: DateTime.now().add(const Duration(days: 9)),
        ),
      );
      expect(future.isUpcoming, isTrue);
      expect(future.hasNoActiveTrip, isTrue);
      expect(base.isUpcoming, isFalse);
      expect(base.hasNoActiveTrip, isFalse);
      final today = base.copyWith(
        trip: base.trip.copyWith(startDate: DateTime.now()),
      );
      expect(today.isUpcoming, isFalse);
      expect(TripState.placeholder(squadCode: '1').hasNoActiveTrip, isTrue);
      expect(const TripMember(id: 'a', name: 'A').name, 'A');
    });
  });
}
