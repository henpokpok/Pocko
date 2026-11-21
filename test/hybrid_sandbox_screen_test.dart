import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/sandbox/hybrid_sandbox_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';

import 'test_helpers.dart';

void main() {
  const tall = Size(520, 3200);

  testWidgets('Renders diagnostics, Remote Config and runtime probe', (
    tester,
  ) async {
    await pumpPocko(
      tester,
      const HybridSandboxScreen(),
      scaffold: false,
      size: tall,
    );
    await settle(tester, 400);

    expect(find.text('Pocko Hybrid AI'), findsOneWidget);
    expect(find.text('Diagnostic Sandbox'), findsOneWidget);
    expect(find.text('Tokyo Trip 🇯🇵'), findsOneWidget);
    expect(find.text('Live Runtime Probe'), findsOneWidget);
    expect(
      find.text('SIMULATED ENGINE'),
      findsOneWidget,
      reason: 'no native/web runtime in flutter test',
    );
    expect(find.text('Live Firebase Remote Config'), findsOneWidget);
    expect(find.text('ai_inference_mode'), findsOneWidget);
    expect(find.text('cloud_fallback_model'), findsOneWidget);
    expect(find.text('prefer_on_device'), findsOneWidget);
    expect(
      find.textContaining('PREFER_ON_DEVICE (web: prefer_on_device)'),
      findsOneWidget,
    );
    expect(find.text('Fetch & Activate'), findsOneWidget);
    expect(find.text('AI Inference Mode'), findsOneWidget);
  });

  testWidgets(
    'Preset → Process shows telemetry, parsed items and raw JSON; Add updates the trip',
    (tester) async {
      final container = await pumpPocko(
        tester,
        const HybridSandboxScreen(),
        scaffold: false,
        size: tall,
      );
      final before = container
          .read(tripControllerProvider)
          .trip
          .expenses
          .length;

      await tester.ensureVisible(
        find.widgetWithText(
          ActionChip,
          'Starbucks matcha latte 650 Maya paid for herself',
        ),
      );
      await tester.tap(
        find.widgetWithText(
          ActionChip,
          'Starbucks matcha latte 650 Maya paid for herself',
        ),
      );
      await tester.pump();

      // Use cloud-only so the cloud telemetry pill is exercised.
      await tester.tap(find.text('Cloud Only'));
      await tester.pump();
      await tester.ensureVisible(find.text('Process with Hybrid AI'));
      await tester.tap(find.text('Process with Hybrid AI'));
      await settle(tester, 800);

      // The test engine is the offline simulation, so the badge must say so (and never SIM).
      expect(find.text('📴 Offline Safety Net • Rule Engine'), findsOneWidget);
      expect(find.text('SIM'), findsNothing);
      expect(find.text('¥650'), findsOneWidget);
      expect(find.text('Snacks & Cafe'), findsOneWidget);
      expect(find.text('View Raw JSON Response from AI'), findsOneWidget);
      expect(find.textContaining('Maya'), findsWidgets);

      final add = find.textContaining('Add 1 to Trip');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester, 600);
      expect(
        container.read(tripControllerProvider).trip.expenses.length,
        before + 1,
      );
    },
  );

  testWidgets(
    'Force-simulated switch and mode selector are interactive without overflow',
    (tester) async {
      await pumpPocko(
        tester,
        const HybridSandboxScreen(),
        scaffold: false,
        size: const Size(360, 3200),
      );
      await tester.ensureVisible(find.text('Local Only'));
      await tester.tap(find.text('Local Only'));
      await tester.pump();
      expect(
        find.textContaining('Override: Strictly On-Device Only'),
        findsOneWidget,
      );
      await tester.tap(find.byType(Switch).first);
      await settle(tester, 400);
      expect(tester.takeException(), isNull);
    },
  );
}
