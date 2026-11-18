import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/widgets/pocko_selector.dart';
import 'package:travmate/core/widgets/pocko_toast.dart';
import 'package:travmate/features/capture/selected_names.dart';

import 'test_helpers.dart';

Widget _selector(int count, ValueChanged<String> onPick, {String? selected}) {
  return Center(
    child: PockoSelector<String>(
      key: const ValueKey('sel'),
      label: 'Pick',
      onDark: false,
      selected: selected,
      onSelected: onPick,
      entries: [
        for (var i = 0; i < count; i++)
          PockoMenuEntry<String>(value: 'v$i', label: 'Option $i'),
      ],
    ),
  );
}

void main() {
  group('PockoSelector: compact, scrollable, searchable', () {
    testWidgets('a long list is capped at 320 px and scrolls', (tester) async {
      await pumpPocko(
        tester,
        _selector(40, (_) {}),
        size: const Size(390, 900),
      );
      await tester.tap(find.byKey(const ValueKey('sel')));
      await settle(tester, 400);

      final panel = tester.getSize(
        find.byKey(const ValueKey('selector_panel')),
      );
      expect(panel.height, lessThanOrEqualTo(320));
      expect(panel.height, greaterThan(200), reason: 'it uses the room it has');
      expect(find.byKey(const ValueKey('selector_list')), findsOneWidget);
      // The far end of the list is not on screen until it is scrolled to.
      final last = find.byKey(const ValueKey('selector_row_Option 39'));
      expect(
        tester.getRect(last).bottom >
                tester
                    .getRect(find.byKey(const ValueKey('selector_panel')))
                    .bottom ||
            tester.getRect(last).top >
                tester
                    .getRect(find.byKey(const ValueKey('selector_panel')))
                    .bottom,
        isTrue,
      );
      await tester.ensureVisible(last);
      await tester.pump();
      await tester.tap(last);
      await settle(tester, 300);
    });

    testWidgets('more than 5 options show an instant search field', (
      tester,
    ) async {
      String? picked;
      await pumpPocko(tester, _selector(12, (v) => picked = v));
      await tester.tap(find.byKey(const ValueKey('sel')));
      await settle(tester, 400);

      expect(find.byKey(const ValueKey('selector_search')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('selector_search')),
        'option 1',
      );
      await tester.pump();
      // "Option 1", "Option 10" and "Option 11" match.
      expect(
        find.byKey(const ValueKey('selector_row_Option 1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('selector_row_Option 10')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('selector_row_Option 2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('selector_row_Option 10')));
      await settle(tester, 300);
      expect(picked, 'v10');
    });

    testWidgets('no matches says so; clearing the query restores the list', (
      tester,
    ) async {
      await pumpPocko(tester, _selector(8, (_) {}));
      await tester.tap(find.byKey(const ValueKey('sel')));
      await settle(tester, 400);
      await tester.enterText(
        find.byKey(const ValueKey('selector_search')),
        'zzz',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('selector_empty')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('selector_search')), '');
      await tester.pump();
      expect(find.byKey(const ValueKey('selector_empty')), findsNothing);
      expect(
        find.byKey(const ValueKey('selector_row_Option 0')),
        findsOneWidget,
      );
    });

    testWidgets('5 or fewer options have no search field', (tester) async {
      await pumpPocko(tester, _selector(5, (_) {}));
      await tester.tap(find.byKey(const ValueKey('sel')));
      await settle(tester, 400);
      expect(find.byKey(const ValueKey('selector_search')), findsNothing);
      expect(
        find.byKey(const ValueKey('selector_row_Option 4')),
        findsOneWidget,
      );
    });
  });

  group('showPockoToast', () {
    Widget host(
      VoidCallback? onAction, {
      String? actionLabel,
      String? detail,
    }) => Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => showPockoToast(
            context,
            message: 'Ramen logged',
            detail: detail,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
          child: const Text('Toast'),
        ),
      ),
    );

    testWidgets('pill card: icon, bold message, detail, shrinking 5 s bar', (
      tester,
    ) async {
      await pumpPocko(tester, host(null, detail: '¥1,200 • split 3 ways'));
      await tester.tap(find.text('Toast'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('pocko_toast')), findsOneWidget);
      expect(find.byKey(const ValueKey('toast_icon')), findsOneWidget);
      expect(find.text('Ramen logged'), findsOneWidget);
      expect(find.text('¥1,200 • split 3 ways'), findsOneWidget);
      expect(find.byKey(const ValueKey('toast_action')), findsNothing);

      double bar() => tester
          .widget<FractionallySizedBox>(
            find.ancestor(
              of: find.byKey(const ValueKey('toast_progress')),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .widthFactor!;
      final early = bar();
      await tester.pump(const Duration(milliseconds: 2000));
      final later = bar();
      expect(early, greaterThan(0.85));
      expect(later, lessThan(early));
      expect(later, closeTo(0.58, 0.08));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('auto-dismisses after 5 s even with an Undo action', (
      tester,
    ) async {
      await pumpPocko(tester, host(() {}, actionLabel: 'Undo'));
      await tester.tap(find.text('Toast'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('toast_action')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 4500));
      expect(
        find.byKey(const ValueKey('pocko_toast')),
        findsOneWidget,
        reason: 'still visible just before 5 s',
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('pocko_toast')),
        findsNothing,
        reason: 'gone after 5 s',
      );
    });

    testWidgets('Undo runs its callback and dismisses', (tester) async {
      var undone = 0;
      await pumpPocko(tester, host(() => undone++, actionLabel: 'Undo'));
      await tester.tap(find.text('Toast'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('toast_action')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(undone, 1);
      expect(find.byKey(const ValueKey('pocko_toast')), findsNothing);
    });

    testWidgets('a new toast replaces the one on screen', (tester) async {
      await pumpPocko(tester, host(null));
      await tester.tap(find.text('Toast'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Toast'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('pocko_toast')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('error toasts use the error look', (tester) async {
      await pumpPocko(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showPockoToast(
                context,
                message: 'Could not join',
                kind: PockoToastKind.error,
              ),
              child: const Text('Err'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Err'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('formatSelectedNames', () {
    test('"(3) Liam, Maya, Alex"', () {
      expect(
        formatSelectedNames(['Liam', 'Maya', 'Alex']),
        '(3) Liam, Maya, Alex',
      );
      expect(formatSelectedNames(['You']), '(1) You');
      expect(formatSelectedNames([]), '');
    });

    test('long lists end with a clean ellipsis on a name boundary', () {
      final out = formatSelectedNames([
        'Liam',
        'Maya',
        'Alex',
        'Jisoo',
        'Min',
        'Hyun',
        'Seo',
      ]);
      expect(out, startsWith('(7) Liam, Maya, Alex'));
      expect(out, endsWith('…'));
      expect(out.length, lessThanOrEqualTo(40));
      expect(out, isNot(contains(', …')));
    });

    test('blank names are ignored and counted out', () {
      expect(formatSelectedNames(['Alex', ' ', 'Maya']), '(2) Alex, Maya');
    });
  });
}
