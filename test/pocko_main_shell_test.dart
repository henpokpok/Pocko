import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/sandbox/hybrid_sandbox_screen.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

const _indicator = ValueKey('nav_indicator');

void main() {
  group('PockoMainShell (phone)', () {
    testWidgets('Renders brand, trip pill, bottom bar and the Home tab', (
      tester,
    ) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);

      expect(find.text('Pocko'), findsOneWidget);
      expect(find.text('Tokyo Trip 🇯🇵 • Home'), findsOneWidget);
      for (final label in ['Home', 'Expenses', 'Matcher', 'Settle']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
      expect(find.text('GROUP NET BALANCE'), findsOneWidget);
      expect(find.text('TOP EXPENSES'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets(
      'Navigates between tabs and opens group setup from the top bar',
      (tester) async {
        await pumpPocko(tester, const PockoMainShell(), scaffold: false);

        await tester.tap(find.text('Expenses'));
        await settle(tester, 400);
        expect(find.text('TOTAL EXPENSES'), findsOneWidget);

        await tester.tap(find.text('Matcher'));
        await settle(tester, 400);
        expect(find.text('Smart Slip\nMatcher'), findsOneWidget);

        await tester.tap(find.text('Settle'));
        await settle(tester, 400);
        expect(find.text('CATEGORY BREAKDOWN'), findsOneWidget);
        expect(find.text('NET BALANCE SNAPSHOT'), findsOneWidget);

        await tester.tap(find.text('Tokyo Trip 🇯🇵 • Settle'));
        await settle(tester, 600);
        expect(find.text('Travel Group'), findsOneWidget);
        expect(find.text('Group Code'), findsOneWidget);
      },
    );

    testWidgets('Center + opens the capture overlay', (tester) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      expect(find.byType(AiExpenseCaptureSheet), findsNothing);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, 900);

      expect(find.byType(AiExpenseCaptureSheet), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets(
      'Dim & drop: no blur anywhere, a ~85% dark scrim over the whole screen, the page stays full-bleed at scale 1.0',
      (tester) async {
        await pumpPocko(tester, const PockoMainShell(), scaffold: false);
        final page = find.byType(Scaffold).first;
        double painted() =>
            tester.getTopRight(page).dx - tester.getTopLeft(page).dx;
        final before = painted();
        await tester.tap(find.byIcon(Icons.add_rounded));
        await settle(tester, 900);

        // The live page is still on screen underneath.
        expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
        expect(find.text('¥60,000'), findsOneWidget);

        // Zero blur jank: neither the overlay nor its scrim use a blur filter.
        expect(
          find.descendant(
            of: find.byType(AiExpenseCaptureSheet),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('capture_overlay_fade')),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );

        final scrim = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('capture_scrim')),
        );
        expect(scrim.color, const Color(0xD9070F18));
        expect(scrim.color.a, closeTo(0.85, 0.005));

        // Full-bleed: the page keeps its exact size (scale 1.0), with no
        // scale transform and no rounded clip inset around it, so no black
        // frame can appear at the screen edges.
        expect(find.byKey(const ValueKey('capture_page_scale')), findsNothing);
        expect(painted(), closeTo(before, 0.01));
        expect(tester.getTopLeft(page), Offset.zero);
        for (final w in [AnimatedScale, Transform, ClipRRect, ClipPath]) {
          expect(
            find.ancestor(of: page, matching: find.byType(w)),
            findsNothing,
            reason: '$w must not wrap the underlying page',
          );
        }

        // The scrim covers the entire viewport (status and nav areas too).
        final view = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(
          tester.getSize(find.byKey(const ValueKey('capture_scrim'))),
          view,
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('capture_scrim'))),
          Offset.zero,
        );
      },
    );

    testWidgets(
      'The scrim fades in over 240ms and Pocko zooms 0.55 -> 1.0 to 240px',
      (tester) async {
        await pumpPocko(tester, const PockoMainShell(), scaffold: false);
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        final fade = tester.widget<AnimatedOpacity>(
          find.byKey(const ValueKey('capture_overlay_fade')),
        );
        expect(fade.duration, const Duration(milliseconds: 240));
        expect(fade.curve, Curves.easeOutCubic);

        final scale = tester.widget<ScaleTransition>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('hero_pocko')),
                matching: find.byType(ScaleTransition),
              )
              .first,
        );
        expect(scale.scale.value, lessThan(0.8));
        expect(scale.scale.value, greaterThanOrEqualTo(0.55));

        await settle(tester, 1000);
        expect(scale.scale.value, closeTo(1.0, 0.01));
        expect(
          tester.getSize(find.byKey(const ValueKey('hero_pocko'))).width,
          240,
        );
      },
    );

    testWidgets(
      'Closing the overlay restores the page and unmounts the capture UI',
      (tester) async {
        await pumpPocko(tester, const PockoMainShell(), scaffold: false);
        await tester.tap(find.byIcon(Icons.add_rounded));
        await settle(tester, 900);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await settle(tester, 800);

        expect(find.byType(AiExpenseCaptureSheet), findsNothing);
        expect(find.byKey(const ValueKey('capture_page')), findsOneWidget);
        expect(find.byKey(const ValueKey('capture_scrim')), findsNothing);
      },
    );

    testWidgets(
      'Manual Expense closes the overlay and opens the 80% Add Expense sheet',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const PockoMainShell(),
          scaffold: false,
        );
        final before = container
            .read(tripControllerProvider)
            .trip
            .expenses
            .length;
        await tester.tap(find.byIcon(Icons.add_rounded));
        await settle(tester, 900);

        await tester.tap(find.byKey(const ValueKey('manual_expense_button')));
        await settle(tester, 1200);

        expect(find.byType(AiExpenseCaptureSheet), findsNothing);
        expect(find.text('Add Expense'), findsWidgets);
        final sheet = tester.getSize(find.byType(BottomSheet));
        expect(sheet.height, lessThanOrEqualTo(844 * 0.8 + 0.5));
        expect(
          container.read(tripControllerProvider).trip.expenses.length,
          before,
          reason: 'nothing is saved until the form is submitted',
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Expense Title'),
          'Street market snacks',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Amount'),
          '1500',
        );
        final add = find.widgetWithText(ElevatedButton, 'Add Expense');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await settle(tester, 800);

        final state = container.read(tripControllerProvider);
        expect(state.trip.expenses.length, before + 1);
        expect(state.trip.expenses.last.title, 'Street market snacks');
        expect(state.trip.expenses.last.amount, 1500);
      },
    );

    testWidgets('Diagnostic button opens the Hybrid AI sandbox', (
      tester,
    ) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      await tester.tap(find.byIcon(Icons.terminal_rounded));
      await settle(tester, 700);
      expect(find.byType(HybridSandboxScreen), findsOneWidget);
      expect(find.text('Pocko Hybrid AI'), findsOneWidget);
    });

    testWidgets('Adding an expense updates Home and the totals everywhere', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const PockoMainShell(),
        scaffold: false,
      );
      expect(find.text('¥60,000'), findsOneWidget);

      container
          .read(tripControllerProvider.notifier)
          .addExpenses(
            container
                .read(tripControllerProvider)
                .trip
                .expenses
                .take(1)
                .map(
                  (e) => e.copyWith(
                    id: 'dup',
                    title: 'Late-night yakitori',
                    amount: 3300,
                    createdAt: DateTime.now(),
                  ),
                )
                .toList(),
          );
      await settle(tester, 800);

      expect(find.text('¥63,300'), findsOneWidget);
      expect(find.text('Late-night yakitori'), findsOneWidget);
    });
  });

  group('Bottom navigation indicator & Matcher badge', () {
    testWidgets(
      'One indicator glides between tabs without being rebuilt (no flicker)',
      (tester) async {
        await pumpPocko(tester, const PockoMainShell(), scaffold: false);
        expect(find.byKey(_indicator), findsOneWidget);
        final state = tester.state(find.byKey(_indicator));
        final x0 = tester.getTopLeft(find.byKey(_indicator)).dx;

        await tester.tap(find.text('Settle'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 130));
        final mid = tester.getTopLeft(find.byKey(_indicator)).dx;
        await settle(tester, 400);
        final end = tester.getTopLeft(find.byKey(_indicator)).dx;

        expect(
          find.byKey(_indicator),
          findsOneWidget,
          reason: 'never removed mid-transition',
        );
        expect(
          identical(tester.state(find.byKey(_indicator)), state),
          isTrue,
          reason: 'same element animates',
        );
        expect(mid, greaterThan(x0));
        expect(mid, lessThan(end), reason: 'it is mid-glide, not jumping');
        expect(end, greaterThan(x0 + 100));
      },
    );

    testWidgets('The indicator lands under each tab and glides back smoothly', (
      tester,
    ) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      final xs = <String, double>{};
      for (final tab in ['Home', 'Expenses', 'Matcher', 'Settle']) {
        await tester.tap(find.text(tab));
        await settle(tester, 400);
        xs[tab] = tester.getCenter(find.byKey(_indicator)).dx;
        expect(
          (xs[tab]! - tester.getCenter(find.text(tab)).dx).abs(),
          lessThan(6),
          reason: '$tab indicator is centered',
        );
      }
      expect(xs['Home']!, lessThan(xs['Expenses']!));
      expect(xs['Expenses']!, lessThan(xs['Matcher']!));
      expect(xs['Matcher']!, lessThan(xs['Settle']!));
    });

    testWidgets(
      'Pending slips show a count badge on the Matcher icon; it hides at 0',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const PockoMainShell(),
          scaffold: false,
        );
        final badge = find.byKey(const ValueKey('nav_badge_3'));
        expect(badge, findsOneWidget);
        expect(
          find.descendant(of: badge, matching: find.text('3')),
          findsOneWidget,
        );

        final notifier = container.read(tripControllerProvider.notifier);
        notifier.confirmSlips(['slip_1']);
        await settle(tester, 500);
        expect(
          find.descendant(of: badge, matching: find.text('2')),
          findsOneWidget,
        );

        notifier.confirmSlips(['slip_2', 'slip_3']);
        await settle(tester, 500);
        expect(
          find.byKey(const ValueKey('nav_badge_3')),
          findsNothing,
          reason: 'hidden when nothing is pending',
        );
      },
    );

    testWidgets(
      'The badge is emerald when every slip has a match and coral when one needs review',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const PockoMainShell(),
          scaffold: false,
        );
        Color badgeColor() {
          final c = tester.widget<Container>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('nav_badge_3')),
                  matching: find.byType(Container),
                )
                .first,
          );
          return (c.decoration! as BoxDecoration).color!;
        }

        expect(badgeColor().toARGB32(), const Color(0xFF10B981).toARGB32());
        container.read(tripControllerProvider.notifier).detachSlip('slip_3');
        await settle(tester, 500);
        expect(badgeColor().toARGB32(), const Color(0xFFFF7A6B).toARGB32());
      },
    );
  });

  group('PockoMainShell (tablet / desktop)', () {
    testWidgets(
      'Uses a side rail instead of the floating bottom bar, with the badge on Matcher',
      (tester) async {
        await pumpPocko(
          tester,
          const PockoMainShell(),
          size: const Size(1024, 768),
          scaffold: false,
        );

        expect(find.byIcon(Icons.add_rounded), findsOneWidget);
        expect(
          tester.getCenter(find.byIcon(Icons.add_rounded)).dx,
          lessThan(120),
        );
        expect(find.byKey(const ValueKey('nav_badge_3')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('The rail indicator slides vertically between tabs', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        size: const Size(1024, 768),
        scaffold: false,
      );
      final y0 = tester.getTopLeft(find.byKey(_indicator)).dy;
      await tester.tap(find.text('Settle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final mid = tester.getTopLeft(find.byKey(_indicator)).dy;
      await settle(tester, 400);
      final end = tester.getTopLeft(find.byKey(_indicator)).dy;
      expect(mid, greaterThan(y0));
      expect(mid, lessThan(end));
    });

    testWidgets('Home becomes a balanced two-column dashboard', (tester) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        size: const Size(1280, 800),
        scaffold: false,
      );
      final hero = tester.getTopLeft(find.text('TOTAL TRIP SPEND'));
      final top = tester.getTopLeft(find.text('TOP EXPENSES'));
      expect(top.dx, greaterThan(hero.dx + 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Every tab renders at iPad Air width without overflow', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        size: const Size(820, 1180),
        scaffold: false,
      );
      for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
        await tester.tap(find.text(tab));
        await settle(tester, 500);
        expect(tester.takeException(), isNull, reason: '$tab overflowed');
      }
    });
  });

  group('PockoMainShell (small phones)', () {
    testWidgets('Every tab renders on a 320 x 568 screen without overflow', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        size: const Size(320, 568),
        scaffold: false,
      );
      for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
        await tester.tap(find.text(tab));
        await settle(tester, 500);
        expect(tester.takeException(), isNull, reason: '$tab overflowed');
      }
    });
  });
}
