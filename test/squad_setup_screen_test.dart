import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/squad/squad_setup_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

void main() {
  const tall = Size(420, 2000);

  Future<dynamic> pump(WidgetTester tester, {Size size = tall}) => pumpPocko(
    tester,
    SquadSetupScreen(onLaunchCanvas: () {}),
    scaffold: false,
    size: size,
  );

  testWidgets(
    'Shows live group info: members, code, sync status, per-person cost',
    (tester) async {
      final container = await pump(tester);
      final state = container.read(tripControllerProvider);

      expect(find.text('Group & Settings'), findsOneWidget);
      expect(find.text('Travel Group'), findsOneWidget);
      expect(find.text(state.squadCode), findsOneWidget);
      expect(
        find.text('Offline-first • local only'),
        findsOneWidget,
        reason: 'no Firebase in tests: status is honest',
      );
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('¥15,000'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
    },
  );

  testWidgets('Adding members validates names and rejects duplicates', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(find.text('Add'));
    await settle(tester, 500);
    await tester.tap(find.text('Add Friend'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alex');
    await tester.tap(find.text('Add Friend'));
    await tester.pump();
    expect(find.text('alex is already in the group'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Nan');
    await tester.tap(find.text('Add Friend'));
    await settle(tester, 600);
    expect(
      container
          .read(tripControllerProvider)
          .trip
          .members
          .any((m) => m.name == 'Nan'),
      isTrue,
    );
    expect(find.text('Nan'), findsOneWidget);
  });

  testWidgets('Removing a payer is blocked with an explanation', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.tap(find.byTooltip('Remove Alex'));
    await settle(tester, 500);
    expect(find.textContaining('paid for'), findsOneWidget);
    expect(container.read(tripControllerProvider).trip.members.length, 4);
  });

  testWidgets(
    'Join sheet validates the 6-digit code and reports offline mode',
    (tester) async {
      final container = await pump(tester);

      await tester.tap(find.text('Join Group'));
      await settle(tester, 500);
      await tester.enterText(
        find.byKey(const ValueKey('join_code_field')),
        '12',
      );
      await tester.tap(find.byKey(const ValueKey('join_submit_button')));
      await tester.pump();
      expect(
        find.textContaining('Enter the 6-digit group code (e.g. 782-901)'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('join_code_field')),
        '999 001',
      );
      await tester.tap(find.byKey(const ValueKey('join_submit_button')));
      await settle(tester, 700);
      expect(container.read(tripControllerProvider).squadCode, '999-001');
      expect(
        find.textContaining('Group sync is not available'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Switching currency converts every figure and the AI matcher can be paused',
    (tester) async {
      final container = await pump(tester);

      await tester.tap(find.text('Currency'));
      await settle(tester, 500);
      expect(find.text('Select Base Currency'), findsOneWidget);
      await tester.tap(find.textContaining('US Dollar'));
      await settle(tester, 700);
      expect(container.read(tripControllerProvider).trip.baseCurrency, 'USD');
      expect(
        find.text('\$100'),
        findsOneWidget,
        reason: 'per person: ¥15,000 at 150 JPY/USD',
      );

      await tester.tap(find.text('AI Matcher'));
      await tester.pump();
      expect(container.read(tripControllerProvider).isAiMatcherActive, isFalse);
      expect(find.text('Paused'), findsOneWidget);
    },
  );

  testWidgets('Lays out on a 320 px phone and a wide tablet', (tester) async {
    await pump(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    await pump(tester, size: const Size(1100, 800));
    expect(tester.takeException(), isNull);
  });
}
