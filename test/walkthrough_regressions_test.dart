import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/utils/currency_helper.dart';
import 'package:travmate/core/widgets/photo_attachment_field.dart';
import 'package:travmate/features/expenses/expenses_canvas_screen.dart';
import 'package:travmate/features/onboarding/first_trip_setup_card.dart';
import 'package:travmate/features/settle/repayment_sheet.dart';
import 'package:travmate/features/settle/visual_settle_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_permissions.dart';
import 'package:travmate/models/expense_item.dart';

import 'test_helpers.dart';

Finder _k(String key) => find.byKey(ValueKey(key));

/// Findings from the final real-user walkthrough, each pinned by a test.
void main() {
  group('Negative amounts lead with the sign', () {
    test('"-¥6,800", never "¥-6,800"', () {
      expect(CurrencyHelper.formatAmount(-6800, 'JPY'), '-¥6,800');
      expect(
        CurrencyHelper.formatAmount(-6800, 'JPY', showSign: true),
        '-¥6,800',
      );
      expect(
        CurrencyHelper.formatAmount(27850, 'JPY', showSign: true),
        '+¥27,850',
      );
      expect(CurrencyHelper.formatAmount(27850, 'JPY'), '¥27,850');
      expect(CurrencyHelper.formatAmount(-12.5, 'USD'), '-\$12.50');
    });

    test('zero and rounding-to-zero amounts have no sign', () {
      expect(CurrencyHelper.formatAmount(0, 'JPY', showSign: true), '¥0');
      expect(CurrencyHelper.formatAmount(-0.3, 'JPY'), '¥0');
    });
  });

  group('Expenses strip total follows the category filter too', () {
    testWidgets('Meals only: the count and total match the listed cards', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        ExpensesCanvasScreen(onOpenCaptureModal: () {}),
        size: const Size(420, 2400),
      );
      final all = container.read(tripControllerProvider).trip.expenses;
      final meals = all.where((e) => e.category == ExpenseCategory.MEAL);
      final mealTotal = meals.fold<double>(0, (s, e) => s + e.amountIn('JPY'));
      container
          .read(tripControllerProvider.notifier)
          .setCategoryFilter(ExpenseCategory.MEAL);
      await settle(tester, 500);
      final strip = tester.widget<Container>(_k('date_total'));
      expect(strip, isNotNull);
      expect(
        find.descendant(
          of: _k('date_total'),
          matching: find.text(
            'All dates • ${meals.length} expense${meals.length == 1 ? '' : 's'}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _k('date_total'),
          matching: find.text(
            '${CurrencyHelper.formatAmount(mealTotal, 'JPY')} spent',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('Setup card: adding a friend keeps the keyboard ready', () {
    testWidgets('Enter adds the name and the field stays focused', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        SingleChildScrollView(child: FirstTripSetupCard(onStart: (_) {})),
        size: const Size(420, 1400),
      );
      final field = find.byType(TextField).last; // the friend name field
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Maya');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Maya'), findsWidgets);

      // No second tap needed: the next name can be typed immediately.
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, 'Liam');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Liam'), findsWidgets);
      expect(find.text('Maya'), findsWidgets);
    });
  });

  group('Repayment typo guard (a stray digit must not create a ¥118M debt)', () {
    Future<ProviderContainer> open(WidgetTester tester) async {
      final container = await pumpPocko(
        tester,
        Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => showRepaymentSheet(
                context,
                fromMemberId: 'maya',
                toMemberId: 'you',
              ),
              child: const Text('open'),
            ),
          ),
        ),
        size: const Size(420, 1600),
      );
      final n = container.read(tripControllerProvider.notifier);
      n.startNewTrip(name: 'Trip', currency: 'JPY', friends: ['Maya']);
      final maya = container
          .read(tripControllerProvider)
          .trip
          .members
          .firstWhere((m) => m.name == 'Maya')
          .id;
      n.addExpense(
        ExpenseItem(
          id: 'e1',
          title: 'Dinner',
          amount: 1000,
          currency: 'JPY',
          payerId: 'you',
          splitWithMemberIds: ['you', maya],
          createdAt: DateTime.now(),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester, 700);
      return container;
    }

    testWidgets('too large: the first tap warns, the second records', (
      tester,
    ) async {
      final container = await open(tester);
      // Maya's real id comes from the new trip.
      final maya = container
          .read(tripControllerProvider)
          .trip
          .members
          .firstWhere((m) => m.name == 'Maya')
          .id;
      await tester.tap(_k('repay_from'));
      await settle(tester, 400);
      await tester.tap(_k('selector_row_Maya'));
      await settle(tester, 400);
      await tester.enterText(_k('repay_amount'), '118005000');
      await tester.tap(_k('repay_save'));
      await settle(tester, 300);
      expect(
        find.textContaining('more than Maya owes You (¥500)'),
        findsOneWidget,
      );
      expect(container.read(tripControllerProvider).settlements, isEmpty);

      await tester.tap(_k('repay_save'));
      await settle(tester, 700);
      final s = container.read(tripControllerProvider);
      expect(s.settlements.single.amount, 118005000);
      expect(s.settlements.single.fromMemberId, maya);
    });

    testWidgets(
      'editing the amount re-arms the guard; a fair amount needs one tap',
      (tester) async {
        final container = await open(tester);
        await tester.tap(_k('repay_from'));
        await settle(tester, 400);
        await tester.tap(_k('selector_row_Maya'));
        await settle(tester, 400);
        await tester.enterText(_k('repay_amount'), '9999');
        await tester.tap(_k('repay_save'));
        await settle(tester, 300);
        expect(
          find.textContaining('Tap Record Repayment again'),
          findsOneWidget,
        );
        // Fixing the typo clears the warning and the next tap records at once.
        await tester.enterText(_k('repay_amount'), '300');
        await tester.pump();
        expect(find.textContaining('Tap Record Repayment again'), findsNothing);
        await tester.tap(_k('repay_save'));
        await settle(tester, 700);
        expect(
          container.read(tripControllerProvider).settlements.single.amount,
          300,
        );
      },
    );

    testWidgets('paying exactly what is owed records on the first tap', (
      tester,
    ) async {
      final container = await open(tester);
      await tester.tap(_k('repay_from'));
      await settle(tester, 400);
      await tester.tap(_k('selector_row_Maya'));
      await settle(tester, 400);
      await tester.enterText(_k('repay_amount'), '500');
      await tester.tap(_k('repay_save'));
      await settle(tester, 700);
      expect(container.read(tripControllerProvider).settlements, hasLength(1));
    });

    testWidgets('someone who owes nothing gets the "does not owe" message', (
      tester,
    ) async {
      await open(tester);
      // You -> Maya: You are owed, never the debtor.
      await tester.tap(_k('repay_from'));
      await settle(tester, 400);
      await tester.tap(_k('selector_row_You'));
      await settle(tester, 400);
      await tester.tap(_k('repay_to'));
      await settle(tester, 400);
      await tester.tap(_k('selector_row_Maya'));
      await settle(tester, 400);
      await tester.enterText(_k('repay_amount'), '100');
      await tester.tap(_k('repay_save'));
      await settle(tester, 300);
      expect(
        find.textContaining('You does not owe Maya anything right now'),
        findsOneWidget,
      );
    });
  });

  group('Permission messages say what the guest tried to do', () {
    test('editing and deleting have their own polite wording', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(tripControllerProvider);
      final p = c.read(tripPermissionsProvider);
      expect(
        p.deniedMessage,
        'Only the Trip Host or creator can delete this entry',
      );
      expect(
        p.deniedEditMessage,
        'Only the Trip Host or creator can edit this entry',
      );
    });
  });

  group('Photo buttons never truncate their label', () {
    testWidgets('"Choose from Gallery" scales to fit a 360 px phone', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        PhotoAttachmentField(title: 'Receipt', base64: null, onChanged: (_) {}),
        size: const Size(360, 700),
      );
      expect(
        find.descendant(
          of: _k('receipt_gallery'),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Net Balance amounts never clip', () {
    testWidgets('absurdly large balances shrink to fit their column', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const VisualSettleScreen(),
        size: const Size(360, 3400),
      );
      container
          .read(tripControllerProvider.notifier)
          .recordRepayment(
            fromMemberId: 'maya',
            toMemberId: 'you',
            amount: 118005000,
          );
      await settle(tester, 900);
      final fits = find.byKey(const ValueKey('balance_amount_fit'));
      expect(fits, findsNWidgets(4), reason: 'one per traveler');
      for (final f in fits.evaluate()) {
        final box = f.renderObject! as RenderBox;
        expect(box.size.width, lessThanOrEqualTo(96.01));
        // The text inside is scaled down, never wider than its slot.
        final text = find.descendant(
          of: find.byWidget(f.widget),
          matching: find.byType(Text),
        );
        // getRect applies the FittedBox's scale transform.
        expect(
          tester.getRect(text).width,
          lessThanOrEqualTo(box.size.width + 0.5),
        );
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('118,'), findsWidgets);
    });
  });
}
