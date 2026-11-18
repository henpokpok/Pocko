import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/expenses/expense_editor_sheet.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/raw_prompt_note.dart';

import 'test_helpers.dart';

const _ramen = 'Eat ramen with Maya and Liam 500 yen each';

Future<ProviderContainer> _pumpCapture(WidgetTester tester) => pumpPocko(
  tester,
  const AiExpenseCaptureSheet(
    enableSpeechRecognition: false,
    silenceTimeout: Duration(milliseconds: 250),
  ),
  size: const Size(390, 1000),
);

Future<void> _toReview(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm_button')));
  await settle(tester, 1500);
}

String _text(WidgetTester tester, String key) {
  final f = find.byKey(ValueKey(key));
  // The breakdown key sits on a badge container: read its Text.
  final textFinder =
      tester.any(find.descendant(of: f, matching: find.byType(Text)))
      ? find.descendant(of: f, matching: find.byType(Text))
      : f;
  return tester.widget<Text>(textFinder).data!;
}

void main() {
  group('PER_PERSON: live pill sync', () {
    testWidgets(
      '"500 yen each" = 1,500 for You + Maya + Liam, then follows the pills',
      (tester) async {
        await _pumpCapture(tester);
        await _toReview(tester, _ramen);

        // 500 x 3 people, category Meals, badge shows the maths.
        expect(_text(tester, 'preview_amount'), '¥1,500');
        expect(_text(tester, 'preview_title'), 'Ramen');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('expense_preview')),
            matching: find.byIcon(ExpenseCategory.MEAL.icon),
          ),
          findsOneWidget,
        );
        expect(_text(tester, 'preview_breakdown'), '¥1,500 (¥500 × 3 each)');
        expect(_text(tester, 'focus_label'), startsWith('(3) '));
        // The transcript pill shows the live total.
        expect(find.text('¥1,500'), findsWidgets);

        // Remove Liam on the bottom bar: 500 x 2 = 1,000.
        await tester.tap(find.byKey(const ValueKey('member_liam')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_text(tester, 'preview_amount'), '¥1,000');
        expect(_text(tester, 'preview_breakdown'), '¥1,000 (¥500 × 2 each)');

        // Add Alex: 500 x 3 = 1,500 again.
        await tester.tap(find.byKey(const ValueKey('member_alex')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_text(tester, 'preview_amount'), '¥1,500');

        // Add Liam back: 500 x 4 = 2,000.
        await tester.tap(find.byKey(const ValueKey('member_liam')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_text(tester, 'preview_amount'), '¥2,000');
        expect(_text(tester, 'preview_breakdown'), '¥2,000 (¥500 × 4 each)');
      },
    );

    testWidgets('the name in the transcript toggles the same live total', (
      tester,
    ) async {
      await _pumpCapture(tester);
      await _toReview(tester, _ramen);
      await tester.tap(find.byKey(const ValueKey('member_token_liam_0')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_text(tester, 'preview_amount'), '¥1,000');
    });

    testWidgets('the committed expense stores the live total', (tester) async {
      final container = await _pumpCapture(tester);
      await _toReview(tester, _ramen);
      await tester.tap(find.byKey(const ValueKey('member_liam')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final added = container.read(tripControllerProvider).trip.expenses.last;
      expect(added.amount, 1000);
      expect(added.category, ExpenseCategory.MEAL);
      expect(added.splitWithMemberIds, unorderedEquals(['you', 'maya']));
      await settle(tester, 1200);
    });

    testWidgets('a plain price shows no breakdown and ignores member taps', (
      tester,
    ) async {
      await _pumpCapture(tester);
      await _toReview(tester, 'Ramen 4800 split 4 ways');
      expect(find.byKey(const ValueKey('preview_breakdown')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('member_liam')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_text(tester, 'preview_amount'), '¥4,800');
    });

    testWidgets('a hand-typed price detaches from the per-person maths', (
      tester,
    ) async {
      await _pumpCapture(tester);
      await _toReview(tester, _ramen);
      await tester.tap(find.byKey(const ValueKey('pill_amount_0')));
      await settle(tester, 400);
      final editor = find.descendant(
        of: find.byKey(const ValueKey('inline_editor')),
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, '1800');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, 400);
      expect(_text(tester, 'preview_amount'), '¥1,800');
      await tester.tap(find.byKey(const ValueKey('member_liam')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        _text(tester, 'preview_amount'),
        '¥1,800',
        reason: 'user total wins',
      );
    });

    testWidgets('quantity and service charge badges', (tester) async {
      await _pumpCapture(tester);
      await _toReview(tester, '4 coffees at 5 dollars a cup');
      expect(_text(tester, 'preview_amount'), '\$20');
      expect(_text(tester, 'preview_breakdown'), '\$20 (4 × \$5)');
    });

    testWidgets('percent badge', (tester) async {
      await _pumpCapture(tester);
      await _toReview(tester, 'Dinner 10 thousand yen plus 10% service charge');
      expect(_text(tester, 'preview_amount'), '¥11,000');
      expect(_text(tester, 'preview_breakdown'), '¥11,000 (¥10,000 + 10%)');
    });
  });

  group('Natural phrases through the capture overlay', () {
    testWidgets('"Bought water for Maya" vs "Water with Maya"', (tester) async {
      final container = await _pumpCapture(tester);
      await _toReview(tester, 'Bought water for Maya 200 yen');
      expect(_text(tester, 'focus_label'), '(1) Maya');
      await tester.tap(find.byKey(const ValueKey('back_button')));
      await settle(tester, 400);
      await tester.enterText(find.byType(TextField), 'Water with Maya 200 yen');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await settle(tester, 1500);
      expect(_text(tester, 'focus_label'), contains('You'));
      expect(_text(tester, 'focus_label'), startsWith('(2) '));
      expect(container, isNotNull);
    });

    testWidgets('"Maya paid 6 thousand yen for taxi with everyone"', (
      tester,
    ) async {
      final container = await _pumpCapture(tester);
      await _toReview(
        tester,
        'Maya paid 6 thousand yen for taxi with everyone',
      );
      expect(_text(tester, 'preview_amount'), '¥6,000');
      expect(_text(tester, 'preview_meta'), startsWith('Maya paid'));
      expect(_text(tester, 'focus_label'), startsWith('(4) '));
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final added = container.read(tripControllerProvider).trip.expenses.last;
      expect(added.payerId, 'maya');
      expect(added.amount, 6000);
      await settle(tester, 1200);
    });

    testWidgets('a compound utterance becomes two expenses', (tester) async {
      final container = await _pumpCapture(tester);
      final before = container
          .read(tripControllerProvider)
          .trip
          .expenses
          .length;
      await _toReview(
        tester,
        'Matcha 600 yen for me, and gyoza 1200 yen with Alex',
      );
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final all = container.read(tripControllerProvider).trip.expenses;
      expect(all.length, before + 2);
      expect(all[all.length - 2].amount, 600);
      expect(all[all.length - 2].splitWithMemberIds, ['you']);
      expect(all.last.amount, 1200);
      await settle(tester, 1200);
    });
  });

  group('Itemized bill through the capture overlay', () {
    const bill =
        'Sushiro dinner, I paid: mine 1200, Maya salmon 1800, Liam udon 950';

    testWidgets(
      'one expense with the Itemized split badge and the exact total',
      (tester) async {
        final container = await _pumpCapture(tester);
        final before = container
            .read(tripControllerProvider)
            .trip
            .expenses
            .length;
        await _toReview(tester, bill);

        expect(find.byKey(const ValueKey('preview_itemized')), findsOneWidget);
        expect(find.text('Itemized split'), findsOneWidget);
        expect(_text(tester, 'preview_amount'), '¥3,950');
        expect(_text(tester, 'focus_label'), startsWith('(3) '));

        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 200));
        final all = container.read(tripControllerProvider).trip.expenses;
        expect(all.length, before + 1, reason: 'ONE expense, not three');
        final e = all.last;
        expect(e.isItemized, isTrue);
        expect(e.amount, 3950);
        expect(e.customSplits, {'you': 1200.0, 'maya': 1800.0, 'liam': 950.0});
        expect(e.createdByUid, isNotNull);
        expect(RawPromptNote.parse(e.note).raw, bill);
        await settle(tester, 1200);
      },
    );

    testWidgets('an ordinary sentence shows no itemized badge', (tester) async {
      await _pumpCapture(tester);
      await _toReview(tester, 'Ramen 4800 yen split 4 ways');
      expect(find.byKey(const ValueKey('preview_itemized')), findsNothing);
    });
  });

  group('Raw prompt audit trail (Expense.note)', () {
    testWidgets('Confirm stores the exact verbatim prompt', (tester) async {
      final container = await _pumpCapture(tester);
      await _toReview(tester, _ramen);
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final added = container.read(tripControllerProvider).trip.expenses.last;
      expect(added.note, 'Raw prompt: "$_ramen"');
      await settle(tester, 1200);
    });

    testWidgets('every item of one utterance keeps the full prompt', (
      tester,
    ) async {
      const text =
          'Ramen 4800 split 4 ways, and Shinkansen tickets 18200 for Alex, Maya, and me';
      final container = await _pumpCapture(tester);
      await _toReview(tester, text);
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await tester.pump(const Duration(milliseconds: 200));
      final all = container.read(tripControllerProvider).trip.expenses;
      expect(all[all.length - 2].note, 'Raw prompt: "$text"');
      expect(all.last.note, 'Raw prompt: "$text"');
      await settle(tester, 1200);
    });

    test('compose / parse round trip', () {
      final n = RawPromptNote.compose(
        'Eat "ramen" 500 each',
        extra: 'extra line',
      );
      expect(n, 'Raw prompt: "Eat "ramen" 500 each"\nextra line');
      final p = RawPromptNote.parse(n);
      expect(p.raw, 'Eat "ramen" 500 each');
      expect(p.rest, 'extra line');
      expect(RawPromptNote.parse('Just a note').raw, isNull);
      expect(RawPromptNote.parse('Just a note').rest, 'Just a note');
      expect(RawPromptNote.parse(null).rest, '');
      expect(RawPromptNote.compose('x'), 'Raw prompt: "x"');
    });

    testWidgets(
      'the edit sheet shows the original prompt and keeps it on save',
      (tester) async {
        ExpenseItem? saved;
        await pumpPocko(
          tester,
          Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  saved = await showExpenseEditor(
                    context,
                    tripState: ref.read(tripControllerProvider),
                    expense: ExpenseItem(
                      id: 'e1',
                      title: 'Ramen',
                      amount: 1500,
                      currency: 'JPY',
                      category: ExpenseCategory.MEAL,
                      payerId: 'you',
                      splitWithMemberIds: const ['you', 'maya', 'liam'],
                      createdAt: DateTime.now(),
                      inferenceSource: InferenceSource.onDevice,
                      note: RawPromptNote.compose(_ramen),
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
          size: const Size(420, 1100),
        );
        await tester.tap(find.text('Open editor'));
        await settle(tester, 700);

        expect(find.byKey(const ValueKey('raw_prompt_card')), findsOneWidget);
        expect(find.byIcon(Icons.record_voice_over_rounded), findsOneWidget);
        expect(find.text(_ramen), findsOneWidget);
        expect(find.text('ORIGINAL VOICE / TEXT PROMPT'), findsOneWidget);

        // The user's own note goes next to it; the prompt is never lost.
        final noteField = find.widgetWithText(TextField, 'Note (optional)');
        await tester.ensureVisible(noteField);
        await tester.enterText(noteField, 'Great broth');
        final save = find.text('Save Changes');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await settle(tester, 500);
        expect(saved!.note, 'Raw prompt: "$_ramen"\nGreat broth');
        final parsed = RawPromptNote.parse(saved!.note);
        expect(parsed.raw, _ramen);
        expect(parsed.rest, 'Great broth');
      },
    );

    testWidgets('manual expenses have no prompt card', (tester) async {
      await pumpPocko(
        tester,
        Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => showExpenseEditor(
                context,
                isNew: true,
                tripState: ref.read(tripControllerProvider),
                expense: ExpenseItem(
                  id: 'm',
                  title: '',
                  amount: 0,
                  currency: 'JPY',
                  payerId: 'you',
                  splitWithMemberIds: const ['you'],
                  createdAt: DateTime.now(),
                  inferenceSource: InferenceSource.manual,
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
        size: const Size(420, 1000),
      );
      await tester.tap(find.text('Open editor'));
      await settle(tester, 700);
      expect(find.byKey(const ValueKey('raw_prompt_card')), findsNothing);
    });

    testWidgets('the Expenses list shows a one-line italic preview', (
      tester,
    ) async {
      final container = await pumpPocko(
        tester,
        const PockoMainShell(),
        scaffold: false,
      );
      container
          .read(tripControllerProvider.notifier)
          .addExpense(
            ExpenseItem(
              id: 'e_prompt',
              title: 'Ramen',
              amount: 1500,
              currency: 'JPY',
              category: ExpenseCategory.MEAL,
              payerId: 'you',
              splitWithMemberIds: const ['you', 'maya', 'liam'],
              createdAt: DateTime.now(),
              inferenceSource: InferenceSource.onDevice,
              note: RawPromptNote.compose(_ramen),
            ),
          );
      await tester.tap(find.text('Expenses'));
      await settle(tester, 600);
      final preview = find.byKey(const ValueKey('raw_prompt_preview_e_prompt'));
      await tester.ensureVisible(preview);
      expect(preview, findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(of: preview, matching: find.byType(Text)),
      );
      expect(text.data, _ramen);
      expect(text.style!.fontStyle, FontStyle.italic);
      expect(text.maxLines, 1);
      // An expense without a prompt shows none.
      expect(
        find.byKey(const ValueKey('raw_prompt_preview_exp_pre1')),
        findsNothing,
      );
    });
  });
}
