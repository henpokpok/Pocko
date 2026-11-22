import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/matcher/smart_slip_matcher_screen.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/services/matcher/slip_samples.dart';

import 'test_helpers.dart';

/// Clean-capture polish: custom-split wording, never-truncated match badge,
/// and no third-party brand names in the demo / sample slips.
void main() {
  testWidgets('unequal shares say "Custom split • 3 people", not "each"', (
    tester,
  ) async {
    await pumpPocko(
      tester,
      const AiExpenseCaptureSheet(enableSpeechRecognition: false),
      size: const Size(390, 1100),
    );
    await tester.enterText(
      find.byType(TextField),
      'Sushi dinner, mine 1200, Maya 1800, Liam 950 yen',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm_button')));
    await settle(tester, 1500);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('preview_each'))).data,
      'Custom split • 3 people',
    );
    expect(find.textContaining('each'), findsNothing);
  });

  testWidgets('an equal split still shows the per-person amount', (
    tester,
  ) async {
    await pumpPocko(
      tester,
      const AiExpenseCaptureSheet(enableSpeechRecognition: false),
      size: const Size(390, 1100),
    );
    await tester.enterText(find.byType(TextField), 'Ramen 4800 yen');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm_button')));
    await settle(tester, 1500);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('preview_each'))).data,
      endsWith('each'),
    );
  });

  testWidgets('"Exact match • 100%" is never truncated at 412 px', (
    tester,
  ) async {
    await pumpPocko(
      tester,
      const SmartSlipMatcherScreen(),
      size: const Size(412, 1800),
    );
    final badge = find.byKey(const ValueKey('match_tier_slip_1'));
    expect(badge, findsOneWidget);
    final text = tester.widget<Text>(badge);
    expect(text.data, 'Exact match • 100%');
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    // Wrapped in a scale-down FittedBox: it shrinks instead of showing "…".
    expect(
      find.ancestor(of: badge, matching: find.byType(FittedBox)),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  test('demo and sample slips carry no third-party brand names', () {
    final state = TripState.initial();
    final texts = [
      for (final s in state.slips)
        '${s.bankName} ${s.maskedText} ${s.merchant}',
      for (final s in SlipSamples.all) '${s.title} ${s.subtitle} ${s.rawText}',
    ].join('\n');
    for (final brand in [
      'Chase',
      'Wise',
      'Apple Pay',
      'Suica',
      'Sapphire',
      'JR ',
    ]) {
      expect(texts, isNot(contains(brand)), reason: brand);
    }
    expect(texts, contains('Bank Card'));
    expect(texts, contains('5521'));
  });
}
