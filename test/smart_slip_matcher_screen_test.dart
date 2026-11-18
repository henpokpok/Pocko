import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/slip_status.dart';
import 'package:travmate/core/widgets/telemetry_pill.dart';
import 'package:travmate/features/matcher/smart_slip_matcher_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

void main() {
  const tall = Size(420, 3200);

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
  }

  testWidgets(
    'Shows each logged expense next to its candidate slip with ✓ Correct / ✕ Wrong',
    (tester) async {
      await pumpPocko(tester, const SmartSlipMatcherScreen(), size: tall);

      expect(find.text('Smart Slip\nMatcher'), findsOneWidget);
      expect(find.text('DETECTED SLIP MATCHES (3)'), findsOneWidget);
      expect(find.text('LOGGED EXPENSE'), findsWidgets);
      expect(find.text('CANDIDATE SLIP'), findsWidgets);
      expect(find.text('Correct'), findsNWidgets(3));
      expect(find.text('Wrong'), findsNWidgets(3));
      expect(find.textContaining('Exact match'), findsNWidgets(3));
      expect(find.text('Batch Confirm & Split (3)'), findsOneWidget);
      expect(find.text('Upload Slip Photo'), findsOneWidget);
      expect(find.text('Sample Slips'), findsOneWidget);
      // exp_5 has no slip yet: it waits with Choose slip / Paid in Cash.
      expect(find.text('WAITING FOR A SLIP (1)'), findsOneWidget);
      expect(find.text('Paid in Cash'), findsOneWidget);
      expect(find.text('Choose slip'), findsOneWidget);
    },
  );

  testWidgets(
    'Every card carries a compact telemetry footer in the exact format',
    (tester) async {
      await pumpPocko(tester, const SmartSlipMatcherScreen(), size: tall);
      expect(find.byType(TelemetryFooter), findsNWidgets(4));
      expect(find.text('🟢 (Local) • 71ms'), findsOneWidget);
      expect(find.text('🟢 (Local) • 68ms'), findsOneWidget);
      expect(find.text('🟢 (Local) • 74ms'), findsOneWidget);
      expect(
        find.text('🟢 (Local) • 98ms'),
        findsOneWidget,
        reason: 'waiting card uses the expense',
      );
    },
  );

  testWidgets('✓ Correct verifies one pair and lowers the batch count', (
    tester,
  ) async {
    final container = await pumpPocko(
      tester,
      const SmartSlipMatcherScreen(),
      size: tall,
    );
    await tapKey(tester, 'approve_slip_1');
    await settle(tester, 500);

    final state = container.read(tripControllerProvider);
    expect(state.slips.firstWhere((s) => s.id == 'slip_1').isConfirmed, isTrue);
    expect(
      state.trip.expenses.firstWhere((e) => e.id == 'exp_3').slipStatus,
      SlipStatus.matched,
    );
    expect(find.text('Batch Confirm & Split (2)'), findsOneWidget);
    expect(find.text('DETECTED SLIP MATCHES (2)'), findsOneWidget);
  });

  testWidgets('Batch confirm verifies every proposed pair at once', (
    tester,
  ) async {
    final container = await pumpPocko(
      tester,
      const SmartSlipMatcherScreen(),
      size: tall,
    );
    await tester.ensureVisible(find.text('Batch Confirm & Split (3)'));
    await tester.tap(find.text('Batch Confirm & Split (3)'));
    await settle(tester, 600);

    final state = container.read(tripControllerProvider);
    expect(state.pendingSlips, isEmpty);
    expect(
      state.trip.expenses
          .where((e) => e.slipStatus == SlipStatus.matched)
          .length,
      6,
      reason: '3 seeded + 3 newly verified',
    );
    expect(find.textContaining('DETECTED SLIP MATCHES'), findsNothing);
  });

  group('✕ Wrong', () {
    testWidgets('opens the sheet with Paid in Cash, other slips and gallery', (
      tester,
    ) async {
      await pumpPocko(tester, const SmartSlipMatcherScreen(), size: tall);
      await tapKey(tester, 'reject_slip_3');
      await settle(tester, 600);

      expect(find.textContaining('Which slip belongs to'), findsOneWidget);
      expect(find.text('Paid in Cash (No Slip Needed)'), findsOneWidget);
      expect(find.text('OTHER SLIPS I FOUND'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick_slip_slip_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick_slip_slip_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick_slip_slip_3')), findsNothing);
      expect(find.byKey(const ValueKey('wrong_gallery')), findsOneWidget);
      expect(
        find.text('Card alert • TeamLab', skipOffstage: false),
        findsOneWidget,
        reason: 'sample slips are offered too',
      );
    });

    testWidgets('the sheet honours the global 80% height cap', (tester) async {
      await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: const Size(420, 700),
      );
      await tapKey(tester, 'reject_slip_3');
      await settle(tester, 600);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(700 * 0.80 + 0.5));
    });

    testWidgets('Paid in Cash marks the expense and detaches its slip', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: tall,
      );
      await tapKey(tester, 'reject_slip_3');
      await settle(tester, 600);
      await tester.tap(find.byKey(const ValueKey('wrong_cash')));
      await settle(tester, 700);

      final state = container.read(tripControllerProvider);
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_6').slipStatus,
        SlipStatus.cash,
      );
      expect(
        state.slips.firstWhere((s) => s.id == 'slip_3').targetExpenseId,
        isNull,
      );
      expect(
        find.text('DETECTED SLIP MATCHES (3)'),
        findsOneWidget,
        reason: 'orphan slip stays as slip-only card',
      );
      expect(find.text('Batch Confirm & Split (2)'), findsOneWidget);
    });

    testWidgets('choosing a different slip re-links and verifies the pair', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: tall,
      );
      await tapKey(tester, 'reject_slip_3');
      await settle(tester, 600);
      await tester.tap(find.byKey(const ValueKey('pick_slip_slip_1')));
      await settle(tester, 700);

      final state = container.read(tripControllerProvider);
      final slip1 = state.slips.firstWhere((s) => s.id == 'slip_1');
      expect(slip1.targetExpenseId, 'exp_6');
      expect(slip1.isConfirmed, isTrue);
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_6').slipStatus,
        SlipStatus.matched,
      );
      expect(
        state.slips.firstWhere((s) => s.id == 'slip_3').targetExpenseId,
        isNull,
      );
    });
  });

  testWidgets('Waiting cards: Paid in Cash marks the expense without a slip', (
    tester,
  ) async {
    final container = await pumpPocko(
      tester,
      const SmartSlipMatcherScreen(),
      size: tall,
    );
    await tapKey(tester, 'cash_exp_5');
    await settle(tester, 600);
    expect(
      container
          .read(tripControllerProvider)
          .trip
          .expenses
          .firstWhere((e) => e.id == 'exp_5')
          .slipStatus,
      SlipStatus.cash,
    );
    expect(find.textContaining('WAITING FOR A SLIP'), findsNothing);
  });

  testWidgets('Waiting cards: Choose slip opens the same chooser sheet', (
    tester,
  ) async {
    await pumpPocko(tester, const SmartSlipMatcherScreen(), size: tall);
    await tapKey(tester, 'choose_exp_5');
    await settle(tester, 600);
    expect(find.textContaining('TeamLab Borderless Tickets'), findsWidgets);
    expect(find.text('Paid in Cash (No Slip Needed)'), findsOneWidget);
    expect(find.text('OTHER SLIPS I FOUND'), findsOneWidget);
  });

  testWidgets(
    'Local sample: PII is masked on-device, auto-matches TeamLab and shows a (Sim) footer',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: tall,
      );

      await tester.tap(find.text('Sample Slips'));
      await settle(tester, 500);
      expect(find.text('Try a sample slip'), findsOneWidget);
      await tester.tap(find.text('Card alert • TeamLab'));
      await settle(tester, 1500);

      final slip = container.read(tripControllerProvider).slips.first;
      expect(slip.merchant, 'TEAMLAB BORDERLESS TOKYO');
      expect(slip.targetExpenseId, 'exp_5');
      expect(slip.maskedAccount, '•••• 5521');
      expect(find.text('DETECTED SLIP MATCHES (4)'), findsOneWidget);
      expect(find.byKey(ValueKey('footer_${slip.id}')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('footer_${slip.id}')),
          matching: find.textContaining('(Sim) • '),
        ),
        findsOneWidget,
        reason: 'simulated engine is labelled honestly',
      );
    },
  );

  testWidgets(
    'Cloud sample: itemized EUR receipt shows ☁️ footer and offers Create expense',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: tall,
      );

      await tester.tap(find.text('Sample Slips'));
      await settle(tester, 500);
      await tester.tap(find.text('Paris bistro receipt (EUR)'));
      await settle(tester, 2000);

      final slip = container.read(tripControllerProvider).slips.first;
      expect(slip.currency, 'EUR');
      expect(slip.lineItems.length, 5);
      expect(slip.targetExpenseId, isNull);

      expect(find.text('Manual verification required'), findsOneWidget);
      expect(find.text('Create expense'), findsOneWidget);
      expect(find.text('Link to expense'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('footer_${slip.id}')),
          matching: find.textContaining('☁️ (Sim) • '),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('5 line items'), findsWidgets);
      expect(find.textContaining('≈ ¥'), findsOneWidget);
    },
  );

  testWidgets(
    'Create expense from a foreign receipt logs it already verified',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: tall,
      );
      final before = container
          .read(tripControllerProvider)
          .trip
          .expenses
          .length;

      await tester.tap(find.text('Sample Slips'));
      await settle(tester, 500);
      await tester.tap(find.text('Seoul night-market (KRW)'));
      await settle(tester, 2000);

      await tester.ensureVisible(find.text('Create expense'));
      await tester.tap(find.text('Create expense'));
      await settle(tester, 600);
      expect(find.text('Edit Details & Splits'), findsOneWidget);
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await settle(tester, 800);

      final state = container.read(tripControllerProvider);
      expect(state.trip.expenses.length, before + 1);
      final created = state.trip.expenses.last;
      expect(created.currency, 'KRW');
      expect(created.amount, 26000);
      expect(created.slipStatus, SlipStatus.matched);
      expect(state.slips.first.isConfirmed, isTrue);
    },
  );

  testWidgets('Confirming everything leaves the empty state consistent', (
    tester,
  ) async {
    final container = await pumpPocko(
      tester,
      const SmartSlipMatcherScreen(),
      size: tall,
    );
    container.read(tripControllerProvider.notifier).confirmSlips([
      'slip_1',
      'slip_2',
      'slip_3',
    ]);
    await settle(tester, 500);
    expect(find.textContaining('DETECTED SLIP MATCHES'), findsNothing);
    expect(find.text('WAITING FOR A SLIP (1)'), findsOneWidget);
    expect(find.text('VERIFIED SLIPS (3)'), findsOneWidget);
  });

  testWidgets(
    'Works on a 320 x 568 phone and in the two-column desktop layout',
    (tester) async {
      await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);

      await pumpPocko(
        tester,
        const SmartSlipMatcherScreen(),
        size: const Size(1180, 820),
      );
      final header = tester.getTopLeft(find.text('Smart Slip\nMatcher'));
      final list = tester.getTopLeft(find.text('DETECTED SLIP MATCHES (3)'));
      expect(list.dx, greaterThan(header.dx + 300));
      expect(tester.takeException(), isNull);
    },
  );
}
