import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/features/expenses/expenses_canvas_screen.dart';
import 'package:travmate/features/trip/date_filter.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

void main() {
  const tall = Size(390, 3000);

  Future<dynamic> pump(WidgetTester tester, {Size size = tall}) {
    return pumpPocko(
      tester,
      ExpensesCanvasScreen(onOpenCaptureModal: () {}),
      size: size,
    );
  }

  testWidgets('Groups the feed by day, newest first, with live totals', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('TOTAL EXPENSES'), findsOneWidget);
    expect(find.text('¥60,000'), findsWidgets);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);

    final newest = tester.getTopLeft(find.text('Shinkansen to Kyoto'));
    final older = tester.getTopLeft(find.text('Shibuya Sky Observation Deck'));
    expect(newest.dy, lessThan(older.dy));
  });

  group('Date filter strip (with Pre-Trip)', () {
    testWidgets(
      'Shows All Dates, a dedicated Pre-Trip chip and each trip day',
      (tester) async {
        final container = await pump(tester);
        expect(find.text('All Dates'), findsOneWidget);
        expect(find.text('Pre-Trip'), findsWidgets);
        final days = container.read(tripControllerProvider).tripDays;
        for (final d in days) {
          expect(
            find.byKey(ValueKey('date_${DateFormat('yyyyMMdd').format(d)}')),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('date_pretrip')), findsOneWidget);
      },
    );

    testWidgets('All Dates is selected first and shows the grand total', (
      tester,
    ) async {
      await pump(tester);
      final total = find.byKey(const ValueKey('date_total'));
      expect(
        find.descendant(
          of: total,
          matching: find.text('All dates • 7 expenses'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: total, matching: find.text('¥60,000 spent')),
        findsOneWidget,
      );
    });

    testWidgets(
      'Pre-Trip filters to expenses before the trip start and shows their total',
      (tester) async {
        final container = await pump(tester);
        await tester.tap(find.byKey(const ValueKey('date_pretrip')));
        await settle(tester, 600);

        expect(
          container.read(tripControllerProvider).dateFilter,
          const DateFilter.preTrip(),
        );
        expect(
          find.text('Travel Insurance (booked in advance)'),
          findsOneWidget,
        );
        expect(find.text('Shinkansen to Kyoto'), findsNothing);
        final total = find.byKey(const ValueKey('date_total'));
        expect(
          find.descendant(
            of: total,
            matching: find.text('Pre-Trip • 1 expense'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: total, matching: find.text('¥3,300 spent')),
          findsOneWidget,
        );
        expect(
          find.textContaining('• Pre-Trip'),
          findsOneWidget,
          reason: 'card metadata marks it as pre-trip',
        );
      },
    );

    testWidgets('A trip day shows that day\'s expenses and daily total', (
      tester,
    ) async {
      final container = await pump(tester);
      final state = container.read(tripControllerProvider);
      final day = startOfDay(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_6').expenseDateTime,
      );
      final dayChip = find.byKey(
        ValueKey('date_${DateFormat('yyyyMMdd').format(day)}'),
      );
      await tester.ensureVisible(dayChip);
      await tester.tap(dayChip);
      await settle(tester, 600);

      final expected = state.spendFor(DateFilter.day(day));
      final count = state.trip.expenses
          .where((e) => startOfDay(e.expenseDateTime) == day)
          .length;
      final total = find.byKey(const ValueKey('date_total'));
      expect(
        find.descendant(
          of: total,
          matching: find.textContaining('$count expense'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: total,
          matching: find.text(
            '¥${NumberFormat('#,##0').format(expected)} spent',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Travel Insurance (booked in advance)'), findsNothing);
    });

    testWidgets('Date and category filters work together', (tester) async {
      final container = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('date_pretrip')));
      await settle(tester, 300);
      container
          .read(tripControllerProvider.notifier)
          .setCategoryFilter(ExpenseCategory.MEAL);
      await settle(tester, 400);
      expect(find.text('Nothing in this category'), findsOneWidget);
    });
  });

  group('Chips never show a checkmark over the category icon', () {
    testWidgets(
      'Every FilterChip has showCheckmark: false and keeps its icon when selected',
      (tester) async {
        await pump(tester);
        final chips = tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .toList();
        expect(chips.length, greaterThan(6));
        expect(chips.every((c) => c.showCheckmark == false), isTrue);

        final transport = find.widgetWithText(FilterChip, 'Transport (2)');
        await tester.ensureVisible(transport);
        await tester.tap(transport);
        await settle(tester, 400);

        expect(tester.widget<FilterChip>(transport).selected, isTrue);
        expect(
          find.descendant(of: transport, matching: find.byIcon(Icons.check)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: transport,
            matching: find.byIcon(ExpenseCategory.TRANSPORT.icon),
          ),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets(
    'Cards show date + time metadata and the compact telemetry footer at the bottom',
    (tester) async {
      await pump(tester);
      final time = tester.widget<Text>(
        find.byKey(const ValueKey('time_exp_6')),
      );
      expect(time.data, matches(RegExp(r'^\w{3} \d{1,2} • \d{2}:\d{2}$')));

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('footer_exp_6')),
          matching: find.text('🟢 (Local) • 104ms'),
        ),
        findsOneWidget,
      );
      expect(find.text('☁️ (Cloud) • 480ms'), findsOneWidget);
      expect(find.text('✏️ (Manual)'), findsOneWidget);

      // The footer is the very last element of the card.
      final card = find
          .ancestor(
            of: find.byKey(const ValueKey('footer_exp_6')),
            matching: find.byType(Container),
          )
          .first;
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('footer_exp_6'))).dy,
        lessThanOrEqualTo(tester.getBottomLeft(card).dy),
      );
      final slipChip = tester.getTopLeft(find.text('Need Slip').first).dy;
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('footer_exp_6'))).dy,
        greaterThan(slipChip - 400),
      );
    },
  );

  testWidgets(
    'Tapping a card opens the editor with Date + Time pickers; saving recalculates everything',
    (tester) async {
      final container = await pump(tester);

      await tester.tap(find.text('Shinkansen to Kyoto'));
      await settle(tester, 500);
      expect(find.text('Edit Details & Splits'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor_date')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor_time')), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '20000');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await settle(tester, 800);

      final state = container.read(tripControllerProvider);
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_6').amount,
        20000,
      );
      expect(state.totalSpend, 61800);
      expect(find.text('¥61,800'), findsWidgets);
    },
  );

  testWidgets(
    'Editing the date to before the trip start makes it a Pre-Trip expense',
    (tester) async {
      final container = await pump(tester);
      await tester.tap(find.text('Shinkansen to Kyoto'));
      await settle(tester, 500);

      await tester.tap(find.byKey(const ValueKey('editor_date')));
      await settle(tester, 500);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // Day "1" of the current month is before the trip start (any date is allowed).
      await tester.tap(
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.text('1'),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester, 500);
      expect(
        find.text('Pre-Trip expense (before the trip starts)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('editor_time')));
      await settle(tester, 500);
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester, 500);

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await settle(tester, 800);

      final state = container.read(tripControllerProvider);
      final e = state.trip.expenses.firstWhere((x) => x.id == 'exp_6');
      expect(e.expenseDateTime.day, 1);
      expect(state.isPreTrip(e), isTrue);
      expect(state.preTripExpenses.length, 2);
    },
  );

  testWidgets('Editor validates empty amounts', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Shinkansen to Kyoto'));
    await settle(tester, 500);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '0');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
  });

  testWidgets('Swipe to delete removes the expense and Undo brings it back', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.drag(
      find.text('Akihabara Gachapon & Snacks'),
      const Offset(-500, 0),
    );
    await settle(tester, 700);

    expect(
      container
          .read(tripControllerProvider)
          .trip
          .expenses
          .any((e) => e.id == 'exp_3'),
      isFalse,
    );
    expect(find.text('Akihabara Gachapon & Snacks'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester, 700);
    expect(
      container
          .read(tripControllerProvider)
          .trip
          .expenses
          .any((e) => e.id == 'exp_3'),
      isTrue,
    );
    expect(find.text('Akihabara Gachapon & Snacks'), findsOneWidget);
  });

  testWidgets(
    'Category filter narrows the list and stale filters are repaired',
    (tester) async {
      final container = await pump(tester);

      await tester.ensureVisible(find.text('Transport (2)'));
      await tester.tap(find.text('Transport (2)'));
      await settle(tester, 500);
      expect(find.text('Shinkansen to Kyoto'), findsOneWidget);
      expect(find.text('Shibuya Sky Observation Deck'), findsNothing);

      container
          .read(tripControllerProvider.notifier)
          .setCategoryFilter(ExpenseCategory.SNACK_CAFE);
      container.read(tripControllerProvider.notifier).removeExpense('exp_3');
      await settle(tester, 500);
      expect(
        container.read(tripControllerProvider).selectedFilterCategory,
        isNull,
      );
    },
  );

  testWidgets('A completely empty trip shows the napping Pocko state', (
    tester,
  ) async {
    final container = await pump(tester);
    final notifier = container.read(tripControllerProvider.notifier);
    for (final e in List.of(
      container.read(tripControllerProvider).trip.expenses,
    )) {
      notifier.removeExpense(e.id);
    }
    await settle(tester, 600);

    expect(find.text('No expenses yet'), findsOneWidget);
    expect(find.text('Log first expense'), findsOneWidget);
    expect(find.text('¥0'), findsWidgets);
  });

  testWidgets('Wide screens show the feed beside the summary', (tester) async {
    await pump(tester, size: const Size(1100, 800));
    final hero = tester.getTopLeft(find.text('TOTAL EXPENSES'));
    final feed = tester.getTopLeft(find.text('Shinkansen to Kyoto'));
    expect(feed.dx, greaterThan(hero.dx + 250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Renders on a 320 x 568 phone without overflow', (tester) async {
    await pump(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });
}
