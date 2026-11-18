import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/theme/app_theme.dart';
import 'package:travmate/features/expenses/expenses_canvas_screen.dart';
import 'package:travmate/features/squad/squad_setup_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_permissions.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/identity/device_identity.dart';

import 'test_helpers.dart';

const _denied = 'Only the Trip Host or creator can delete this entry';

/// A container whose "device" can switch person: the trip is built by the host,
/// then [as] makes the same shared trip be used by somebody else.
class _World {
  String uid = 'host_uid';
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      hybridAiServiceProvider.overrideWithValue(testAiService()),
      currentUidProvider.overrideWith((ref) => uid),
    ],
  );

  _World() {
    container.read(tripControllerProvider); // built (and hosted) by host_uid
  }

  TripController get controller =>
      container.read(tripControllerProvider.notifier);
  TripState get state => container.read(tripControllerProvider);

  void as(String newUid) {
    uid = newUid;
    container.invalidate(currentUidProvider);
  }
}

ExpenseItem _item(String id, {String? by}) => ExpenseItem(
  id: id,
  title: 'Item $id',
  amount: 1000,
  currency: 'JPY',
  payerId: 'you',
  splitWithMemberIds: const ['you', 'alex'],
  createdAt: DateTime.now(),
  inferenceSource: InferenceSource.manual,
  createdByUid: by,
);

void main() {
  group('Host vs guest permissions (controller)', () {
    test('the device that creates the trip is its host', () {
      final w = _World();
      addTearDown(w.container.dispose);
      expect(w.state.trip.hostUid, 'host_uid');
      expect(w.container.read(tripPermissionsProvider).isHost, isTrue);
      expect(w.container.read(tripPermissionsProvider).hostMemberId, 'you');
    });

    test('new expenses are stamped with their creator', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.controller.addExpense(_item('h1'));
      expect(
        w.state.trip.expenses.firstWhere((e) => e.id == 'h1').createdByUid,
        'host_uid',
      );
      w.as('guest_uid');
      w.controller.addExpense(_item('g1'));
      expect(
        w.state.trip.expenses.firstWhere((e) => e.id == 'g1').createdByUid,
        'guest_uid',
      );
    });

    test('a guest cannot delete or edit the host\'s entries', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.controller.addExpense(_item('h1'));
      final hostEntry = w.state.trip.expenses.firstWhere((e) => e.id == 'h1');
      w.as('guest_uid');

      expect(w.controller.canModifyExpense(hostEntry), isFalse);
      expect(w.controller.removeExpense('h1'), isNull);
      expect(
        w.controller.updateExpense(hostEntry.copyWith(title: 'Hacked')),
        isFalse,
      );
      final still = w.state.trip.expenses.firstWhere((e) => e.id == 'h1');
      expect(still.title, 'Item h1');
      expect(w.container.read(tripPermissionsProvider).deniedMessage, _denied);
      // Seed data from before creator tracking belongs to the host too.
      expect(w.controller.removeExpense('exp_1'), isNull);
    });

    test('a guest can edit and delete the entries they created', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.as('guest_uid');
      w.controller.addExpense(_item('g1'));
      final mine = w.state.trip.expenses.firstWhere((e) => e.id == 'g1');
      expect(
        w.controller.updateExpense(mine.copyWith(title: 'Mine v2')),
        isTrue,
      );
      expect(
        w.state.trip.expenses.firstWhere((e) => e.id == 'g1').title,
        'Mine v2',
      );
      expect(w.controller.removeExpense('g1'), isNotNull);
    });

    test('the host can edit or delete anything and the creator is kept', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.as('guest_uid');
      w.controller.addExpense(_item('g1'));
      w.as('host_uid');
      final theirs = w.state.trip.expenses.firstWhere((e) => e.id == 'g1');
      expect(
        w.controller.updateExpense(theirs.copyWith(title: 'Fixed')),
        isTrue,
      );
      expect(
        w.state.trip.expenses.firstWhere((e) => e.id == 'g1').createdByUid,
        'guest_uid',
        reason: 'the original creator never changes',
      );
      expect(w.controller.removeExpense('g1'), isNotNull);
    });

    test('Lock Guest Edits freezes guests, but they can still add', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.as('guest_uid');
      w.controller.addExpense(_item('g1'));
      expect(
        w.controller.setLockGuestEdits(true),
        isFalse,
        reason: 'host only',
      );

      w.as('host_uid');
      expect(w.controller.setLockGuestEdits(true), isTrue);
      expect(w.state.trip.lockGuestEdits, isTrue);

      w.as('guest_uid');
      final mine = w.state.trip.expenses.firstWhere((e) => e.id == 'g1');
      expect(w.controller.canModifyExpense(mine), isFalse);
      expect(w.controller.removeExpense('g1'), isNull);
      expect(
        w.container.read(tripPermissionsProvider).deniedMessage,
        'The Trip Host has locked guest edits',
      );
      w.controller.addExpense(_item('g2'));
      expect(w.state.trip.expenses.any((e) => e.id == 'g2'), isTrue);

      w.as('host_uid');
      expect(
        w.controller.removeExpense('g1'),
        isNotNull,
        reason: 'host ignores the lock',
      );
    });

    test('only the host removes travelers and resets repayments', () {
      final w = _World();
      addTearDown(w.container.dispose);
      w.controller.recordRepayment(
        fromMemberId: 'alex',
        toMemberId: 'you',
        amount: 100,
      );
      w.as('guest_uid');
      expect(
        w.controller.removeMember('maya'),
        'Only the Trip Host can remove travelers.',
      );
      w.controller.resetSettledTransfers();
      expect(w.state.settlements.length, 1);
      w.as('host_uid');
      w.controller.resetSettledTransfers();
      expect(w.state.settlements, isEmpty);
    });

    test('legacy trips without a host stay open to everyone', () {
      final trip = TripState.initial().trip;
      expect(trip.hostUid, isNull);
      final p = TripPermissions(trip, 'anyone');
      expect(p.isLegacy, isTrue);
      expect(p.canModify(null), isTrue);
      expect(p.canModify('someone_else'), isTrue);
      expect(p.hostMemberId, isNull);
    });
  });

  group('Repayments (controller)', () {
    test('a repayment is deducted from the net balances at once', () {
      final w = _World();
      addTearDown(w.container.dispose);
      final before = w.state.netBalances;
      final p = w.controller.recordRepayment(
        fromMemberId: 'maya',
        toMemberId: 'alex',
        amount: 2500,
        note: '  cash  ',
      );
      expect(p, isNotNull);
      expect(p!.note, 'cash');
      expect(p.createdByUid, 'host_uid');
      expect(w.state.settlements.single.id, p.id);
      expect(
        w.state.netBalances['maya']!,
        closeTo(before['maya']! + 2500, 0.01),
      );
      expect(
        w.state.netBalances['alex']!,
        closeTo(before['alex']! - 2500, 0.01),
      );
    });

    test('invalid repayments are rejected', () {
      final w = _World();
      addTearDown(w.container.dispose);
      expect(
        w.controller.recordRepayment(
          fromMemberId: 'you',
          toMemberId: 'you',
          amount: 5,
        ),
        isNull,
      );
      expect(
        w.controller.recordRepayment(
          fromMemberId: 'you',
          toMemberId: 'alex',
          amount: 0,
        ),
        isNull,
      );
      expect(
        w.controller.recordRepayment(
          fromMemberId: 'ghost',
          toMemberId: 'alex',
          amount: 5,
        ),
        isNull,
      );
      expect(w.state.settlements, isEmpty);
    });

    test('a guest can only undo the repayments they recorded', () {
      final w = _World();
      addTearDown(w.container.dispose);
      final hostPayment = w.controller.recordRepayment(
        fromMemberId: 'alex',
        toMemberId: 'you',
        amount: 100,
      )!;
      w.as('guest_uid');
      final guestPayment = w.controller.recordRepayment(
        fromMemberId: 'maya',
        toMemberId: 'you',
        amount: 200,
      )!;
      w.controller.undoSettlement(hostPayment.id);
      expect(w.state.settlements.length, 2, reason: 'not theirs');
      w.controller.undoSettlement(guestPayment.id);
      expect(w.state.settlements.single.id, hostPayment.id);
    });

    test(
      'settlement payments survive a JSON round trip with note and slip',
      () {
        final w = _World();
        addTearDown(w.container.dispose);
        final p = w.controller.recordRepayment(
          fromMemberId: 'alex',
          toMemberId: 'you',
          amount: 100,
          note: 'slip attached',
          slipImageBase64: 'QUJD',
        )!;
        final copy = w.state.settlements.single;
        expect(copy.slipImageBase64, 'QUJD');
        expect(p.toJson()['note'], 'slip attached');
      },
    );
  });

  group('Host vs guest permissions (UI)', () {
    Future<_World> pump(
      WidgetTester tester,
      Widget child, {
      required String uid,
      Size size = const Size(420, 2200),
    }) async {
      final w = _World();
      addTearDown(w.container.dispose);
      w.as(uid);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: w.container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: child),
          ),
        ),
      );
      await settle(tester, 300);
      return w;
    }

    testWidgets('a guest swiping the host\'s entry gets the polite message', (
      tester,
    ) async {
      final w = await pump(
        tester,
        ExpensesCanvasScreen(onOpenCaptureModal: () {}),
        uid: 'guest_uid',
      );
      await tester.drag(
        find.text('Akihabara Gachapon & Snacks'),
        const Offset(-500, 0),
      );
      await settle(tester, 800);
      expect(find.text(_denied), findsOneWidget);
      expect(find.text('Akihabara Gachapon & Snacks'), findsOneWidget);
      expect(w.state.trip.expenses.any((e) => e.id == 'exp_3'), isTrue);
    });

    testWidgets('a guest tapping the host\'s entry cannot open the editor', (
      tester,
    ) async {
      await pump(
        tester,
        ExpensesCanvasScreen(onOpenCaptureModal: () {}),
        uid: 'guest_uid',
      );
      await tester.tap(find.text('Akihabara Gachapon & Snacks'));
      await settle(tester, 800);
      expect(find.text(_denied), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
    });

    testWidgets('the host swipes any entry away', (tester) async {
      final w = await pump(
        tester,
        ExpensesCanvasScreen(onOpenCaptureModal: () {}),
        uid: 'host_uid',
      );
      await tester.drag(
        find.text('Akihabara Gachapon & Snacks'),
        const Offset(-500, 0),
      );
      await settle(tester, 800);
      expect(w.state.trip.expenses.any((e) => e.id == 'exp_3'), isFalse);
    });

    testWidgets(
      'Manage Group shows the Host crown and the host-only lock switch',
      (tester) async {
        final w = await pump(
          tester,
          SquadSetupScreen(onLaunchCanvas: () {}),
          uid: 'host_uid',
        );
        expect(find.byKey(const ValueKey('host_badge')), findsOneWidget);
        expect(find.text('👑 Host'), findsOneWidget);
        expect(find.text('Lock Guest Edits'), findsOneWidget);
        final sw = find.byKey(const ValueKey('guest_lock_switch'));
        await tester.ensureVisible(sw);
        await tester.tap(sw);
        await settle(tester, 400);
        expect(w.state.trip.lockGuestEdits, isTrue);
        expect(find.byTooltip('Remove Alex'), findsOneWidget);
      },
    );

    testWidgets('a guest sees the crown but no switch and no remove buttons', (
      tester,
    ) async {
      final w = await pump(
        tester,
        SquadSetupScreen(onLaunchCanvas: () {}),
        uid: 'guest_uid',
      );
      expect(find.byKey(const ValueKey('host_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('guest_lock_switch')), findsNothing);
      expect(find.byTooltip('Remove Alex'), findsNothing);
      expect(w.state.trip.lockGuestEdits, isFalse);
    });
  });
}
