import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/capture/member_pill.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

const _twoItems =
    'Ramen 4800 split 4 ways, and Shinkansen tickets 18200 for Alex, Maya, and me';

Future<dynamic> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double keyboard = 0,
  Duration silence = const Duration(milliseconds: 250),
  VoidCallback? onClose,
  VoidCallback? onManual,
  bool scaffold = true,
}) {
  return pumpPocko(
    tester,
    AiExpenseCaptureSheet(
      enableSpeechRecognition: false,
      silenceTimeout: silence,
      onClose: onClose,
      onManualExpense: onManual,
    ),
    size: size,
    bottomInset: keyboard,
    scaffold: scaffold,
  );
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

/// Types [text], presses Confirm once and waits for the review.
Future<void> _toReview(WidgetTester tester, [String text = _twoItems]) async {
  await _type(tester, text);
  await tester.tap(find.byKey(const ValueKey('confirm_button')));
  await settle(tester, 1500);
}

String _focusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('focus_label'))).data!;

Finder _orb(String id) => find.byKey(ValueKey('member_$id'));

void main() {
  group('Input: Light Intelligence overlay', () {
    testWidgets(
      'Giant 240px Pocko, big Voice / Type controls, no blur filter',
      (tester) async {
        await _pump(tester);
        await settle(tester, 900);

        expect(
          tester.getSize(find.byKey(const ValueKey('hero_pocko'))).width,
          240,
        );
        expect(find.text('Voice'), findsOneWidget);
        expect(find.text('Type'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );

    testWidgets('Pocko zooms in from 0.55 to 1.0 (easeOutBack)', (
      tester,
    ) async {
      await _pump(tester);
      final scale = tester.widget<ScaleTransition>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('hero_pocko')),
              matching: find.byType(ScaleTransition),
            )
            .first,
      );
      expect(scale.scale.value, inInclusiveRange(0.55, 0.8));
      await settle(tester, 1000);
      expect(scale.scale.value, closeTo(1.0, 0.01));
    });

    testWidgets('The hero only shrinks when the keyboard opens', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(390, 844),
        keyboard: 300,
        scaffold: false,
      );
      await settle(tester, 700);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('hero_pocko'))).width,
        lessThan(100),
      );
    });

    testWidgets('Preset chips are gone: no Japan-specific quick phrases', (
      tester,
    ) async {
      await _pump(tester);
      await settle(tester, 600);
      for (final gone in [
        'Ramen •',
        'Shinkansen for 3',
        'Two at once',
        'Euro dinner',
        'solo coffee',
      ]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('A subtle Manual Expense action replaces them', (tester) async {
      var manual = 0;
      await _pump(tester, onManual: () => manual++);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.text('Manual Expense'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('manual_expense_button')));
      await tester.pump();
      expect(manual, 1);
    });

    testWidgets(
      'Typing shows a moving green gradient (ShaderMask) on the live text',
      (tester) async {
        await _pump(tester);
        // The mask is always mounted (so the field never remounts); idle it
        // paints the text untouched (BlendMode.dst).
        expect(
          tester
              .widget<ShaderMask>(find.byKey(const ValueKey('live_gradient')))
              .blendMode,
          BlendMode.dst,
        );

        await _type(tester, 'Coffee 650');
        expect(find.byKey(const ValueKey('live_gradient')), findsOneWidget);
        final mask = tester.widget<ShaderMask>(
          find.byKey(const ValueKey('live_gradient')),
        );
        expect(mask.blendMode, BlendMode.srcIn);

        // The sweep moves: the shader callback yields different shaders over time.
        final b = const Rect.fromLTWH(0, 0, 300, 40);
        final s1 = mask.shaderCallback(b);
        await tester.pump(const Duration(milliseconds: 400));
        final mask2 = tester.widget<ShaderMask>(
          find.byKey(const ValueKey('live_gradient')),
        );
        final s2 = mask2.shaderCallback(b);
        expect(identical(s1, s2), isFalse);
      },
    );

    testWidgets('Voice: the gradient is active while the mic listens', (
      tester,
    ) async {
      await _pump(tester, silence: const Duration(seconds: 30));
      await tester.tap(find.byIcon(Icons.mic_rounded).last);
      await settle(tester, 900);
      expect(find.byKey(const ValueKey('live_gradient')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await settle(tester, 1500);
    });

    testWidgets('Type mode focuses the field', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    });
  });

  group('Confirm button (no emoji)', () {
    testWidgets(
      'Reads Confirm with a Material check icon, never Analyze or sparkles',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text('Type'));
        await tester.pump(const Duration(milliseconds: 300));

        final button = find.byKey(const ValueKey('confirm_button'));
        expect(button, findsOneWidget);
        expect(
          find.descendant(of: button, matching: find.text('Confirm')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Analyze'), findsNothing);

        // No sparkle / emoji characters on any text in the capture flow.
        final sparkle = RegExp(r'[✨🍜🚄☕€]');
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(sparkle.hasMatch(t.data ?? ''), isFalse, reason: t.data);
        }
      },
    );

    testWidgets('Confirm with nothing to parse explains what to do', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Type'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('Say or type what you spent first'),
        findsOneWidget,
      );
    });

    testWidgets('Text without an amount returns to the input with a hint', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'hello pocko');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await settle(tester, 1200);
      expect(find.textContaining('could not find an amount'), findsOneWidget);
      expect(find.byKey(const ValueKey('step_review')), findsNothing);
    });

    testWidgets('First Confirm analyzes, second Confirm saves', (tester) async {
      final container = await _pump(tester);
      final before = container
          .read(tripControllerProvider)
          .trip
          .expenses
          .length;

      await _toReview(tester, 'Ramen 4800 split 4 ways');
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      expect(
        container.read(tripControllerProvider).trip.expenses.length,
        before,
        reason: 'analysis alone saves nothing',
      );

      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('Logged ¥4,800 • Ramen'), findsOneWidget);
      expect(
        container.read(tripControllerProvider).trip.expenses.length,
        before + 1,
      );
      await settle(tester, 900);
    });
  });

  group('Analyzing: kinetic shimmer on the user\'s own text', () {
    testWidgets(
      'The transcript stays centered, shimmers and waves while Pocko juggles',
      (tester) async {
        await _pump(tester);
        await _type(tester, 'Ramen 4800 split 4 ways');
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('step_processing')), findsOneWidget);
        expect(find.byKey(const ValueKey('analyzing_text')), findsOneWidget);
        expect(find.byKey(const ValueKey('analyzing_shimmer')), findsOneWidget);
        expect(find.text('Ramen'), findsOneWidget);
        expect(find.text('4800'), findsOneWidget);

        // Never frozen: a word's vertical position changes as the wave moves.
        final y1 = tester.getTopLeft(find.text('Ramen')).dy;
        await tester.pump(const Duration(milliseconds: 190));
        final y2 = tester.getTopLeft(find.text('Ramen')).dy;
        expect(y1, isNot(y2));

        // The text is centered horizontally on screen.
        final box = tester.getRect(
          find.byKey(const ValueKey('analyzing_text')),
        );
        expect(box.center.dx, closeTo(195, 12));

        // Same hero, no flash: it is still the one big Pocko.
        expect(find.byKey(const ValueKey('hero_pocko')), findsOneWidget);
        await settle(tester, 1200);
      },
    );

    testWidgets('Local analysis has a ~500ms beat, not several seconds', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('step_processing')), findsOneWidget);
      await settle(tester, 900);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
    });

    testWidgets('Cancel returns to the input', (tester) async {
      await _pump(tester);
      await _type(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Cancel'));
      await settle(tester, 900);
      expect(find.byKey(const ValueKey('step_review')), findsNothing);
      expect(find.byKey(const ValueKey('step_input')), findsOneWidget);
    });

    testWidgets('Voice: demo dictation auto-analyzes after the pause', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.mic_rounded).last);
      await settle(tester, 500);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await settle(tester, 4800);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
    });
  });

  group('Always-visible group member bar', () {
    testWidgets('Avatars and names are on screen from the very first stage', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('member_bar')), findsOneWidget);
      for (final id in ['you', 'alex', 'maya', 'liam']) {
        expect(_orb(id), findsOneWidget);
      }
      for (final n in ['You', 'Alex', 'Maya', 'Liam']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(
        find.text('Tap to tag who is in, or let Pocko pick'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping avatars tags participants before analysis', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(_orb('alex'));
      await tester.tap(_orb('maya'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('(2) Alex, Maya'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
      await tester.tap(_orb('alex'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('(1) Maya'), findsOneWidget);
    });

    testWidgets('The bar stays visible while Pocko analyzes', (tester) async {
      await _pump(tester);
      await _type(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('member_bar')), findsOneWidget);
      await settle(tester, 1200);
    });

    testWidgets(
      'Nobody tagged: Pocko auto-selects the people it detected on the same bar',
      (tester) async {
        await _pump(tester, size: const Size(390, 1000));
        await _toReview(
          tester,
          'Shinkansen tickets 18200 for Alex, Maya, and me',
        );
        expect(_focusText(tester), startsWith('(3) '));
        expect(_focusText(tester), contains('Alex'));
        expect(_focusText(tester), contains('Maya'));
        // The bar highlights exactly those members.
        expect(
          [
            for (final id in ['you', 'alex', 'maya', 'liam'])
              tester.widget<MemberPill>(_orb(id)).selected,
          ],
          [true, true, true, false],
        );
      },
    );

    testWidgets(
      'Fewer people tagged than mentioned: detected members are added',
      (tester) async {
        final container = await _pump(tester, size: const Size(390, 1000));
        await tester.tap(_orb('liam'));
        await tester.pump();
        await _toReview(tester, 'Ramen 4800 split 4 ways');
        expect(_focusText(tester), startsWith('(4) '));
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 100));
        final added = container.read(tripControllerProvider).trip.expenses.last;
        expect(
          added.splitWithMemberIds,
          unorderedEquals(['you', 'alex', 'maya', 'liam']),
        );
        await settle(tester, 900);
      },
    );

    testWidgets(
      'Tagging at least as many people as detected keeps the user\'s choice',
      (tester) async {
        final container = await _pump(tester, size: const Size(390, 1000));
        await tester.tap(_orb('you'));
        await tester.tap(_orb('liam'));
        await tester.pump();
        await _toReview(tester, 'Matcha latte 650, Maya paid, just for Maya');
        final label = _focusText(tester);
        expect(label, startsWith('(2) '), reason: label);
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 100));
        final added = container.read(tripControllerProvider).trip.expenses.last;
        expect(added.splitWithMemberIds, unorderedEquals(['you', 'liam']));
        await settle(tester, 900);
      },
    );

    testWidgets(
      'Tapping a highlighted token switches which item the bar edits',
      (tester) async {
        await _pump(tester, size: const Size(390, 1000));
        await _toReview(tester);
        expect(_focusText(tester).toLowerCase(), contains('ramen'));
        expect(_focusText(tester), contains('(4) '));

        await tester.tap(find.byKey(const ValueKey('pill_title_1')));
        await settle(tester, 400);
        expect(_focusText(tester).toLowerCase(), contains('shinkansen'));
        expect(_focusText(tester), contains('(3) '));

        // Edit the focused item's members on the bar.
        await tester.tap(_orb('liam'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_focusText(tester), contains('(4) '));
      },
    );
  });

  group('Review: inline highlighted transcript', () {
    testWidgets(
      'Title and amount pills plus category badges, Confirm and Back',
      (tester) async {
        await _pump(tester, size: const Size(390, 1000));
        await _toReview(tester);
        expect(find.byKey(const ValueKey('inline_transcript')), findsOneWidget);
        for (final i in [0, 1]) {
          expect(find.byKey(ValueKey('pill_title_$i')), findsOneWidget);
          expect(find.byKey(ValueKey('pill_amount_$i')), findsOneWidget);
        }
        // The category pill lives on its own row, never inside the sentence.
        expect(find.byKey(const ValueKey('cat_badge_0')), findsOneWidget);
        expect(find.text('2 expenses • ¥23,000 total'), findsOneWidget);
        expect(find.text('Confirm'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
      },
    );

    testWidgets('Price pill opens an instant inline editor and saves', (
      tester,
    ) async {
      final container = await _pump(tester, size: const Size(390, 1000));
      await _toReview(tester);
      await tester.tap(find.byKey(const ValueKey('pill_amount_0')));
      await settle(tester, 800);
      expect(find.byKey(const ValueKey('inline_editor')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('inline_edit_field')),
        '5200',
      );
      await tester.tap(find.byKey(const ValueKey('inline_edit_save')));
      await settle(tester, 400);
      expect(find.text('2 expenses • ¥23,400 total'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      final exp = container.read(tripControllerProvider).trip.expenses;
      expect(exp[exp.length - 2].amount, 5200);
      await settle(tester, 900);
    });

    testWidgets('Title pill renames; invalid prices are rejected', (
      tester,
    ) async {
      final container = await _pump(tester, size: const Size(390, 1000));
      await _toReview(tester);

      await tester.tap(find.byKey(const ValueKey('pill_amount_1')));
      await settle(tester, 800);
      await tester.enterText(
        find.byKey(const ValueKey('inline_edit_field')),
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('inline_edit_save')));
      await settle(tester, 300);
      expect(find.text('Enter a price greater than zero.'), findsOneWidget);
      await settle(tester, 800);
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester, 300);

      await tester.tap(find.byKey(const ValueKey('pill_title_1')));
      await settle(tester, 800);
      await tester.enterText(
        find.byKey(const ValueKey('inline_edit_field')),
        'Bullet train',
      );
      await tester.tap(find.byKey(const ValueKey('inline_edit_save')));
      await settle(tester, 300);

      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(tripControllerProvider).trip.expenses.last.title,
        'Bullet train',
      );
      await settle(tester, 900);
    });

    testWidgets('Payer chip and category badge edit the focused item', (
      tester,
    ) async {
      final container = await _pump(tester, size: const Size(390, 1000));
      await _toReview(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('payer_menu')));
      await tester.tap(find.byKey(const ValueKey('payer_menu')));
      await settle(tester, 400);
      await tester.tap(find.text('Liam paid').last);
      await settle(tester, 300);
      await tester.tap(find.byKey(const ValueKey('cat_badge_0')));
      await settle(tester, 400);
      await tester.tap(find.text('Attractions').last);
      await settle(tester, 300);

      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      final exp = container.read(tripControllerProvider).trip.expenses;
      final first = exp[exp.length - 2];
      expect(first.payerId, 'liam');
      expect(first.category.displayName, 'Attractions');
      await settle(tester, 900);
    });

    testWidgets('Back returns to the input with the transcript kept', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 1000));
      await _toReview(tester, 'Ramen 4800 split 4 ways');
      await tester.tap(find.text('Back'));
      await settle(tester, 400);
      expect(find.byKey(const ValueKey('step_input')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Ramen 4800 split 4 ways',
      );
    });

    testWidgets(
      'Foreign-currency phrase keeps its currency and converts for the total',
      (tester) async {
        await _pump(tester, size: const Size(390, 1000));
        await _toReview(tester, 'Dinner 85 euro Alex paid, split everyone');
        expect(find.text('1 expense • ¥13,770 total'), findsOneWidget);
      },
    );
  });

  group('Confirm: Logged beat', () {
    testWidgets(
      'Logged ✓, both expenses committed, Undo available, then onClose',
      (tester) async {
        var closed = 0;
        final container = await _pump(
          tester,
          size: const Size(390, 1000),
          onClose: () => closed++,
        );
        final before = container.read(tripControllerProvider);
        await _toReview(tester);

        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byKey(const ValueKey('step_logged')), findsOneWidget);
        expect(find.byKey(const ValueKey('logged_pill')), findsOneWidget);
        expect(find.textContaining('Logged 2 expenses'), findsOneWidget);
        final after = container.read(tripControllerProvider);
        expect(after.trip.expenses.length, before.trip.expenses.length + 2);
        expect(after.totalSpend, before.totalSpend + 23000);

        expect(closed, 0, reason: 'still showing the Logged beat');
        await settle(tester, 400);
        expect(find.text('Undo'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await settle(tester, 300);
        expect(
          container.read(tripControllerProvider).trip.expenses.length,
          before.trip.expenses.length,
        );
        await settle(tester, 900);
        expect(
          closed,
          1,
          reason: 'fades back to the live screen after the ~950ms beat',
        );
      },
    );

    testWidgets('The close button calls onClose', (tester) async {
      var closed = 0;
      await _pump(tester, onClose: () => closed++);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('Layout robustness', () {
    testWidgets('320 x 568 phone: no overflow, member bar still visible', (
      tester,
    ) async {
      await _pump(tester, size: const Size(320, 568));
      await settle(tester, 900);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('member_bar')), findsOneWidget);
      await _toReview(tester);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Keyboard open on a short phone: field usable, hero shrinks', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(360, 640),
        keyboard: 280,
        scaffold: false,
      );
      await settle(tester, 700);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('hero_pocko'))).width,
        lessThan(100),
      );
      expect(
        find.byKey(const ValueKey('member_bar')),
        findsNothing,
        reason: 'only ~360px are visible: the bar yields to the field',
      );
    });

    testWidgets('Very short viewport with keyboard still lays out', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(320, 480),
        keyboard: 260,
        scaffold: false,
      );
      await settle(tester, 700);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tablet: 240px hero, no overflow, review stays centered', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1180, 820));
      await settle(tester, 900);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('hero_pocko'))).width,
        240,
      );
      await _toReview(tester);
      expect(tester.takeException(), isNull);
      final c = tester.getCenter(
        find.byKey(const ValueKey('inline_transcript')),
      );
      expect(c.dx, inInclusiveRange(1180 / 2 - 300, 1180 / 2 + 300));
    });
  });
}
