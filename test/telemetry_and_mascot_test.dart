import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/widgets/pocko_empty_state.dart';
import 'package:travmate/core/widgets/pocko_mascot.dart';
import 'package:travmate/core/widgets/telemetry_pill.dart';

import 'test_helpers.dart';

void main() {
  group('TelemetryPill', () {
    Future<void> pump(WidgetTester tester, TelemetryPill pill) =>
        pumpPocko(tester, Center(child: pill), size: const Size(480, 300));

    testWidgets('On-device pill shows engine and latency', (tester) async {
      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.onDevice,
          latencyMs: 92,
          modelInfo: 'Gemini Nano (AICore)',
        ),
      );
      expect(find.text('🟢 On-Device • Gemini Nano'), findsOneWidget);
      expect(find.text('92 ms'), findsOneWidget);
      expect(find.text('SIM'), findsNothing);
    });

    testWidgets('Apple and Chrome engines are named correctly', (tester) async {
      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.onDevice,
          latencyMs: 61,
          modelInfo:
              'Apple Foundation Models (on-device via Firebase AI Logic)',
        ),
      );
      expect(find.text('🟢 On-Device • Apple FM'), findsOneWidget);

      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.onDevice,
          latencyMs: 80,
          modelInfo: 'Gemini Nano (Chrome Prompt API, on-device)',
        ),
      );
      expect(find.text('🟢 On-Device • Gemini Nano (Chrome)'), findsOneWidget);
    });

    testWidgets('Cloud pill shows Gemini Flash fallback', (tester) async {
      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.inCloud,
          latencyMs: 840,
          modelInfo: 'gemini-2.5-flash',
        ),
      );
      expect(find.text('☁️ Cloud Fallback • Gemini Flash'), findsOneWidget);
      expect(find.text('840 ms'), findsOneWidget);
    });

    testWidgets('Offline results say Offline • Local Rules, never SIM; compact variant is short', (
      tester,
    ) async {
      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.onDevice,
          latencyMs: 90,
          simulated: true,
        ),
      );
      expect(find.text('SIM'), findsNothing);
      expect(find.textContaining('Offline • Local Rules'), findsOneWidget);

      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.inCloud,
          latencyMs: 700,
          compact: true,
        ),
      );
      expect(find.text('☁️ 700 ms'), findsOneWidget);
    });

    testWidgets('Dark variant renders without errors', (tester) async {
      await pump(
        tester,
        const TelemetryPill(
          source: InferenceSource.onDevice,
          latencyMs: 50,
          onDark: true,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PockoMascot', () {
    testWidgets('Renders every mood, animated, including voice level', (
      tester,
    ) async {
      for (final mood in PockoMood.values) {
        await pumpPocko(
          tester,
          Center(child: PockoMascot(mood: mood, size: 120, voiceLevel: 0.8)),
          size: const Size(300, 300),
        );
        expect(find.byType(PockoMascot), findsOneWidget);
        // Cross two blink windows and several wave cycles.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 700));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '$mood threw while animating',
        );
      }
    });

    testWidgets(
      'Static mascot (animate:false) and entrance animation still render',
      (tester) async {
        await pumpPocko(
          tester,
          const Center(
            child: PockoMascot(
              mood: PockoMood.waving,
              size: 40,
              animate: false,
            ),
          ),
          size: const Size(200, 200),
        );
        expect(find.byType(CustomPaint), findsWidgets);
        await pumpPocko(
          tester,
          const Center(
            child: PockoMascot(
              mood: PockoMood.scanning,
              size: 90,
              enableEntranceAnimation: true,
            ),
          ),
          size: const Size(200, 200),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      },
    );

    test('Blink schedule: two short blinks per loop, eyes open otherwise', () {
      expect(PockoPainter.blinkAt(0.29), 1.0);
      expect(PockoPainter.blinkAt(0.74), 1.0);
      expect(PockoPainter.blinkAt(0.0), 0.0);
      expect(PockoPainter.blinkAt(0.5), 0.0);
      expect(PockoPainter.blinkAt(0.295), inExclusiveRange(0.0, 1.0));
    });

    test('Painter repaints when blink, gaze or voice level change', () {
      final a = PockoPainter(mood: PockoMood.listening, animProgress: 0.1);
      expect(
        a.shouldRepaint(
          PockoPainter(mood: PockoMood.listening, animProgress: 0.1),
        ),
        isFalse,
      );
      expect(
        a.shouldRepaint(
          PockoPainter(mood: PockoMood.listening, animProgress: 0.1, blink: 1),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          PockoPainter(
            mood: PockoMood.listening,
            animProgress: 0.1,
            voiceLevel: 0.5,
          ),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          PockoPainter(mood: PockoMood.listening, animProgress: 0.1, gaze: 0.5),
        ),
        isTrue,
      );
    });

    testWidgets('Exposes a semantic label for screen readers', (tester) async {
      await pumpPocko(
        tester,
        const Center(child: PockoMascot(mood: PockoMood.sleepy, size: 80)),
        size: const Size(200, 200),
      );
      expect(find.bySemanticsLabel('Pocko napping'), findsOneWidget);
    });
  });

  testWidgets('PockoEmptyState shows title, message and an action', (
    tester,
  ) async {
    var tapped = false;
    await pumpPocko(
      tester,
      Center(
        child: PockoEmptyState(
          title: 'Nothing here',
          message: 'Add something to begin.',
          actionLabel: 'Add',
          onAction: () => tapped = true,
        ),
      ),
      size: const Size(400, 500),
    );
    await settle(tester, 400);
    expect(find.text('Nothing here'), findsOneWidget);
    await tester.tap(find.text('Add'));
    expect(tapped, isTrue);
  });
}
