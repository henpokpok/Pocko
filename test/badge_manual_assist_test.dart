import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/expenses/expense_editor_sheet.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/expense_item.dart';

import 'test_helpers.dart';

class _EditorHarness extends ConsumerWidget {
  final bool isNew;
  final ExpenseCategory category;
  final void Function(ExpenseItem?) onResult;
  const _EditorHarness({
    required this.isNew,
    required this.onResult,
    this.category = ExpenseCategory.MISC,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ElevatedButton(
        onPressed: () async {
          final state = ref.read(tripControllerProvider);
          final result = await showExpenseEditor(
            context,
            isNew: isNew,
            tripState: state,
            expense: ExpenseItem(
              id: 'draft',
              title: isNew ? '' : 'Mystery item',
              amount: isNew ? 0 : 500,
              currency: 'JPY',
              category: category,
              payerId: 'you',
              splitWithMemberIds: const ['you', 'alex'],
              createdAt: DateTime.now(),
              inferenceSource: InferenceSource.manual,
            ),
          );
          onResult(result);
        },
        child: const Text('Open editor'),
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester, {
  bool isNew = true,
  ExpenseCategory category = ExpenseCategory.MISC,
  void Function(ExpenseItem?)? onResult,
}) async {
  await pumpPocko(
    tester,
    _EditorHarness(
      isNew: isNew,
      category: category,
      onResult: onResult ?? (_) {},
    ),
    size: const Size(420, 1000),
  );
  await tester.tap(find.text('Open editor'));
  await settle(tester, 700);
}

Finder get _titleField => find.widgetWithText(TextField, 'Expense Title');
Finder get _badge => find.byKey(const ValueKey('pocko_suggestion'));

/// The searchable category selector currently shows [label].
bool _chipSelected(WidgetTester t, String label) => find
    .descendant(
      of: find.byKey(const ValueKey('editor_category')),
      matching: find.text(label),
    )
    .evaluate()
    .isNotEmpty;

/// Opens the category popover and picks [label] by hand.
Future<void> _pickCategory(WidgetTester t, String label) async {
  final trigger = find.byKey(const ValueKey('editor_category'));
  await t.ensureVisible(trigger);
  await t.tap(trigger);
  await settle(t, 400);
  // The popover is searchable (and scrolls): filter so the row is on screen.
  await t.enterText(find.byKey(const ValueKey('selector_search')), label);
  await t.pump();
  await t.tap(find.byKey(ValueKey('selector_row_$label')));
  await settle(t, 400);
}

void main() {
  group('Manual Expense: Pocko auto-category assist (2.5s debounce)', () {
    test('the debounce is 2.5 seconds', () {
      expect(kCategoryAssistDebounce, const Duration(milliseconds: 2500));
    });

    testWidgets(
      'waits for 2.5s of idle typing, then picks the category and shows Pocko',
      (tester) async {
        await _open(tester);
        expect(_chipSelected(tester, 'Miscellaneous'), isTrue);

        await tester.enterText(_titleField, 'Ramen lunch');
        await tester.pump(const Duration(milliseconds: 2300));
        expect(
          _badge,
          findsNothing,
          reason: 'still inside the debounce window',
        );
        expect(_chipSelected(tester, 'Miscellaneous'), isTrue);

        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_badge, findsOneWidget);
        expect(find.text('Pocko suggested Meals'), findsOneWidget);
        expect(_chipSelected(tester, 'Meals'), isTrue);
        expect(_chipSelected(tester, 'Miscellaneous'), isFalse);
        await settle(tester, 700);
      },
    );

    testWidgets(
      'the badge sits beside the CATEGORY header and shows a tiny Pocko',
      (tester) async {
        await _open(tester);
        await tester.enterText(_titleField, 'Shinkansen to Kyoto');
        await settle(tester, 3000);
        expect(find.text('Pocko suggested Transport'), findsOneWidget);
        final header = tester.getRect(find.text('CATEGORY'));
        final badge = tester.getRect(_badge);
        expect(badge.left, greaterThan(header.right));
        expect((badge.center.dy - header.center.dy).abs(), lessThan(16));
      },
    );

    testWidgets('typing again restarts the countdown', (tester) async {
      await _open(tester);
      await tester.enterText(_titleField, 'Ramen');
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.enterText(_titleField, 'Ramen noodles');
      await tester.pump(const Duration(milliseconds: 2000));
      expect(_badge, findsNothing, reason: '4s total but never 2.5s idle');
      await settle(tester, 700);
      expect(_badge, findsOneWidget);
    });

    testWidgets('a hand-picked category is never overridden', (tester) async {
      await _open(tester);
      await _pickCategory(tester, 'Souvenirs');
      await tester.enterText(_titleField, 'Ramen lunch');
      await settle(tester, 3200);
      expect(_chipSelected(tester, 'Souvenirs'), isTrue);
      expect(_badge, findsNothing);
    });

    testWidgets(
      'picking by hand after a suggestion locks it and removes the badge',
      (tester) async {
        await _open(tester);
        await tester.enterText(_titleField, 'Ramen lunch');
        await settle(tester, 3200);
        expect(_badge, findsOneWidget);
        await _pickCategory(tester, 'Apparel');
        expect(_badge, findsNothing);
        await tester.enterText(_titleField, 'Taxi ride');
        await settle(tester, 3200);
        expect(_chipSelected(tester, 'Apparel'), isTrue);
      },
    );

    testWidgets('an unrecognized title stays quiet', (tester) async {
      await _open(tester);
      await tester.enterText(_titleField, 'zzqx plorb');
      await settle(tester, 3200);
      expect(_badge, findsNothing);
      expect(_chipSelected(tester, 'Miscellaneous'), isTrue);
    });

    testWidgets('editing an existing expense never auto-changes its category', (
      tester,
    ) async {
      await _open(tester, isNew: false, category: ExpenseCategory.SOUVENIR);
      await tester.enterText(_titleField, 'Ramen lunch');
      await settle(tester, 3200);
      expect(_badge, findsNothing);
      expect(_chipSelected(tester, 'Souvenirs'), isTrue);
    });

    testWidgets('the suggested category is what gets saved', (tester) async {
      ExpenseItem? saved;
      await _open(tester, onResult: (r) => saved = r);
      await tester.enterText(_titleField, 'Matcha latte');
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '650');
      await settle(tester, 3200);
      final add = find.widgetWithText(ElevatedButton, 'Add Expense');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester, 700);
      expect(saved, isNotNull);
      expect(saved!.category, ExpenseCategory.SNACK_CAFE);
    });
  });

  group('Matcher badge sits on the icon corner', () {
    Future<void> expectCorner(WidgetTester tester) async {
      await settle(tester, 700);
      final badge = find.byKey(const ValueKey('nav_badge_3'));
      expect(badge, findsOneWidget);
      // The icon's own Stack is exactly the 22px glyph.
      final stack = find
          .ancestor(of: badge, matching: find.byType(Stack))
          .first;
      final icon = tester.getRect(stack);
      expect(icon.size, const Size(22, 22));
      final b = tester.getRect(badge);
      expect(b.top, closeTo(icon.top - 5, 0.6), reason: 'top: -5');
      expect(b.right, closeTo(icon.right + 8, 0.6), reason: 'right: -8');
      expect(
        find.descendant(of: stack, matching: find.byType(Icon)),
        findsOneWidget,
        reason: 'the Matcher Icon is wrapped in this Stack',
      );
      final widget = tester.widget<Stack>(stack);
      expect(widget.clipBehavior, Clip.none);
    }

    testWidgets('bottom navigation bar (phone)', (tester) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      await expectCorner(tester);
    });

    testWidgets('side rail (tablet / desktop)', (tester) async {
      await pumpPocko(
        tester,
        const PockoMainShell(),
        scaffold: false,
        size: const Size(1180, 820),
      );
      await expectCorner(tester);
    });
  });
}
