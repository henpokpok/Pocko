import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/media/receipt_photo_service.dart';
import 'package:travmate/features/settle/transfer_lane_card.dart';
import 'package:travmate/features/settle/visual_settle_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

void main() {
  const tall = Size(420, 3400);

  testWidgets('Shows the donut, live balances and the optimized transfers', (
    tester,
  ) async {
    final container = await pumpPocko(
      tester,
      const VisualSettleScreen(),
      size: tall,
    );

    expect(find.text('CATEGORY BREAKDOWN'), findsOneWidget);
    expect(find.text('NET BALANCE SNAPSHOT'), findsOneWidget);
    expect(find.text('OPTIMIZED SETTLEMENT TRANSFERS (3)'), findsOneWidget);
    expect(find.text('Record Payment'), findsNWidgets(3));
    expect(
      container.read(tripControllerProvider).simplifiedTransfers.length,
      3,
    );
    expect(find.text('+¥7,225'), findsWidgets, reason: 'Alex is owed ¥7,225');
  });

  group('Directional transfer lanes', () {
    testWidgets('Each transfer is a debtor → amount → creditor lane', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      final transfers = container
          .read(tripControllerProvider)
          .simplifiedTransfers;
      expect(transfers.length, 3);
      // The old curved-wire graph and "How to pay" are gone.
      expect(find.text('WHO OWES WHOM'), findsNothing);
      expect(find.byKey(const ValueKey('debt_graph')), findsNothing);
      expect(find.text('How to pay'), findsNothing);

      for (final t in transfers) {
        final from = tester.getCenter(
          find.byKey(ValueKey('lane_from_${t.id}')),
        );
        final pill = tester.getCenter(
          find.byKey(ValueKey('lane_amount_${t.id}')),
        );
        final to = tester.getCenter(find.byKey(ValueKey('lane_to_${t.id}')));
        expect(from.dx, lessThan(pill.dx), reason: 'debtor sits on the left');
        expect(pill.dx, lessThan(to.dx), reason: 'creditor sits on the right');
        expect(find.byKey(ValueKey('lane_arrow_${t.id}')), findsOneWidget);
      }
      for (final amount in ['¥7,225', '¥3,450', '¥575']) {
        expect(find.text(amount), findsWidgets, reason: '$amount pill');
      }
      expect(find.text('pays'), findsNWidgets(3));
      expect(find.text('receives'), findsNWidgets(3));
    });

    testWidgets('A lane expands into the itemized "why this amount"', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      final big = container
          .read(tripControllerProvider)
          .simplifiedTransfers
          .firstWhere((t) => t.amount == 7225);
      expect(find.byKey(ValueKey('lane_breakdown_${big.id}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('lane_expand_${big.id}')));
      await settle(tester, 500);
      expect(find.byKey(ValueKey('lane_breakdown_${big.id}')), findsOneWidget);
      expect(find.textContaining('Maya owes Alex'), findsOneWidget);
      expect(find.textContaining('TeamLab Borderless Tickets'), findsWidgets);
      expect(find.text('Hide breakdown'), findsOneWidget);
    });

    testWidgets(
      'Record Payment opens a pre-filled sheet; saving deducts it from the plan',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const VisualSettleScreen(),
          size: tall,
        );
        final t = container
            .read(tripControllerProvider)
            .simplifiedTransfers
            .firstWhere((t) => t.amount == 7225);
        await tester.tap(find.byKey(ValueKey('lane_record_${t.id}')));
        await settle(tester, 700);

        expect(find.text('Record Repayment'), findsWidgets);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('repay_amount')))
              .controller!
              .text,
          '7225',
        );
        await tester.tap(find.byKey(const ValueKey('repay_save')));
        await settle(tester, 700);

        final state = container.read(tripControllerProvider);
        expect(state.settlements.length, 1);
        expect(state.settlements.single.amount, 7225);
        expect(find.text('OPTIMIZED SETTLEMENT TRANSFERS (2)'), findsOneWidget);
        expect(find.text('REPAYMENT HISTORY (1)'), findsOneWidget);
        expect(find.textContaining('paid back'), findsWidgets);
      },
    );

    testWidgets(
      'The lanes update when payments are recorded and vanish when all are square',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const VisualSettleScreen(),
          size: tall,
        );
        final notifier = container.read(tripControllerProvider.notifier);
        final first = container
            .read(tripControllerProvider)
            .simplifiedTransfers
            .first;
        notifier.markTransferSettled(first.id);
        await settle(tester, 600);
        expect(find.byKey(ValueKey('transfer_${first.id}')), findsNothing);

        for (final t in List.of(
          container.read(tripControllerProvider).simplifiedTransfers,
        )) {
          notifier.markTransferSettled(t.id);
        }
        await settle(tester, 600);
        expect(find.byType(TransferLaneCard), findsNothing);
        expect(
          find.text('All settled with 0 awkward math! 🎉'),
          findsOneWidget,
        );
      },
    );
  });

  group('Record Repayment', () {
    const tinyPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    testWidgets(
      'the + button logs "Maya paid back You" and deducts it at once',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const VisualSettleScreen(),
          size: tall,
        );
        final before = container.read(tripControllerProvider).netBalances;

        await tester.tap(find.byKey(const ValueKey('record_repayment_button')));
        await settle(tester, 700);
        await tester.tap(find.byKey(const ValueKey('repay_from')));
        await settle(tester, 400);
        await tester.tap(find.byKey(const ValueKey('selector_row_Maya')));
        await settle(tester, 400);
        await tester.enterText(
          find.byKey(const ValueKey('repay_amount')),
          '2500',
        );
        await tester.enterText(
          find.byKey(const ValueKey('repay_note')),
          'Cash at the hotel',
        );
        await tester.tap(find.byKey(const ValueKey('repay_save')));
        await settle(tester, 700);

        final state = container.read(tripControllerProvider);
        final p = state.settlements.single;
        expect(p.fromMemberId, 'maya');
        expect(p.toMemberId, 'you');
        expect(p.note, 'Cash at the hotel');
        expect(p.createdByUid, isNotNull);
        expect(
          state.netBalances['maya']!,
          closeTo(before['maya']! + 2500, 0.01),
          reason: 'the debtor owes less',
        );
        expect(
          state.netBalances['you']!,
          closeTo(before['you']! - 2500, 0.01),
          reason: 'the creditor is owed less',
        );
        expect(find.text('REPAYMENT HISTORY (1)'), findsOneWidget);
        expect(find.byKey(ValueKey('repayment_title_${p.id}')), findsOneWidget);
        expect(find.text('Maya paid back You • ¥2,500'), findsOneWidget);
      },
    );

    testWidgets('validates the people and the amount', (tester) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      await tester.tap(find.byKey(const ValueKey('record_repayment_button')));
      await settle(tester, 700);
      await tester.tap(find.byKey(const ValueKey('repay_save')));
      await settle(tester, 300);
      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('repay_amount')), '100');
      // From = To is rejected.
      await tester.tap(find.byKey(const ValueKey('repay_from')));
      await settle(tester, 400);
      await tester.tap(find.byKey(const ValueKey('selector_row_You')));
      await settle(tester, 400);
      await tester.tap(find.byKey(const ValueKey('repay_save')));
      await settle(tester, 300);
      expect(find.text('Choose two different people.'), findsOneWidget);
      expect(container.read(tripControllerProvider).settlements, isEmpty);
    });

    testWidgets('a slip photo is stored, shown and opens full screen', (
      tester,
    ) async {
      final original = ReceiptPhotoService.pick;
      addTearDown(() => ReceiptPhotoService.pick = original);
      ReceiptPhotoService.pick = (_) async =>
          const ReceiptPhotoResult.ok(tinyPng);

      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      await tester.tap(find.byKey(const ValueKey('record_repayment_button')));
      await settle(tester, 700);
      await tester.enterText(find.byKey(const ValueKey('repay_amount')), '900');
      final gallery = find.byKey(const ValueKey('receipt_gallery'));
      await tester.ensureVisible(gallery);
      await tester.tap(gallery);
      await settle(tester, 500);
      expect(find.byKey(const ValueKey('receipt_preview')), findsOneWidget);
      final save = find.byKey(const ValueKey('repay_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await settle(tester, 300);
      // Alex owes less than ¥900: the typo guard asks for a second tap.
      expect(find.textContaining('Tap Record Repayment again'), findsOneWidget);
      await tester.tap(save);
      await settle(tester, 700);

      final p = container.read(tripControllerProvider).settlements.single;
      expect(p.slipImageBase64, tinyPng);
      final slip = find.byKey(ValueKey('repayment_slip_${p.id}'));
      expect(slip, findsOneWidget);
      await tester.ensureVisible(slip);
      await tester.tap(slip);
      await settle(tester, 500);
      expect(find.byKey(const ValueKey('receipt_fullscreen')), findsOneWidget);
    });

    testWidgets('Undo removes a recorded repayment', (tester) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      final notifier = container.read(tripControllerProvider.notifier);
      notifier.recordRepayment(
        fromMemberId: 'maya',
        toMemberId: 'you',
        amount: 500,
      );
      await settle(tester, 600);
      expect(find.text('REPAYMENT HISTORY (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Undo').first);
      await tester.tap(find.text('Undo').first);
      await settle(tester, 600);
      expect(container.read(tripControllerProvider).settlements, isEmpty);
      expect(find.text('REPAYMENT HISTORY (1)'), findsNothing);
    });
  });

  group('Your itemized breakdown', () {
    testWidgets(
      'Lists every person with what you owe or are owed; expands to the exact expenses',
      (tester) async {
        await pumpPocko(tester, const VisualSettleScreen(), size: tall);
        expect(find.text('YOUR ITEMIZED BREAKDOWN'), findsOneWidget);
        for (final other in ['alex', 'maya', 'liam']) {
          expect(find.byKey(ValueKey('pair_$other')), findsOneWidget);
        }
        expect(find.text('You owe Alex'), findsOneWidget);
        expect(find.text('¥1,950'), findsWidgets);

        await tester.ensureVisible(find.byKey(const ValueKey('pair_alex')));
        await tester.tap(find.text('You owe Alex'));
        await settle(tester, 500);

        expect(find.textContaining('TeamLab Borderless Tickets'), findsWidgets);
        expect(
          find.textContaining('Alex paid ¥15,400 • your share'),
          findsOneWidget,
        );
        expect(
          find.text('-¥3,850'),
          findsOneWidget,
          reason: 'your exact share of the TeamLab tickets',
        );
        expect(
          find.textContaining('You paid ¥4,800 • Alex’s share'),
          findsOneWidget,
        );
        expect(find.text('+¥1,200'), findsOneWidget);
        expect(find.text('Net after 4 items'), findsOneWidget);
      },
    );

    testWidgets(
      'A pair with a pending transfer offers Mark Settled right there',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const VisualSettleScreen(),
          size: tall,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('pair_liam')));
        await tester.tap(find.text('You owe Liam'));
        await settle(tester, 500);

        final button = find.byKey(const ValueKey('pair_settle_liam'));
        expect(button, findsOneWidget);
        expect(
          find.descendant(
            of: button,
            matching: find.text('Mark Settled • ¥575'),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('fewest transfers'),
          findsOneWidget,
          reason: 'explains plan vs direct total',
        );

        await tester.ensureVisible(button);
        await tester.tap(button);
        await settle(tester, 700);
        expect(
          container
              .read(tripControllerProvider)
              .settlements
              .single
              .fromMemberId,
          'you',
        );
      },
    );
  });

  testWidgets(
    'A settled transfer recalculates balances, offers Undo and lists the repayment',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );

      final first = container
          .read(tripControllerProvider)
          .simplifiedTransfers
          .first;
      container
          .read(tripControllerProvider.notifier)
          .markTransferSettled(first.id);
      await settle(tester, 700);

      var state = container.read(tripControllerProvider);
      expect(state.settlements.length, 1);
      expect(find.text('OPTIMIZED SETTLEMENT TRANSFERS (2)'), findsOneWidget);
      expect(find.text('REPAYMENT HISTORY (1)'), findsOneWidget);
      expect(find.textContaining('paid back'), findsOneWidget);

      await tester.tap(find.text('Undo').first);
      await settle(tester, 700);
      state = container.read(tripControllerProvider);
      expect(state.settlements, isEmpty);
      expect(find.text('OPTIMIZED SETTLEMENT TRANSFERS (3)'), findsOneWidget);
    },
  );

  testWidgets(
    'Settling every transfer shows the celebration and Reset restores the plan',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      final notifier = container.read(tripControllerProvider.notifier);
      for (final t in List.of(
        container.read(tripControllerProvider).simplifiedTransfers,
      )) {
        notifier.markTransferSettled(t.id);
      }
      await settle(tester, 700);

      expect(find.text('All settled with 0 awkward math! 🎉'), findsOneWidget);
      await tester.ensureVisible(find.text('Reset Settle Status'));
      await tester.tap(find.text('Reset Settle Status'));
      await settle(tester, 700);
      expect(find.text('OPTIMIZED SETTLEMENT TRANSFERS (3)'), findsOneWidget);
    },
  );

  testWidgets(
    'Currency switch converts transfers, graph pills and breakdowns instantly',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: tall,
      );
      container.read(tripControllerProvider.notifier).updateBaseCurrency('USD');
      await settle(tester, 800);
      expect(
        find.text('\$48.17'),
        findsWidgets,
        reason: '¥7,225 at 150 JPY/USD',
      );
      expect(find.textContaining('¥7,225'), findsNothing);
    },
  );

  testWidgets('Empty trip shows the nothing-to-settle state', (tester) async {
    final container = await pumpPocko(
      tester,
      const VisualSettleScreen(),
      size: tall,
    );
    final notifier = container.read(tripControllerProvider.notifier);
    for (final e in List.of(
      container.read(tripControllerProvider).trip.expenses,
    )) {
      notifier.removeExpense(e.id);
    }
    await settle(tester, 700);
    expect(find.text('Nothing to settle yet'), findsOneWidget);
    expect(find.text('Nothing to chart yet'), findsOneWidget);
    expect(find.text('YOUR ITEMIZED BREAKDOWN'), findsNothing);
  });

  testWidgets(
    'Lays out in two columns on desktop and survives a 320 px phone',
    (tester) async {
      await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: const Size(1200, 800),
      );
      final left = tester.getTopLeft(find.text('CATEGORY BREAKDOWN'));
      final right = tester.getTopLeft(
        find.textContaining('OPTIMIZED SETTLEMENT TRANSFERS'),
      );
      expect(right.dx, greaterThan(left.dx + 300));
      expect(tester.takeException(), isNull);

      await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(TransferLaneCard), findsNWidgets(3));
    },
  );
}
