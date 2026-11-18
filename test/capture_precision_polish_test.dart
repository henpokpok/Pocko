import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/widgets/pocko_selector.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/capture/member_pill.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

const _dinner = 'Dinner 4800 for Alex, Maya and Liam';

Future<dynamic> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1100),
  Duration silence = const Duration(milliseconds: 250),
}) {
  return pumpPocko(
    tester,
    AiExpenseCaptureSheet(
      enableSpeechRecognition: false,
      silenceTimeout: silence,
    ),
    size: size,
  );
}

Future<void> _toReview(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm_button')));
  await settle(tester, 1500);
}

Finder _pill(String id) => find.byKey(ValueKey('member_$id'));
bool _selected(WidgetTester t, String id) =>
    t.widget<MemberPill>(_pill(id)).selected;
Finder _token(String id, [int n = 0]) =>
    find.byKey(ValueKey('member_token_${id}_$n'));
Finder _plain(String id, [int n = 0]) =>
    find.byKey(ValueKey('member_text_${id}_$n'));
String _preview(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('Voice pause (3.5 seconds)', () {
    test('the default silence timeout is 3.5 seconds', () {
      const sheet = AiExpenseCaptureSheet();
      expect(sheet.silenceTimeout, const Duration(milliseconds: 3500));
    });

    testWidgets(
      'dictation is not cut off early: analysis waits for the full pause',
      (tester) async {
        await _pump(tester, silence: const Duration(milliseconds: 3500));
        await tester.tap(find.byIcon(Icons.mic_rounded).last);
        // The demo dictation types for ~2s, then 3.5s of dead air must pass.
        await settle(tester, 4500);
        expect(find.byKey(const ValueKey('step_input')), findsOneWidget);
        await settle(tester, 2500);
        expect(find.byKey(const ValueKey('step_input')), findsNothing);
        await settle(tester, 1500);
        expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      },
    );
  });

  group('Name-only member pills', () {
    testWidgets(
      'no initial avatar circle: only the name, with a stadium shape',
      (tester) async {
        await _pump(tester);
        for (final (id, name) in [
          ('you', 'You'),
          ('alex', 'Alex'),
          ('maya', 'Maya'),
          ('liam', 'Liam'),
        ]) {
          final pill = _pill(id);
          expect(pill, findsOneWidget);
          final texts = tester.widgetList<Text>(
            find.descendant(of: pill, matching: find.byType(Text)),
          );
          expect(texts.map((t) => t.data), [name], reason: 'only the name');
          expect(
            find.descendant(of: pill, matching: find.byIcon(Icons.check)),
            findsNothing,
          );

          final box = tester.widget<AnimatedContainer>(
            find.descendant(of: pill, matching: find.byType(AnimatedContainer)),
          );
          expect(
            box.padding,
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          );
          expect(
            (box.decoration! as ShapeDecoration).shape,
            isA<StadiumBorder>(),
          );
        }
        // The old first-letter avatars are gone.
        expect(find.text('Y'), findsNothing);
        expect(find.text('A'), findsNothing);
      },
    );

    testWidgets('selected pills get the emerald fill and glow', (tester) async {
      await _pump(tester);
      Color fill(String id) =>
          ((tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: _pill(id),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!)
                  as ShapeDecoration)
              .color!;
      final before = fill('alex');
      await tester.tap(_pill('alex'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_selected(tester, 'alex'), isTrue);
      expect(fill('alex'), isNot(before));
      expect(fill('alex').g, greaterThan(fill('alex').r));
    });
  });

  group('Large Confirm and Back', () {
    testWidgets(
      'Confirm: 58px tall, w700 17.5 text, 22px check icon, wide padding',
      (tester) async {
        await _pump(tester);
        await tester.enterText(find.byType(TextField), 'Coffee 400');
        await tester.pump();
        final confirm = find.byKey(const ValueKey('confirm_button'));
        expect(tester.getSize(confirm).height, greaterThanOrEqualTo(58));
        final style = tester.widget<ElevatedButton>(confirm).style!;
        expect(style.minimumSize!.resolve({})!.height, 58);
        final text = style.textStyle!.resolve({})!;
        expect(text.fontSize, 17.5);
        expect(text.fontWeight, FontWeight.w700);
        final pad = style.padding!.resolve({})! as EdgeInsets;
        expect(pad.horizontal / 2, inInclusiveRange(28, 36));
        final icon = tester.widget<Icon>(
          find.descendant(
            of: confirm,
            matching: find.byIcon(Icons.check_rounded),
          ),
        );
        expect(icon.size, 22);
      },
    );

    testWidgets('Back matches: 58px tall with the same typography', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, _dinner);
      final back = find.byKey(const ValueKey('back_button'));
      expect(tester.getSize(back).height, greaterThanOrEqualTo(58));
      final style = tester.widget<OutlinedButton>(back).style!;
      expect(style.minimumSize!.resolve({})!.height, 58);
      expect(style.textStyle!.resolve({})!.fontSize, 17.5);
      expect(style.textStyle!.resolve({})!.fontWeight, FontWeight.w700);
      final pad = style.padding!.resolve({})! as EdgeInsets;
      expect(pad.horizontal / 2, inInclusiveRange(28, 36));
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('Bi-directional transcript <-> member pill sync', () {
    testWidgets(
      'AI-detected members are highlighted in the text and selected below',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);

        for (final id in ['alex', 'maya', 'liam']) {
          expect(
            _token(id),
            findsOneWidget,
            reason: '$id highlighted in the transcript',
          );
          expect(
            _selected(tester, id),
            isTrue,
            reason: '$id selected on the bar',
          );
        }
        expect(_token('you'), findsNothing);
        expect(_selected(tester, 'you'), isFalse);
      },
    );

    testWidgets(
      'unselecting a bottom pill un-highlights that name in the text',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);

        await tester.tap(_pill('maya'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(_selected(tester, 'maya'), isFalse);
        expect(_token('maya'), findsNothing);
        expect(
          _plain('maya'),
          findsOneWidget,
          reason: 'Maya is plain text again',
        );
        // The others stay highlighted.
        expect(_token('alex'), findsOneWidget);
        expect(_token('liam'), findsOneWidget);
      },
    );

    testWidgets('selecting the pill again re-highlights the name', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, _dinner);
      await tester.tap(_pill('liam'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_token('liam'), findsNothing);
      await tester.tap(_pill('liam'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_selected(tester, 'liam'), isTrue);
      expect(_token('liam'), findsOneWidget);
    });

    testWidgets(
      'tapping a highlighted name in the text unselects the pill (and back)',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);
        await tester.tap(_token('alex'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(_selected(tester, 'alex'), isFalse);
        expect(_plain('alex'), findsOneWidget);
        await tester.tap(_plain('alex'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(_selected(tester, 'alex'), isTrue);
        expect(_token('alex'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting a member who is not in the text changes the split but not the text',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);
        await tester.tap(_pill('you'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(_selected(tester, 'you'), isTrue);
        expect(_token('you'), findsNothing, reason: 'nobody said "me"');
        expect(_preview(tester, 'preview_meta'), contains('Everyone'));
      },
    );

    testWidgets('the split preview updates live as pills change', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, _dinner);
      expect(_preview(tester, 'preview_meta'), 'You paid • Alex, Maya +1');
      expect(_preview(tester, 'preview_each'), '¥1,600 each');

      await tester.tap(_pill('maya'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_preview(tester, 'preview_meta'), 'You paid • Alex, Liam');
      expect(_preview(tester, 'preview_each'), '¥2,400 each');
    });

    testWidgets(
      '"me" in the transcript is highlighted for the current member',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, 'Tickets 18200 for Alex, Maya, and me');
        expect(_token('you'), findsOneWidget);
        await tester.tap(_pill('you'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(_token('you'), findsNothing);
        expect(_plain('you'), findsOneWidget);
      },
    );

    testWidgets('confirm saves exactly the members that are highlighted', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toReview(tester, _dinner);
      await tester.tap(_pill('maya'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 100));
      final added = container.read(tripControllerProvider).trip.expenses.last;
      expect(added.splitWithMemberIds, unorderedEquals(['alex', 'liam']));
      await settle(tester, 900);
    });

    testWidgets('multi-item: highlights follow the focused item', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(
        tester,
        'Ramen 1 thousand for Alex and Maya, and taxi 2 thousand for Liam',
      );
      // Item 0 focused: Alex + Maya highlighted, Liam is plain text.
      expect(_token('alex'), findsOneWidget);
      expect(_token('maya'), findsOneWidget);
      expect(_plain('liam'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pill_title_1')));
      await settle(tester, 700);
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester, 400);
      expect(_token('liam'), findsOneWidget);
      expect(_plain('alex'), findsOneWidget);
      expect(_plain('maya'), findsOneWidget);
    });
  });

  group('Spoken multipliers in the capture flow', () {
    testWidgets(
      '"1 thousan" becomes 1000 and the transcript pill reads ¥1,000',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, 'Dinner 1 thousan yen with Alex and Maya');
        expect(find.text('¥1,000'), findsWidgets);
        expect(find.byKey(const ValueKey('pill_amount_0')), findsOneWidget);
      },
    );

    testWidgets('"2.5k", "15 thousand" and "1 million" as separate expenses', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(
        tester,
        'Taxi 2.5k and hotel 15 thousand and villa 1 million',
      );
      expect(find.text('3 expenses • ¥1,017,500 total'), findsOneWidget);
    });
  });

  group('Category row and live preview card', () {
    testWidgets(
      'the category pill is NOT inside the sentence: it has its own centered row',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);

        final transcript = find.byKey(const ValueKey('inline_transcript'));
        final cat = find.byKey(const ValueKey('cat_badge_0'));
        expect(cat, findsOneWidget);
        expect(
          find.descendant(
            of: transcript,
            matching: find.byKey(const ValueKey('cat_badge_0')),
          ),
          findsNothing,
        );
        final t = tester.getRect(transcript);
        final c = tester.getRect(cat);
        expect(
          c.top,
          greaterThanOrEqualTo(t.bottom),
          reason: 'directly underneath',
        );
        expect(c.center.dx, closeTo(t.center.dx, 12), reason: 'centered');
      },
    );

    testWidgets(
      'layout order: transcript, category row, preview card, member pills',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);
        final cat = tester.getRect(find.byKey(const ValueKey('cat_badge_0')));
        final card = tester.getRect(
          find.byKey(const ValueKey('expense_preview')),
        );
        final bar = tester.getRect(find.byKey(const ValueKey('member_bar')));
        expect(card.top, greaterThanOrEqualTo(cat.bottom));
        expect(bar.top, greaterThanOrEqualTo(card.bottom - 0.5));
      },
    );

    testWidgets('the card mirrors the focused expense', (tester) async {
      await _pump(tester);
      await _toReview(tester, _dinner);
      expect(_preview(tester, 'preview_title'), 'Dinner');
      expect(_preview(tester, 'preview_amount'), '¥4,800');
      expect(_preview(tester, 'preview_meta'), startsWith('You paid'));
      expect(find.byKey(const ValueKey('preview_icon')), findsOneWidget);
    });

    testWidgets('editing a highlighted word updates the card instantly', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, _dinner);

      await tester.tap(find.byKey(const ValueKey('pill_title_0')));
      await settle(tester, 700);
      await tester.enterText(
        find.byKey(const ValueKey('inline_edit_field')),
        'Izakaya night',
      );
      await tester.tap(find.byKey(const ValueKey('inline_edit_save')));
      await settle(tester, 300);
      expect(_preview(tester, 'preview_title'), 'Izakaya night');

      await tester.tap(find.byKey(const ValueKey('pill_amount_0')));
      await settle(tester, 700);
      await tester.enterText(
        find.byKey(const ValueKey('inline_edit_field')),
        '6000',
      );
      await tester.tap(find.byKey(const ValueKey('inline_edit_save')));
      await settle(tester, 300);
      expect(_preview(tester, 'preview_amount'), '¥6,000');
      expect(_preview(tester, 'preview_each'), '¥2,000 each');
    });

    testWidgets('changing category, payer and currency updates the card', (
      tester,
    ) async {
      await _pump(tester);
      await _toReview(tester, _dinner);

      Color iconColor() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const ValueKey('preview_icon')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      final before = iconColor();
      await tester.tap(find.byKey(const ValueKey('cat_badge_0')));
      await settle(tester, 400);
      await tester.tap(find.text('Transport').last);
      await settle(tester, 400);
      expect(iconColor(), isNot(before));

      await tester.ensureVisible(find.byKey(const ValueKey('payer_menu')));
      await tester.tap(find.byKey(const ValueKey('payer_menu')));
      await settle(tester, 400);
      await tester.tap(find.text('Alex paid').last);
      await settle(tester, 400);
      expect(_preview(tester, 'preview_meta'), startsWith('Alex paid'));

      await tester.ensureVisible(find.byKey(const ValueKey('currency_menu')));
      await tester.tap(find.byKey(const ValueKey('currency_menu')));
      await settle(tester, 400);
      await tester.tap(find.textContaining('EUR').last);
      await settle(tester, 400);
      expect(_preview(tester, 'preview_amount'), '€4,800');
    });
  });

  group('Pocko-styled selector menus', () {
    testWidgets(
      'the category picker opens a 24px rounded popover with icons and pastel accents',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);
        await tester.tap(find.byKey(const ValueKey('cat_badge_0')));
        await settle(tester, 400);

        final button = tester.widget(
          find.descendant(
            of: find.byKey(const ValueKey('cat_badge_0')),
            matching: find.byWidgetPredicate((w) => w is PopupMenuButton),
          ),
        ) as PopupMenuButton;
        final shape = button.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(24));
        expect(PockoSelector.menuRadius, 24);
        expect(find.text('Meals'), findsWidgets);
        expect(find.text('Transport'), findsWidgets);
        expect(
          find.byIcon(Icons.check_rounded),
          findsWidgets,
          reason: 'selected row is marked',
        );
        expect(find.byType(DropdownButton), findsNothing);
      },
    );

    testWidgets(
      'payer and currency selectors are Pocko pills, not Material dropdowns',
      (tester) async {
        await _pump(tester);
        await _toReview(tester, _dinner);
        expect(find.byType(DropdownButton), findsNothing);
        expect(find.byType(DropdownButtonFormField), findsNothing);
        expect(find.byKey(const ValueKey('payer_menu')), findsOneWidget);
        expect(find.byKey(const ValueKey('currency_menu')), findsOneWidget);
        expect(find.textContaining('You paid'), findsWidgets);
      },
    );
  });
}
