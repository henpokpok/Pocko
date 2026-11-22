import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/widgets/pocko_bottom_sheet.dart';
import 'package:travmate/core/widgets/telemetry_pill.dart';

import 'test_helpers.dart';

void main() {
  group('showPockoBottomSheet', () {
    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(400, 800),
      double keyboard = 0,
      double contentHeight = 3000,
    }) async {
      await pumpPocko(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showPockoBottomSheet<void>(
                context: context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: contentHeight,
                      child: const Placeholder(key: ValueKey('tall_content')),
                    ),
                    const TextField(key: ValueKey('sheet_field')),
                  ],
                ),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
        size: size,
        bottomInset: keyboard,
      );
      await tester.tap(find.text('Open sheet'));
      await settle(tester, 700);
    }

    testWidgets(
      'Never grows beyond 80% of the screen height, however tall the content',
      (tester) async {
        await open(tester);
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(
          tester.getSize(sheet).height,
          lessThanOrEqualTo(800 * kPockoSheetMaxHeightFactor + 0.5),
        );
        expect(
          tester.getSize(sheet).height,
          closeTo(640, 1),
          reason: 'tall content fills exactly 80%',
        );
        expect(
          tester.getTopLeft(sheet).dy,
          greaterThanOrEqualTo(800 * 0.2 - 1),
        );
      },
    );

    testWidgets(
      'Short content stays short; the sheet is draggable with a handle and 28px corners',
      (tester) async {
        await open(tester, contentHeight: 120);
        final sheet = find.byType(BottomSheet);
        expect(tester.getSize(sheet).height, lessThan(400));
        final bs = tester.widget<BottomSheet>(sheet);
        expect(bs.enableDrag, isTrue);
        expect(bs.showDragHandle, isTrue);
        final shape = bs.shape as RoundedRectangleBorder;
        expect((shape.borderRadius as BorderRadius).topLeft.x, 28);
      },
    );

    testWidgets('Swiping down dismisses the sheet', (tester) async {
      await open(tester, contentHeight: 200);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.drag(find.byType(BottomSheet), const Offset(0, 500));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Respects the screen height on short phones too', (
      tester,
    ) async {
      await open(tester, size: const Size(320, 480));
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(480 * 0.8 + 0.5),
      );
    });

    test('Every bottom sheet in the app goes through showPockoBottomSheet', () {
      final offenders = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') ||
            f.path.endsWith('pocko_bottom_sheet.dart')) {
          continue;
        }
        if (f.readAsStringSync().contains('showModalBottomSheet(')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'use showPockoBottomSheet for a consistent 80% draggable sheet',
      );
    });
  });

  group('TelemetryFooter', () {
    test('Formats the compact footer exactly', () {
      expect(
        TelemetryFooter.format(InferenceSource.onDevice, 92),
        '🟢 (Local) • 92ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.inCloud, 640),
        '☁️ (Cloud) • 640ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.onDevice, 84, simulated: true),
        '📴 (Local) • 84ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.inCloud, 612, simulated: true),
        '📴 (Local) • 612ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.onDevice, 71, slip: true),
        '🛡️ Local PII Shield • 71ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.inCloud, 640, slip: true),
        '☁️ Cloud Gemini • 640ms',
      );
      expect(
        TelemetryFooter.format(
          InferenceSource.inCloud,
          640,
          slip: true,
          simulated: true,
        ),
        '🛡️ Local PII Shield • 640ms',
      );
      expect(
        TelemetryFooter.format(InferenceSource.manual, null),
        '✏️ (Manual)',
      );
    });

    testWidgets('Renders the footer text', (tester) async {
      await pumpPocko(
        tester,
        const Center(
          child: TelemetryFooter(
            source: InferenceSource.inCloud,
            latencyMs: 640,
          ),
        ),
        size: const Size(320, 200),
      );
      expect(find.text('☁️ (Cloud) • 640ms'), findsOneWidget);
    });
  });
}
