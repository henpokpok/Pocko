import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/widgets/pocko_empty_state.dart';
import 'package:travmate/core/widgets/pocko_mascot.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/onboarding/onboarding_screen.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';

import 'test_helpers.dart';

Future<dynamic> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1000),
  VoidCallback? onClose,
}) {
  return pumpPocko(
    tester,
    AiExpenseCaptureSheet(
      enableSpeechRecognition: false,
      silenceTimeout: const Duration(milliseconds: 250),
      onClose: onClose,
    ),
    size: size,
  );
}

FocusNode _focusNode(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('capture_text_field')))
    .focusNode!;

TextEditingController _controller(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('capture_text_field')))
    .controller!;

Future<void> _toReview(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm_button')));
  await settle(tester, 1500);
}

double _maxMascot(WidgetTester tester) => tester
    .widgetList<PockoMascot>(find.byType(PockoMascot))
    .map((m) => m.size)
    .fold<double>(0, (a, b) => a > b ? a : b);

void main() {
  group('Typing never drops focus (0 -> 1 -> N characters)', () {
    testWidgets(
      'focus and the very same TextField survive the first character',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text('Type'));
        await tester.pump(const Duration(milliseconds: 300));

        final node = _focusNode(tester);
        expect(node.hasFocus, isTrue, reason: 'Type mode focuses the field');
        final elementBefore = tester.element(
          find.byKey(const ValueKey('capture_text_field')),
        );

        // Feed characters straight into the open input connection: a field
        // that lost focus would have closed it and could not receive these.
        for (final text in ['R', 'Ra', 'Ram', 'Rame', 'Ramen', 'Ramen 8']) {
          tester.testTextInput.enterText(text);
          await tester.pump();
          expect(node.hasFocus, isTrue, reason: 'focus lost at "$text"');
          expect(_controller(tester).text, text);
        }
        expect(
          identical(
            elementBefore,
            tester.element(find.byKey(const ValueKey('capture_text_field'))),
          ),
          isTrue,
          reason: 'the TextField is never re-created',
        );
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets('the gradient wrapper is permanent: idle dst, glowing srcIn', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 300));

      Finder inside() => find.descendant(
        of: find.byKey(const ValueKey('live_gradient')),
        matching: find.byKey(const ValueKey('capture_text_field')),
      );
      expect(inside(), findsOneWidget, reason: 'wrapped at 0 characters');
      tester.testTextInput.enterText('R');
      await tester.pump();
      expect(inside(), findsOneWidget, reason: 'same path at 1 character');
      expect(
        tester
            .widget<ShaderMask>(find.byKey(const ValueKey('live_gradient')))
            .blendMode,
        BlendMode.srcIn,
      );
      tester.testTextInput.enterText('');
      await tester.pump();
      expect(inside(), findsOneWidget, reason: 'and back to 0 characters');
      expect(_focusNode(tester).hasFocus, isTrue);
    });

    testWidgets('hiding the mode buttons on a short screen keeps the field', (
      tester,
    ) async {
      // Opening the keyboard hides the Voice/Type row; the field must not remount.
      await _pump(tester, size: const Size(390, 700));
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 300));
      tester.testTextInput.enterText('Coffee 650');
      await tester.pump();
      final before = tester.element(
        find.byKey(const ValueKey('capture_text_field')),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump(const Duration(milliseconds: 300));
      final after = tester.element(
        find.byKey(const ValueKey('capture_text_field')),
      );
      expect(identical(before, after), isTrue);
      expect(_controller(tester).text, 'Coffee 650');
    });
  });

  group('Highlighted member names match the title and price pills', () {
    testWidgets('same font size, weight, padding and radius; own tint', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, 'Ramen 4800 split with Alex and Maya');

      final title = find.byKey(const ValueKey('pill_title_0'));
      final price = find.byKey(const ValueKey('pill_amount_0'));
      final member = find.byKey(const ValueKey('member_token_alex_0'));
      expect(title, findsOneWidget);
      expect(price, findsOneWidget);
      expect(member, findsOneWidget);

      TextStyle style(Finder f) => tester
          .widget<Text>(find.descendant(of: f, matching: find.byType(Text)))
          .style!;
      expect(style(member).fontSize, 26);
      expect(style(member).fontSize, style(title).fontSize);
      expect(style(member).fontSize, style(price).fontSize);
      expect(style(member).fontWeight, style(title).fontWeight);
      expect(style(member).fontWeight, FontWeight.w900);

      AnimatedContainer box(Finder f) => tester.widget<AnimatedContainer>(
        find.descendant(of: f, matching: find.byType(AnimatedContainer)),
      );
      expect(box(member).padding, box(title).padding);
      expect(box(member).margin, box(title).margin);
      final mDeco = box(member).decoration! as BoxDecoration;
      final tDeco = box(title).decoration! as BoxDecoration;
      expect(mDeco.borderRadius, tDeco.borderRadius);
      expect(mDeco.borderRadius, BorderRadius.circular(16));
      expect(mDeco.color, isNot(tDeco.color), reason: 'distinct pastel tint');

      // Same line height as the title pill (identical metrics -> identical height).
      expect(
        tester.getSize(member).height,
        closeTo(tester.getSize(title).height, 1.0),
      );
    });
  });

  group('Explicit selected names', () {
    testWidgets('the bar lists names, not just a count', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('member_liam')));
      await tester.tap(find.byKey(const ValueKey('member_maya')));
      await tester.tap(find.byKey(const ValueKey('member_alex')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('(3) Liam, Maya, Alex'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('after analysis the caption names the split', (tester) async {
      await _pump(tester);
      await _toReview(tester, 'Ramen 4800 split with Alex and Maya');
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('focus_label')))
          .data!;
      expect(label, startsWith('(3) '));
      for (final n in ['You', 'Alex', 'Maya']) {
        expect(label, contains(n));
      }
      expect(label, isNot(contains('with 3')));
    });
  });

  group('Expense Logged! celebration', () {
    testWidgets('celebrating Pocko, burst + confetti, spring pill', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(
        tester,
        'Eat Ramen with Maya and Liam for 8 thousand yen',
      );

      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('logged_burst')), findsOneWidget);
      expect(find.byKey(const ValueKey('logged_confetti')), findsOneWidget);
      expect(find.byKey(const ValueKey('logged_check')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is PockoMascot && w.mood == PockoMood.celebrating,
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('logged_pill')), findsOneWidget);
      expect(find.text('✓ Logged ¥8,000 • Ramen'), findsOneWidget);
      // The pill springs in (scale overshoots, never a negative blur).
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await settle(tester, 1200);
    });

    testWidgets('the beat lasts 950 ms, then the overlay closes', (
      tester,
    ) async {
      var closed = 0;
      await _pump(tester, onClose: () => closed++);
      await _toReview(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(closed, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(closed, 1);
    });

    testWidgets('a multi-expense log reads "✓ Logged 2 expenses • total"', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(
        tester,
        'Ramen 4800 split 4 ways, and Shinkansen tickets 18200 for Alex, Maya, and me',
      );
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('✓ Logged 2 expenses • ¥23,000'), findsOneWidget);
      await settle(tester, 1200); // let the 950 ms beat finish
    });

    testWidgets('the toast carries useful context and an Undo', (tester) async {
      await _pump(tester);
      await _toReview(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ramen logged'), findsOneWidget);
      expect(find.byKey(const ValueKey('toast_detail')), findsOneWidget);
      expect(find.byKey(const ValueKey('toast_action')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('Bigger Pocko across the app', () {
    testWidgets('tab headers use 96-112 px', (tester) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      for (final tab in ['Home', 'Expenses', 'Matcher', 'Settle']) {
        await tester.tap(find.text(tab).first);
        await settle(tester, 500);
        final size = _maxMascot(tester);
        expect(size, inInclusiveRange(96, 112), reason: '$tab header');
      }
      expect(find.byKey(const ValueKey('settle_header')), findsOneWidget);
    });

    testWidgets('320 px phones: still 96 px, no overflow', (tester) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        size: const Size(320, 568),
        scaffold: false,
      );
      for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
        await tester.tap(find.text(tab).first);
        await settle(tester, 500);
        expect(tester.takeException(), isNull, reason: tab);
        expect(_maxMascot(tester), greaterThanOrEqualTo(96), reason: tab);
      }
    });

    testWidgets('empty and celebration states use 140-160 px', (tester) async {
      await pumpPocko(
        tester,
        const SingleChildScrollView(
          child: PockoEmptyState(title: 'Nothing yet', message: 'Log one'),
        ),
        size: const Size(390, 900),
      );
      expect(_maxMascot(tester), inInclusiveRange(140, 160));
    });

    testWidgets('the empty state also fits a 320 px phone', (tester) async {
      await pumpPocko(
        tester,
        const SingleChildScrollView(
          child: PockoEmptyState(title: 'Nothing yet', message: 'Log one'),
        ),
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      expect(_maxMascot(tester), 140);
    });
  });

  group('Landing: three illustrated scenes', () {
    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('next_button')));
      await settle(tester, 700);
    }

    testWidgets('log live -> slip matching -> privacy shield', (tester) async {
      await pumpPocko(tester, OnboardingScreen(onDone: () {}), scaffold: false);
      await settle(tester, 600);

      // 1) Café: offline chip, speech bubble, large listening Pocko.
      expect(find.byKey(const ValueKey('scene_cafe')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_offline_chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_bubble')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scene_cafe')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is PockoMascot &&
                w.mood == PockoMood.listening &&
                w.size >= 100,
          ),
        ),
        findsOneWidget,
      );
      // The bill is typed out and then confirmed in 3 s.
      await tester.pump(const Duration(milliseconds: 3200));
      expect(find.textContaining('Logged in 3s'), findsOneWidget);

      // 2) Slip matching: waiting expenses + a bank slip + scanning Pocko.
      await next(tester);
      expect(find.byKey(const ValueKey('scene_slipMatch')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_slip')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_row_1')), findsOneWidget);
      expect(find.text('Waiting for slip'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scene_slipMatch')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is PockoMascot &&
                w.mood == PockoMood.scanning &&
                w.size >= 100,
          ),
        ),
        findsOneWidget,
      );
      // After the slip docks, the waiting expense reads "Matched".
      await tester.pump(const Duration(milliseconds: 3600));
      expect(find.text('Matched'), findsOneWidget);

      // 3) Privacy shield: masked card digits, shield, only •••• 4829 syncs.
      await next(tester);
      expect(find.byKey(const ValueKey('scene_privacyShield')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_shield')), findsOneWidget);
      expect(find.byKey(const ValueKey('scene_card')), findsOneWidget);
      expect(find.text('4829'), findsOneWidget);
      expect(find.text('Syncs •••• 4829 only'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(find.text('••••'), findsNWidgets(3));
      expect(find.text('Masked on this device'), findsOneWidget);
    });

    testWidgets('scenes fit a 320 x 568 phone without overflow', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        OnboardingScreen(onDone: () {}),
        size: const Size(320, 568),
        scaffold: false,
      );
      for (var i = 0; i < 3; i++) {
        await settle(tester, 4500);
        expect(tester.takeException(), isNull, reason: 'scene ${i + 1}');
        if (i < 2) await next(tester);
      }
    });

    testWidgets('scenes fit a tablet', (tester) async {
      await pumpPocko(
        tester,
        OnboardingScreen(onDone: () {}),
        size: const Size(820, 1180),
        scaffold: false,
      );
      await settle(tester, 1000);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('scene_cafe')), findsOneWidget);
    });
  });
}
