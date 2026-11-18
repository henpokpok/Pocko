import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/theme/app_theme.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';

/// Zero-latency, always-simulated AI so widget tests are deterministic.
HybridAiService testAiService() =>
    HybridAiService(isMockEnabled: true, simulateLatency: false);

/// Pumps [child] inside a themed MaterialApp + ProviderScope at a given logical size.
Future<ProviderContainer> pumpPocko(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double bottomInset = 0,
  bool scaffold = true,
  HybridAiService? ai,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  final container = ProviderContainer(
    overrides: [
      hybridAiServiceProvider.overrideWithValue(ai ?? testAiService()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: scaffold ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// Lets timers and animated transitions run (the mascot loops forever, so
/// `pumpAndSettle` is not usable).
Future<void> settle(WidgetTester tester, [int ms = 800]) async {
  for (var elapsed = 0; elapsed < ms; elapsed += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
