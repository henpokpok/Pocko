import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/widgets/pocko_mascot.dart';

void main() {
  group('PockoMascot Widget Tests', () {
    testWidgets('Renders PockoMascot in waving mood without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PockoMascot(
                animate: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PockoMascot), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renders PockoMascot across all moods successfully', (
      tester,
    ) async {
      for (final mood in PockoMood.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PockoMascot(mood: mood, size: 100, animate: false),
              ),
            ),
          ),
        );

        expect(find.byType(PockoMascot), findsOneWidget);
        await tester.pump();
      }
    });
  });
}
