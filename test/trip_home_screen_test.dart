import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:travmate/features/home/trip_home_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/expense_item.dart';

import 'test_helpers.dart';

void main() {
  group('TripHomeScreen', () {
    testWidgets('Renders live hero totals, USD conversion and group balances', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        const TripHomeScreen(),
        size: const Size(390, 2400),
      );

      expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
      expect(find.text('¥60,000'), findsOneWidget);
      expect(find.text('~\$400 USD'), findsOneWidget);
      expect(find.text('Edit Group / Invite →'), findsOneWidget);
      expect(find.text('PER PERSON'), findsOneWidget);
      expect(find.text('¥15,000'), findsOneWidget);

      expect(find.text('GROUP NET BALANCE'), findsOneWidget);
      for (final name in ['You', 'Alex', 'Maya', 'Liam']) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('+ Group'), findsOneWidget);
      expect(find.text('Manage Group →'), findsOneWidget);
      expect(find.textContaining('Squad'), findsNothing);
      expect(find.textContaining('squad'), findsNothing);
    });

    testWidgets('Smart action banners are gone from Home', (tester) async {
      await pumpPocko(
        tester,
        const TripHomeScreen(),
        size: const Size(390, 2400),
      );
      expect(find.textContaining('ready to auto-match'), findsNothing);
      expect(find.textContaining('settle all debts'), findsNothing);
      expect(find.byKey(const ValueKey('banner_slips')), findsNothing);
      expect(find.byKey(const ValueKey('banner_transfers')), findsNothing);
    });

    testWidgets(
      'Top Expenses shows the three biggest expenses as proportional progress tubes',
      (tester) async {
        await pumpPocko(
          tester,
          const TripHomeScreen(),
          size: const Size(390, 2400),
        );
        expect(find.text('TOP EXPENSES'), findsOneWidget);

        final fmt = DateFormat('MMM d');
        final now = DateTime.now();
        String dayOf(int hoursAgo) =>
            fmt.format(now.subtract(Duration(hours: hoursAgo)));
        expect(find.text('Shinkansen to Kyoto • ${dayOf(2)}'), findsOneWidget);
        expect(
          find.text('TeamLab Borderless Tickets • ${dayOf(6)}'),
          findsOneWidget,
        );
        expect(
          find.text('Shibuya Sky Observation Deck • ${dayOf(12)}'),
          findsOneWidget,
        );
        expect(find.text('¥18,200'), findsWidgets);

        final w1 = tester
            .getSize(find.byKey(const ValueKey('top_fill_1')))
            .width;
        final w2 = tester
            .getSize(find.byKey(const ValueKey('top_fill_2')))
            .width;
        final w3 = tester
            .getSize(find.byKey(const ValueKey('top_fill_3')))
            .width;
        expect(w1, greaterThan(w2));
        expect(w2, greaterThan(w3));
        expect(w2 / w1, closeTo(15400 / 18200, 0.01));
        expect(w3 / w1, closeTo(8800 / 18200, 0.01));
      },
    );

    testWidgets(
      'Top Expenses reacts to new expenses and handles fewer than three',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const TripHomeScreen(),
          size: const Size(390, 2400),
        );
        final notifier = container.read(tripControllerProvider.notifier);

        notifier.addExpense(
          ExpenseItem(
            id: 'huge',
            title: 'Ryokan stay',
            amount: 40000,
            currency: 'JPY',
            payerId: 'you',
            createdAt: DateTime.now(),
          ),
        );
        await settle(tester, 900);
        expect(find.textContaining('Ryokan stay'), findsWidgets);
        final top = tester
            .getSize(find.byKey(const ValueKey('top_fill_1')))
            .width;
        final second = tester
            .getSize(find.byKey(const ValueKey('top_fill_2')))
            .width;
        expect(second / top, closeTo(18200 / 40000, 0.01));

        for (final e in List.of(
          container.read(tripControllerProvider).trip.expenses,
        )) {
          if (e.id != 'huge' && e.id != 'exp_6') notifier.removeExpense(e.id);
        }
        await settle(tester, 900);
        expect(find.byKey(const ValueKey('top_bar_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('top_bar_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('top_bar_2')), findsNothing);

        notifier.removeExpense('huge');
        notifier.removeExpense('exp_6');
        await settle(tester, 900);
        expect(
          find.text('Your three biggest expenses will show up here.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('top_bar_0')), findsNothing);
      },
    );

    testWidgets(
      'Recent expenses are the newest three; See all goes to Expenses',
      (tester) async {
        final navigated = <int>[];
        var groupOpened = false;
        await pumpPocko(
          tester,
          TripHomeScreen(
            onNavigateTab: navigated.add,
            onOpenSquadSetup: () => groupOpened = true,
          ),
          size: const Size(390, 2400),
        );
        expect(find.text('RECENT EXPENSES'), findsOneWidget);
        expect(
          find.text('Ichiran Ramen Shinjuku'),
          findsNothing,
          reason: 'oldest is not "recent"',
        );

        await tester.tap(find.text('See all →').first);
        await tester.tap(find.text('See all →').last);
        expect(navigated, [PockoTabs.expenses, PockoTabs.expenses]);

        await tester.tap(find.text('Edit Group / Invite →'));
        expect(groupOpened, isTrue);
      },
    );

    testWidgets(
      'Totals and balances react when state changes (currency switch converts)',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const TripHomeScreen(),
          size: const Size(390, 2400),
        );
        final notifier = container.read(tripControllerProvider.notifier);
        notifier.updateBaseCurrency('USD');
        await settle(tester, 900);
        expect(find.text('\$400'), findsOneWidget);
      },
    );

    testWidgets('Empty trip shows Pocko napping with a call to action', (
      tester,
    ) async {
      var opened = false;
      final container = await pumpPocko(
        tester,
        TripHomeScreen(onOpenCaptureModal: () => opened = true),
        size: const Size(390, 2400),
      );
      final notifier = container.read(tripControllerProvider.notifier);
      for (final e in List.of(
        container.read(tripControllerProvider).trip.expenses,
      )) {
        notifier.removeExpense(e.id);
      }
      await settle(tester, 700);

      expect(find.text('No expenses recorded yet'), findsOneWidget);
      await tester.tap(find.text('Log an expense').first);
      expect(opened, isTrue);
    });
  });
}
