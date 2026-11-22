import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/settings/settings_sheet.dart';
import 'package:travmate/services/hybrid_ai/ai_unavailable.dart';
import 'package:travmate/services/hybrid_ai/expense_normalizer.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/parsed_expense_draft.dart';
import 'package:travmate/services/hybrid_ai/spoken_numbers.dart';
import 'package:travmate/services/network/network_probe.dart';

import 'test_helpers.dart';
import 'voice_dictation_test.dart' show FakeSpeechEngine;

/// Real AI only: no regex "rule engine" ever stands in for Gemini, failures
/// are explained, and the prompts / cross-checks handle percentages,
/// self-corrections and spaced thousands.
class _FailingAi extends HybridAiService {
  _FailingAi(this.error) : super(isMockEnabled: true, simulateLatency: false);
  AiUnavailableException? error;
  final seen = <({String text, bool fromSpeech})>[];
  int calls = 0;

  @override
  Future<HybridAiResult> parseExpenseText({
    required String text,
    InferenceMode? mode,
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
    bool hasReceipt = false,
    bool fromSpeech = false,
  }) {
    calls++;
    seen.add((text: text, fromSpeech: fromSpeech));
    final e = error;
    if (e != null) throw e;
    return super.parseExpenseText(
      text: text,
      mode: mode,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
      hasReceipt: hasReceipt,
      fromSpeech: fromSpeech,
    );
  }
}

class _NanoAi extends HybridAiService {
  _NanoAi(this.status) : super(isMockEnabled: true, simulateLatency: false);
  OnDeviceAiStatus status;
  int downloads = 0;

  @override
  Future<OnDeviceAiStatus> onDeviceStatus() async => status;

  @override
  Future<void> downloadOnDeviceModel() async {
    downloads++;
    status = const OnDeviceAiStatus('downloading', totalBytes: 2097152);
  }
}

List<Map<String, dynamic>> _norm(
  List<Map<String, dynamic>> live,
  String input,
) => ExpenseNormalizer.normalize(
  live,
  userInput: input,
  tripCurrency: 'JPY',
  memberNames: const ['You', 'Alex', 'Maya', 'Liam'],
  defaultPayer: 'You',
);

double _total(Map<String, dynamic> item, {int people = 4}) =>
    ParsedExpenseDraft.fromMap(item).totalFor(people);

void main() {
  setUp(() => NetworkProbe.check = () async => true);

  group('No rule-engine fallback in production', () {
    test(
      'a real service with no runtime throws instead of regex-parsing',
      () async {
        final ai = HybridAiService(simulateLatency: false);
        await expectLater(
          ai.parseExpenseText(text: 'Ramen 4800 yen'),
          throwsA(
            isA<AiUnavailableException>().having(
              (e) => e.kind,
              'kind',
              AiFailureKind.unavailable,
            ),
          ),
        );
      },
    );

    test('offline + no on-device model is reported as offline', () async {
      NetworkProbe.check = () async => false;
      final ai = HybridAiService(simulateLatency: false);
      await expectLater(
        ai.parseExpenseText(text: 'Ramen 4800 yen'),
        throwsA(
          isA<AiUnavailableException>().having(
            (e) => e.kind,
            'kind',
            AiFailureKind.offline,
          ),
        ),
      );
    });

    test('errors are classified honestly', () {
      AiFailureKind k(String raw, {bool online = true}) =>
          AiUnavailableException.fromError(raw, online: online).kind;
      expect(k('anything', online: false), AiFailureKind.offline);
      expect(k('timeout: native runtime'), AiFailureKind.timeout);
      expect(k('Firebase App Check token is invalid'), AiFailureKind.rejected);
      expect(k('[403] permission denied'), AiFailureKind.rejected);
      expect(k('model said nothing'), AiFailureKind.unavailable);
    });

    test(
      'the offline message names On-Device AI and an internet connection',
      () {
        const e = AiUnavailableException(AiFailureKind.offline);
        expect(e.userMessage, contains('offline'));
        expect(e.userMessage, contains('On-Device AI'));
        expect(e.userMessage, contains('internet'));
      },
    );
  });

  group('Spaced thousands, percentages and self-corrections', () {
    test('"2 200 yen" is 2200 (Android dictation splits the comma)', () {
      expect(
        SpokenNumbers.collapseSpacedThousands('Tokyo Tower plushie 2 200 yen'),
        'Tokyo Tower plushie 2200 yen',
      );
      expect(
        SpokenNumbers.collapseSpacedThousands('hotel 10 000 baht'),
        'hotel 10000 baht',
      );
      expect(
        SpokenNumbers.collapseSpacedThousands('taxi 500 yen'),
        'taxi 500 yen',
      );
      expect(
        SpokenNumbers.collapseSpacedThousands('date 2026 11 21'),
        'date 2026 11 21',
      );
    });

    test('"4,200... oh wait no, 4,800" keeps only 4,800', () {
      expect(
        SpokenNumbers.normalize(
          SpokenCorrections.resolve(
            'Dinner 4,200 yen... oh wait no, 4,800 yen',
          ),
        ),
        'Dinner 4,800 yen',
      );
      expect(
        SpokenCorrections.resolve('ramen 4200, I mean 4800'),
        'ramen 4800',
      );
      // Nothing to correct: untouched.
      expect(
        SpokenCorrections.resolve('I actually paid for Maya, taxi 3000'),
        'I actually paid for Maya, taxi 3000',
      );
    });

    test(
      'prompt: percent, correction and spaced-thousands rules are explicit',
      () {
        final p = ExpensePromptBuilder.buildPrompt(userInput: 'x');
        expect(p, contains('plus 10 percent'));
        expect(p, contains('5,000 yen plus 10 percent'));
        expect(p, contains('5500'));
        expect(p, contains('oh wait no, 4800'));
        expect(p, contains('"2 200 yen"'));
        expect(p, contains('2200'));
      },
    );

    test('prompt: the model sees the corrected, collapsed sentence', () {
      final p = ExpensePromptBuilder.buildPrompt(
        userInput: 'Dinner 4,200 yen... oh wait no, 4,800 yen',
      );
      expect(p, contains('User Input: "Dinner 4,800 yen"'));
      final q = ExpensePromptBuilder.buildPrompt(
        userInput: 'Tokyo Tower plushie 2 200 yen',
      );
      expect(q, contains('User Input: "Tokyo Tower plushie 2200 yen"'));
    });

    test('prompt: dictation hints only when the words came from speech', () {
      expect(
        ExpensePromptBuilder.buildPrompt(userInput: 'x'),
        isNot(contains('Michelle')),
      );
      final hinted = ExpensePromptBuilder.buildPrompt(
        userInput: 'x',
        fromSpeech: true,
      );
      expect(hinted, contains('Michelle'));
      expect(hinted, contains('Matcha'));
      expect(hinted, contains('Ramming'));
      expect(hinted, contains('Shinkansen'));
    });

    test('the audio prompt asks Gemini to spell travel and food words', () {
      final p = ExpensePromptBuilder.buildAudioPrompt();
      for (final w in [
        'Matcha',
        'Ramen',
        'Shinkansen',
        'Gyukatsu',
        'Yakitori',
      ]) {
        expect(p, contains(w));
      }
      expect(p, contains('oh wait no, 4800'));
    });

    test('"5,000 yen plus 10 percent" becomes 5500 after the cross-check', () {
      final out = _norm([
        {
          'title': 'Taxi',
          'unitAmount': 5000,
          'amountMode': 'TOTAL',
          'quantity': 1,
          'extraPercent': 10,
          'currency': 'JPY',
          'category': 'TRANSPORT',
          'payer': 'Maya',
          'splitWith': ['You', 'Maya'],
        },
      ], 'Maya paid 5,000 yen plus 10 percent for the taxi');
      expect(out.single['payer'], 'Maya');
      expect(ParsedExpenseDraft.fromMap(out.single).extraPercent, 10);
      expect(_total(out.single), 5500);
    });

    test('a percentage the sentence never says is still dropped', () {
      final out = _norm([
        {
          'title': 'Taxi',
          'unitAmount': 5000,
          'extraPercent': 10,
          'category': 'TRANSPORT',
        },
      ], 'taxi 5000 yen and ramen 1200 yen');
      expect(ParsedExpenseDraft.fromMap(out.first).extraPercent, 0);
    });

    test('"2 200 yen" is never cross-checked down to 200', () {
      final out = _norm([
        {
          'title': 'Tokyo Tower plushie',
          'unitAmount': 2200,
          'category': 'SOUVENIR',
        },
      ], 'Tokyo Tower plushie 2 200 yen');
      expect(ParsedExpenseDraft.fromMap(out.single).unitAmount, 2200);
    });

    test('a spoken self-correction keeps the final number', () {
      final out = _norm([
        {'title': 'Dinner', 'unitAmount': 4800, 'category': 'MEAL'},
      ], 'Dinner 4,200 yen... oh wait no, 4,800 yen');
      expect(out.single['unitAmount'] ?? out.single['amount'], 4800);
    });
  });

  group('Capture sheet: failure banner, pinned controls, 2-step tap', () {
    Future<_FailingAi> pump(
      WidgetTester tester, {
      AiUnavailableException? error,
      Size size = const Size(390, 800),
      FakeSpeechEngine? stt,
    }) async {
      final ai = _FailingAi(error);
      await pumpPocko(
        tester,
        AiExpenseCaptureSheet(
          enableSpeechRecognition: stt != null,
          speechEngineFactory: stt == null ? null : () => stt,
          enableAudioCapture: false,
        ),
        size: size,
        ai: ai,
      );
      return ai;
    }

    testWidgets(
      'an AI failure shows the reason in a banner; Try again retries',
      (tester) async {
        final ai = await pump(
          tester,
          error: const AiUnavailableException(
            AiFailureKind.timeout,
            detail: 'timeout: the native AI runtime did not answer in time',
          ),
        );
        await tester.enterText(find.byType(TextField), 'Ramen 4800 yen');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await settle(tester, 1500);

        expect(find.byKey(const ValueKey('ai_failure_banner')), findsOneWidget);
        expect(find.textContaining('did not answer in time'), findsWidgets);
        expect(find.textContaining('native AI runtime'), findsOneWidget);
        // No silent downgrade: nothing was parsed.
        expect(find.byKey(const ValueKey('step_review')), findsNothing);
        expect(find.byKey(const ValueKey('step_input')), findsOneWidget);
        // The typed words are still there.
        expect(find.text('Ramen 4800 yen'), findsOneWidget);

        ai.error = null; // connection is back
        await tester.tap(find.byKey(const ValueKey('retry_ai_button')));
        await settle(tester, 1500);
        expect(ai.calls, 2);
        expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      },
    );

    testWidgets('offline with no on-device AI: honest banner, no Try again', (
      tester,
    ) async {
      await pump(
        tester,
        error: const AiUnavailableException(AiFailureKind.offline),
      );
      await tester.enterText(find.byType(TextField), 'Ramen 4800 yen');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm_button')));
      await settle(tester, 1500);
      expect(find.textContaining('On-Device AI'), findsOneWidget);
      expect(find.textContaining('internet'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry_ai_button')), findsNothing);
    });

    testWidgets(
      'a very long transcript scrolls inside a box: Clear and the banner stay above the fold',
      (tester) async {
        await pump(
          tester,
          error: const AiUnavailableException(AiFailureKind.unavailable),
          size: const Size(390, 700),
        );
        final long = List.filled(40, 'ramen 500 yen with Maya').join(', ');
        await tester.enterText(find.byType(TextField), long);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await settle(tester, 1500);

        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final clear = tester.getRect(
          find.byKey(const ValueKey('clear_transcript')),
        );
        final banner = tester.getRect(
          find.byKey(const ValueKey('ai_failure_banner')),
        );
        expect(clear.bottom, lessThan(screen.height));
        expect(banner.bottom, lessThan(screen.height));
        expect(clear.top, greaterThan(0));
        expect(
          find.byKey(const ValueKey('transcript_scroll')),
          findsOneWidget,
          reason: 'long text lives in a scrollable box',
        );
        expect(tester.takeException(), isNull);

        // Clear works without scrolling anywhere.
        await tester.tap(find.byKey(const ValueKey('clear_transcript')));
        await settle(tester, 400);
        expect(find.byKey(const ValueKey('ai_failure_banner')), findsNothing);
      },
    );

    testWidgets(
      'first tap on another item selects it (no keyboard); second tap edits; the pencil edits',
      (tester) async {
        final ai = await pump(tester);
        expect(ai.error, isNull);
        await tester.enterText(
          find.byType(TextField),
          'Ramen 1 thousand for Alex and Maya, and taxi 2 thousand for Liam',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await settle(tester, 1500);

        // Item 0 is selected by default; tap item 1's title once.
        await tester.tap(find.byKey(const ValueKey('pill_title_1')));
        await settle(tester, 600);
        expect(find.byKey(const ValueKey('inline_editor')), findsNothing);
        expect(find.byKey(const ValueKey('inline_edit_field')), findsNothing);
        expect(
          find.byKey(const ValueKey('payer_menu')),
          findsOneWidget,
          reason: 'its preview card + split pills are showing',
        );

        // Second tap on the selected item: editing (and the keyboard).
        await tester.tap(find.byKey(const ValueKey('pill_title_1')));
        await settle(tester, 700);
        expect(find.byKey(const ValueKey('inline_edit_field')), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel'));
        await settle(tester, 400);

        // The explicit pencil opens editing for the selected item.
        expect(find.byKey(const ValueKey('inline_edit_field')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('edit_item_1')));
        await settle(tester, 700);
        expect(find.byKey(const ValueKey('inline_edit_field')), findsOneWidget);
      },
    );

    testWidgets(
      'no offline speech pack: the mic stops ONCE with an explanation (it never flips on and off)',
      (tester) async {
        final stt = FakeSpeechEngine();
        await pump(tester, stt: stt);
        await tester.tap(find.byIcon(Icons.mic_rounded).last);
        await settle(tester, 300);
        expect(stt.listenCalls, 1);

        stt.error('error_language_unavailable', permanent: true);
        await settle(tester, 400);
        stt.sessionEnds(); // the recognizer's own "done" must not restart it
        await settle(tester, 800);

        expect(stt.listenCalls, 1, reason: 'no restart loop');
        expect(
          find.byKey(const ValueKey('input_error_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Speech Services by Google'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.mic_rounded), findsWidgets);
      },
    );

    testWidgets(
      'no connection for speech: banner tells you to type or go online',
      (tester) async {
        final stt = FakeSpeechEngine();
        await pump(tester, stt: stt);
        await tester.tap(find.byIcon(Icons.mic_rounded).last);
        await settle(tester, 300);
        stt.error('error_network', permanent: true);
        await settle(tester, 500);
        expect(find.textContaining('no offline speech pack'), findsOneWidget);
        expect(find.textContaining('keyboard'), findsOneWidget);
      },
    );

    testWidgets(
      'offline dictation: "2 200" is sent as 2200 and flagged as speech for the hints',
      (tester) async {
        final stt = FakeSpeechEngine();
        final ai = await pump(tester, stt: stt);
        await tester.tap(find.byIcon(Icons.mic_rounded).last);
        await settle(tester, 300);
        stt.say('Tokyo Tower plushie', isFinal: true);
        await tester.pump();
        stt.sessionEnds();
        await settle(tester, 300);
        stt.say('2 200 yen', isFinal: true);
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Tokyo Tower plushie 2 200 yen',
          reason: 'earlier words survive the recognizer restart',
        );
        await tester.tap(find.byIcon(Icons.stop_rounded).last);
        await settle(tester, 1500);
        expect(ai.seen.single.text, 'Tokyo Tower plushie 2200 yen');
        expect(ai.seen.single.fromSpeech, isTrue);
        expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      },
    );
  });

  group('Gemini Nano download (Settings)', () {
    testWidgets(
      'not downloaded: shows a Download button that starts the download',
      (tester) async {
        final ai = _NanoAi(const OnDeviceAiStatus('downloadable'));
        await pumpPocko(tester, const OnDeviceAiTile(), ai: ai);
        await tester.pump();
        expect(find.text('On-device AI (Gemini Nano)'), findsOneWidget);
        expect(find.textContaining('Not downloaded yet'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('download_nano_button')));
        await tester.pump(const Duration(seconds: 2));
        expect(ai.downloads, 1);
        expect(find.textContaining('Downloading'), findsOneWidget);
      },
    );

    testWidgets('already available: says it is ready', (tester) async {
      await pumpPocko(
        tester,
        const OnDeviceAiTile(),
        ai: _NanoAi(const OnDeviceAiStatus('available')),
      );
      await tester.pump();
      expect(find.textContaining('Ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('download_nano_button')), findsNothing);
    });

    testWidgets('unsupported (web, iOS, tests): the tile is hidden', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        const OnDeviceAiTile(),
        ai: _NanoAi(OnDeviceAiStatus.unsupported),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('settings_on_device_ai')), findsNothing);
    });
  });

  test(
    'Android labels a Gemini Nano answer as on-device (SDK prints "On Device")',
    () {
      final kt = File(
        'android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt',
      ).readAsStringSync();
      expect(kt, contains('import com.google.firebase.ai.InferenceSource'));
      expect(kt, contains('source == InferenceSource.ON_DEVICE'));
      // The old check matched "ON_DEVICE" against "On Device" and never hit.
      expect(
        kt,
        isNot(
          contains('response.inferenceSource.toString().contains("ON_DEVICE"'),
        ),
      );
    },
  );

  test(
    'web bridge: a hung on-device attempt falls straight through to the cloud',
    () {
      final js = File('web/firebase_ai_web.js').readAsStringSync();
      expect(js, contains('onDeviceBrokenUntil'));
      expect(js, contains('attemptMode = InferenceMode.ONLY_IN_CLOUD'));
      expect(js, contains('getFirebaseModel(attemptMode, model, maxTokens)'));
    },
  );

  test('InferenceSource is untouched by the failure path', () {
    expect(InferenceSource.values, contains(InferenceSource.onDevice));
  });
}
