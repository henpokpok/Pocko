import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/theme/font_prewarm.dart';
import 'package:travmate/features/onboarding/onboarding_screen.dart';

import 'test_helpers.dart';

/// First-swipe smoothness on iPad WebKit: all onboarding pages are built and
/// cached up front, tickers run only for the settled page, and no filter that
/// is slow on WebGL (backdrop / mask blur) is left in the hot paths.
void main() {
  Future<void> pumpLanding(WidgetTester tester) async {
    await pumpPocko(tester, OnboardingScreen(onDone: () {}), scaffold: false);
    await settle(tester, 600);
  }

  Finder offstageAware(Key key) => find.byKey(key, skipOffstage: false);

  group('Onboarding pages are pre-built', () {
    testWidgets('every story page and the setup form exist before any swipe', (
      tester,
    ) async {
      await pumpLanding(tester);
      for (var i = 0; i < 3; i++) {
        expect(
          offstageAware(ValueKey('story_$i')),
          findsOneWidget,
          reason: '$i',
        );
        expect(
          offstageAware(
            ValueKey('scene_${['cafe', 'slipMatch', 'privacyShield'][i]}'),
          ),
          findsOneWidget,
        );
      }
      expect(offstageAware(const ValueKey('setup_page')), findsOneWidget);
    });

    testWidgets('each page is its own repaint boundary and kept alive', (
      tester,
    ) async {
      await pumpLanding(tester);
      const keys = ['story_0', 'story_1', 'story_2', 'setup_page'];
      for (var i = 0; i < 4; i++) {
        expect(offstageAware(ValueKey('prewarm_page_$i')), findsOneWidget);
        // A repaint boundary sits between each page's content and the PageView.
        expect(
          find.ancestor(
            of: offstageAware(ValueKey(keys[i])),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
          reason: keys[i],
        );
      }
      // The illustration itself is also isolated from the page text.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('scene_cafe')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('pages stay built after swiping away and back', (tester) async {
      await pumpLanding(tester);
      await tester.tap(find.byKey(const ValueKey('next_button')));
      await settle(tester, 700);
      await tester.tap(find.byKey(const ValueKey('next_button')));
      await settle(tester, 700);
      expect(offstageAware(const ValueKey('story_0')), findsOneWidget);
      expect(offstageAware(const ValueKey('story_1')), findsOneWidget);
    });
  });

  group('Tickers follow the settled, visible page', () {
    bool tickersOn(WidgetTester tester, int page) {
      // The page content sits below the page's TickerMode.
      const keys = ['story_0', 'story_1', 'story_2', 'setup_page'];
      final ctx = tester.element(offstageAware(ValueKey(keys[page])));
      return TickerMode.valuesOf(ctx).enabled;
    }

    testWidgets('only the current page animates when idle', (tester) async {
      await pumpLanding(tester);
      expect(tickersOn(tester, 0), isTrue);
      expect(tickersOn(tester, 1), isFalse);
      expect(tickersOn(tester, 2), isFalse);
    });

    testWidgets('all tickers pause while dragging and resume when settled', (
      tester,
    ) async {
      await pumpLanding(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('onboarding_pages'))),
      );
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tickersOn(tester, 0), isFalse, reason: 'paused mid-drag');

      await gesture.moveBy(const Offset(-260, 0));
      await gesture.up();
      await settle(tester, 900);
      expect(tickersOn(tester, 0), isFalse);
      expect(tickersOn(tester, 1), isTrue, reason: 'resumed on the new page');
    });
  });

  group('No slow WebGL filters in the hot paths', () {
    String read(String p) => File(p).readAsStringSync();

    test('no MaskFilter / BackdropFilter / ImageFilter anywhere in lib/', () {
      final offenders = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        // Allow mentions in comments only.
        final code = text
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (RegExp(r'MaskFilter|BackdropFilter|ImageFilter|ImageFiltered')
            .hasMatch(code)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('no shadow blur radius above 24 (outside animated glows)', () {
      final big = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        for (final m in RegExp(
          r'blurRadius:\s*(\d+(\.\d+)?)',
        ).allMatches(f.readAsStringSync())) {
          if (double.parse(m.group(1)!) > 24) {
            big.add('${f.path}: ${m.group(0)}');
          }
        }
      }
      expect(big, isEmpty);
    });

    test('the capture mic glow is a gradient, not a blurred shadow', () {
      final src = read('lib/features/capture/ai_expense_capture_sheet.dart');
      expect(src, contains("ValueKey('mic_glow')"));
      expect(src, isNot(contains('blurRadius: 24 + level')));
    });
  });

  group('Font pre-warm', () {
    test('requests every weight the UI uses', () {
      expect(
        FontPrewarm.weights,
        containsAll([
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
          FontWeight.w900,
        ]),
      );
    });

    test('never throws and returns within its timeout', () async {
      final sw = Stopwatch()..start();
      final ok = await FontPrewarm.prewarm(
        timeout: const Duration(milliseconds: 300),
      );
      expect(ok, isA<bool>());
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
