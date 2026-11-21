import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/raw_prompt_note.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';
import 'package:travmate/services/hybrid_ai/ai_unavailable.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/network/network_probe.dart';
import 'package:travmate/services/speech/voice_recorder.dart';

import 'test_helpers.dart';
import 'voice_dictation_test.dart' show FakeSpeechEngine;

const _transcript = 'Ramen 4800 yen with Maya and Liam';

HybridAiResult _audioReply({
  String? transcript = _transcript,
  List<Map<String, dynamic>>? items,
}) {
  return HybridAiResult.fromMap({
    'rawJson': jsonEncode({
      'transcript': ?transcript,
      'items':
          items ??
          [
            {
              'title': 'Ramen',
              'unitAmount': 4800,
              'amountMode': 'TOTAL',
              'quantity': 1,
              'extraPercent': 0,
              'currency': 'JPY',
              'category': 'MEAL',
              'payer': 'You',
              'splitWith': ['You', 'Maya', 'Liam'],
            },
          ],
    }),
    'inferenceSource': 'in_cloud',
    'latencyMs': 1480,
    'modelInfo': 'gemini-3.1-flash-lite (Firebase AI Logic Cloud)',
  });
}

/// Real parsing, scripted audio answer.
class FakeAudioAi extends HybridAiService {
  FakeAudioAi({this.online = true, this.reply})
    : super(isMockEnabled: true, simulateLatency: false);

  bool online;
  HybridAiResult? reply;

  /// What the fast transcription-only call returns, and how long each call takes.
  String? preview = _transcript;
  Duration previewDelay = Duration.zero;
  Duration replyDelay = Duration.zero;
  int previewCalls = 0;
  int audioCalls = 0;
  String? lastMime;
  int lastBytes = 0;
  List<String> lastMembers = const [];

  @override
  Future<bool> canTranscribeAudio() async => online;

  @override
  Future<String?> transcribeAudio({
    required String audioBase64,
    String audioMimeType = 'audio/mp4',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
  }) async {
    previewCalls++;
    await Future<void>.delayed(previewDelay);
    return preview;
  }

  @override
  Future<HybridAiResult> parseExpenseAudio({
    required String audioBase64,
    String audioMimeType = 'audio/mp4',
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
  }) async {
    audioCalls++;
    lastMime = audioMimeType;
    lastBytes = base64Decode(audioBase64).length;
    lastMembers = memberNames;
    await Future<void>.delayed(replyDelay);
    final r = reply;
    if (r == null) {
      throw const AiUnavailableException(
        AiFailureKind.timeout,
        detail: 'timeout: scripted',
      );
    }
    return r;
  }
}

class FakeRecorder implements VoiceRecorder {
  void Function(double db)? _onAmp;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  bool permission = true;
  Duration length = const Duration(seconds: 5);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start({required void Function(double db) onAmplitude}) async {
    starts++;
    _onAmp = onAmplitude;
  }

  @override
  Future<RecordedAudio?> stop() async {
    stops++;
    return RecordedAudio(
      bytes: Uint8List.fromList(List.filled(4000, 7)),
      mimeType: 'audio/mp4',
      duration: length,
    );
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> dispose() async {}

  void level(double db) => _onAmp?.call(db);
}

Future<void> _ticks(
  WidgetTester tester,
  FakeRecorder rec,
  double db,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    rec.level(db);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _speakThenSilence(
  WidgetTester tester,
  FakeRecorder rec, {
  int quietTicks = 36,
}) async {
  await _ticks(tester, rec, -52, 6); // room noise: calibrates the detector
  await _ticks(tester, rec, -18, 12); // speaking
  await _ticks(tester, rec, -52, quietTicks);
}

Future<void> _pump(
  WidgetTester tester,
  FakeAudioAi ai,
  FakeRecorder rec, {
  FakeSpeechEngine? stt,
  // The shipping default is 6 s; most timing tests use 3.5 s to stay short.
  Duration audioSilence = const Duration(milliseconds: 3500),
}) async {
  await pumpPocko(
    tester,
    AiExpenseCaptureSheet(
      voiceRecorderFactory: () => rec,
      speechEngineFactory: stt == null ? null : () => stt,
      audioSilenceTimeout: audioSilence,
    ),
    size: const Size(390, 1100),
    ai: ai,
  );
}

Future<void> _tapMic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic_rounded).last);
  await settle(tester, 300);
}

void main() {
  setUp(() => NetworkProbe.check = () async => true);

  group('Gemini audio response parsing', () {
    test('the transcript and the structured items arrive together', () {
      final r = _audioReply();
      expect(r.transcript, _transcript);
      expect(r.items.single['title'], 'Ramen');
      expect(r.drafts.single.unitAmount, 4800);
      expect(r.inferenceSource, InferenceSource.inCloud);
    });

    test('a missing or blank transcript is null, never an empty string', () {
      expect(_audioReply(transcript: null).transcript, isNull);
      expect(_audioReply(transcript: '   ').transcript, isNull);
      expect(HybridAiResult.fromMap({'rawJson': '{}'}).transcript, isNull);
    });

    test('markdown-fenced answers still parse', () {
      final r = HybridAiResult.fromMap({
        'rawJson': '```json\n{"transcript":"Taxi 2000","items":[{"title":"Taxi","unitAmount":2000}]}\n```',
      });
      expect(r.transcript, 'Taxi 2000');
      expect(r.items.length, 1);
    });

    test('normalizeAudioResult repairs the items and keeps the transcript', () {
      final service = HybridAiService(
        isMockEnabled: true,
        simulateLatency: false,
      );
      final live = _audioReply(
        transcript: 'Eat ramen with Maya and Liam for 8 thousand yen',
        items: [
          {
            'title': 'Eat Ramen',
            'unitAmount': 8,
            'currency': 'JPY',
            'category': 'MEAL',
            'payer': 'You',
            'splitWith': ['You'],
          },
        ],
      );
      final fixed = service.normalizeAudioResult(
        live,
        tripCurrency: 'JPY',
        memberNames: const ['You', 'Alex', 'Maya', 'Liam'],
        defaultPayer: 'You',
      );
      expect(
        fixed.transcript,
        'Eat ramen with Maya and Liam for 8 thousand yen',
      );
      final d = fixed.drafts.single;
      expect(d.title, 'Ramen');
      expect(d.unitAmount, 8000);
      expect(d.splitWith, unorderedEquals(['You', 'Maya', 'Liam']));
      expect(d.category, ExpenseCategory.MEAL);
    });

    test('the transcription-only prompt is tiny and asks for JSON', () {
      final p = ExpensePromptBuilder.buildTranscribePrompt(
        memberNames: const ['You', 'Maya'],
      );
      expect(p, contains('verbatim'));
      expect(p, contains('{"transcript"'));
      expect(p, contains('You, Maya'));
      expect(p.split(RegExp(r'\s+')).length, lessThan(70));
    });

    test('the audio prompt asks for the verbatim transcript plus items', () {
      final p = ExpensePromptBuilder.buildAudioPrompt(
        tripCurrency: 'THB',
        memberNames: const ['You', 'Ploy'],
        defaultPayer: 'You',
      );
      expect(p, contains('"transcript": "exact words spoken"'));
      expect(p, contains('"items"'));
      expect(p, contains('audio clip'));
      expect(p, contains('verbatim'));
      expect(p, contains('Currency: THB'));
      expect(p, contains('Members: [You, Ploy]'));
      expect(p, isNot(contains('User Input:')));
      // The text prompt is unchanged and has no transcript field.
      expect(
        ExpensePromptBuilder.buildPrompt(userInput: 'Ramen 500'),
        isNot(contains('"transcript"')),
      );
    });
  });

  group('SilenceDetector (3.5 s dead air after speech)', () {
    Duration t(int ticks) => Duration(milliseconds: ticks * 100);

    test('never fires before anyone has spoken', () {
      final d = SilenceDetector();
      for (var i = 0; i < 200; i++) {
        expect(d.update(-52, t(i)), isFalse);
      }
      expect(d.speechStarted, isFalse);
    });

    test(
      'fires after exactly 3.5 s below the threshold once speech started',
      () {
        final d = SilenceDetector();
        var i = 0;
        for (; i < 6; i++) {
          d.update(-52, t(i));
        }
        for (var k = 0; k < 10; k++, i++) {
          expect(d.update(-18, t(i)), isFalse);
        }
        expect(d.speechStarted, isTrue);
        final lastLoud = i - 1;
        var fired = -1;
        for (; i < lastLoud + 60; i++) {
          if (d.update(-52, t(i))) {
            fired = i;
            break;
          }
        }
        expect(fired - lastLoud, 35, reason: '35 ticks x 100 ms = 3.5 s');
      },
    );

    test('a new loud reading resets the countdown', () {
      final d = SilenceDetector();
      for (var i = 0; i < 6; i++) {
        d.update(-52, t(i));
      }
      d.update(-18, t(6));
      for (var i = 7; i < 40; i++) {
        expect(d.update(-52, t(i)), isFalse); // 3.3 s of quiet
      }
      d.update(-18, t(40)); // speaks again
      for (var i = 41; i < 75; i++) {
        expect(d.update(-52, t(i)), isFalse);
      }
      expect(d.update(-52, t(76)), isTrue);
    });

    test('the threshold follows a noisy room but stays in range', () {
      final noisy = SilenceDetector();
      for (var i = 0; i < 6; i++) {
        noisy.update(-30, t(i));
      }
      expect(noisy.thresholdDb, -25, reason: 'clamped to the maximum');
      final quiet = SilenceDetector();
      for (var i = 0; i < 6; i++) {
        quiet.update(-80, t(i));
      }
      expect(quiet.thresholdDb, -45, reason: 'clamped to the minimum');
    });
  });

  group('WAV wrapper for Web recordings', () {
    test('writes a valid 44-byte PCM header', () {
      final pcm = Uint8List.fromList(List.generate(100, (i) => i));
      final wav = PlatformVoiceRecorder.pcmToWav(pcm, sampleRate: 16000);
      expect(wav.length, 144);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      final h = ByteData.sublistView(wav);
      expect(h.getUint32(4, Endian.little), 136);
      expect(h.getUint32(24, Endian.little), 16000);
      expect(h.getUint16(22, Endian.little), 1);
      expect(h.getUint32(40, Endian.little), 100);
      expect(wav.sublist(44), pcm);
    });
  });

  group('Voice capture via Gemini audio (widget)', () {
    testWidgets(
      'one uninterrupted recording, 3.5 s of silence, transcript + items, note saved',
      (tester) async {
        final ai = FakeAudioAi(reply: _audioReply());
        final rec = FakeRecorder();
        await _pump(tester, ai, rec);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AiExpenseCaptureSheet)),
        );
        final before = container
            .read(tripControllerProvider)
            .trip
            .expenses
            .length;

        await _tapMic(tester);
        expect(rec.starts, 1, reason: 'a single recording, never restarted');

        await _ticks(tester, rec, -52, 6);
        await _ticks(tester, rec, -18, 12);
        await _ticks(tester, rec, -52, 34); // 3.4 s of dead air
        expect(rec.stops, 0, reason: 'not yet 3.5 s of silence');
        await _ticks(tester, rec, -52, 2);
        await settle(tester, 1500);
        expect(rec.stops, 1);
        expect(rec.starts, 1);

        // Sent to Gemini as inline audio with the trip context.
        expect(ai.audioCalls, 1);
        expect(ai.lastMime, 'audio/mp4');
        expect(ai.lastBytes, 4000);
        expect(ai.lastMembers, containsAll(['You', 'Maya', 'Liam']));

        // The verbatim transcript drives the highlighted review.
        expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('preview_amount')))
              .data,
          '¥4,800',
        );
        await tester.tap(find.byKey(const ValueKey('confirm_button')));
        await tester.pump(const Duration(milliseconds: 200));
        final added = container.read(tripControllerProvider).trip.expenses.last;
        expect(
          container.read(tripControllerProvider).trip.expenses.length,
          before + 1,
        );
        expect(added.title, 'Ramen');
        expect(RawPromptNote.parse(added.note).raw, _transcript);
        await settle(tester, 1200);
      },
    );

    testWidgets('the transcript appears while Gemini is still analyzing', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply())
        ..previewDelay = const Duration(milliseconds: 300)
        ..replyDelay = const Duration(milliseconds: 2200);
      final rec = FakeRecorder();
      await _pump(tester, ai, rec);
      await _tapMic(tester);
      await _ticks(tester, rec, -18, 8);
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await tester.pump(const Duration(milliseconds: 100));

      // Before any words arrive: an honest placeholder.
      expect(find.byKey(const ValueKey('step_processing')), findsOneWidget);
      expect(
        find.text('Transcribing'),
        findsOneWidget,
      ); // words of the placeholder

      // The fast call returns at ~300 ms and the words reveal one by one.
      await tester.pump(const Duration(milliseconds: 500));
      final partial = find.descendant(
        of: find.byKey(const ValueKey('analyzing_shimmer')),
        matching: find.byType(Text),
      );
      expect(partial, findsWidgets, reason: 'some words are already visible');
      expect(find.text('Transcribing'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      for (final word in _transcript.split(' ')) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('analyzing_shimmer')),
            matching: find.text(word),
          ),
          findsOneWidget,
          reason: '"$word" shown during analysis',
        );
      }
      expect(
        find.byKey(const ValueKey('step_review')),
        findsNothing,
        reason: 'the full analysis is still running',
      );

      // Then the review opens with the same words.
      await settle(tester, 3000);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      expect(ai.previewCalls, 1);
      expect(ai.audioCalls, 1);
      await settle(tester, 1500);
    });

    testWidgets('a failed preview call never breaks the analysis', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply())..preview = null;
      final rec = FakeRecorder();
      await _pump(tester, ai, rec);
      await _tapMic(tester);
      await _ticks(tester, rec, -18, 8);
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await settle(tester, 2500);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      await settle(tester, 1500);
    });

    testWidgets('a fast analysis still holds the preview long enough to read', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply())
        ..previewDelay = const Duration(milliseconds: 100)
        ..replyDelay = const Duration(milliseconds: 150);
      final rec = FakeRecorder();
      await _pump(tester, ai, rec);
      await _tapMic(tester);
      await _ticks(tester, rec, -18, 8);
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('step_review')), findsNothing);
      await settle(tester, 2500);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      await settle(tester, 1500);
    });

    testWidgets('tapping Stop sends the recording immediately', (tester) async {
      final ai = FakeAudioAi(reply: _audioReply());
      final rec = FakeRecorder();
      await _pump(tester, ai, rec);
      await _tapMic(tester);
      await _ticks(tester, rec, -18, 8);
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await settle(tester, 1500);
      expect(rec.stops, 1);
      expect(ai.audioCalls, 1);
      expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
    });

    testWidgets(
      'no word is lost: even a long pause mid-sentence keeps recording',
      (tester) async {
        final ai = FakeAudioAi(reply: _audioReply());
        final rec = FakeRecorder();
        await _pump(tester, ai, rec);
        await _tapMic(tester);
        await _ticks(tester, rec, -52, 6);
        await _ticks(tester, rec, -18, 8);
        await _ticks(tester, rec, -52, 30); // 3 s thinking pause
        await _ticks(tester, rec, -18, 8); // keeps talking
        await _ticks(tester, rec, -52, 30);
        expect(rec.stops, 0);
        expect(rec.starts, 1);
        await _ticks(tester, rec, -52, 10);
        await settle(tester, 1500);
        expect(rec.stops, 1);
      },
    );

    testWidgets(
      'a clip with no amount shows a friendly error and stays on input',
      (tester) async {
        final ai = FakeAudioAi(
          reply: _audioReply(transcript: 'um hello there', items: const []),
        );
        final rec = FakeRecorder();
        await _pump(tester, ai, rec);
        await _tapMic(tester);
        await _speakThenSilence(tester, rec);
        await settle(tester, 1500);
        expect(find.byKey(const ValueKey('step_input')), findsOneWidget);
        expect(find.textContaining('could not find an amount'), findsOneWidget);
      },
    );

    testWidgets('a too-short recording is rejected without calling Gemini', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply());
      final rec = FakeRecorder()..length = const Duration(milliseconds: 300);
      await _pump(tester, ai, rec);
      await _tapMic(tester);
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await settle(tester, 800);
      expect(ai.audioCalls, 0);
      expect(find.textContaining('did not hear anything'), findsOneWidget);
    });

    testWidgets(
      'when Gemini fails online: a red banner with the reason, and Try again re-sends the SAME recording (no STT downgrade)',
      (tester) async {
        final ai = FakeAudioAi(reply: null);
        final rec = FakeRecorder();
        final stt = FakeSpeechEngine();
        await _pump(tester, ai, rec, stt: stt);
        await _tapMic(tester);
        await _speakThenSilence(tester, rec);
        await settle(tester, 1500);
        expect(find.byKey(const ValueKey('ai_failure_banner')), findsOneWidget);
        expect(find.textContaining('did not answer in time'), findsOneWidget);
        expect(find.textContaining('timeout: scripted'), findsOneWidget);
        expect(stt.listenCalls, 0, reason: 'online never downgrades to STT');
        expect(ai.audioCalls, 1);

        // Connection is back: the same clip is analyzed, nobody speaks again.
        ai.reply = _audioReply();
        await tester.tap(find.byKey(const ValueKey('retry_ai_button')));
        await settle(tester, 1800);
        expect(ai.audioCalls, 2);
        expect(ai.lastBytes, 4000);
        expect(rec.starts, 1, reason: 'no second recording');
        expect(stt.listenCalls, 0);
        expect(find.byKey(const ValueKey('step_review')), findsOneWidget);
      },
    );

    testWidgets(
      'the default dead-air timeout is 6 s: a 5 s thinking pause never ends the clip',
      (tester) async {
        final ai = FakeAudioAi(reply: _audioReply());
        final rec = FakeRecorder();
        await _pump(tester, ai, rec, audioSilence: const Duration(seconds: 6));
        await _tapMic(tester);
        await _ticks(tester, rec, -52, 6);
        await _ticks(tester, rec, -18, 8);
        await _ticks(tester, rec, -52, 50); // 5 s thinking pause
        expect(rec.stops, 0);
        await _ticks(tester, rec, -18, 8); // keeps talking: still one clip
        expect(rec.stops, 0);
        expect(rec.starts, 1);
        await _ticks(tester, rec, -52, 62); // finally 6 s of silence
        await settle(tester, 1500);
        expect(rec.stops, 1);
        expect(ai.audioCalls, 1);
      },
    );
  });

  group('Offline fallback (Airplane Mode)', () {
    testWidgets('offline: speech_to_text is used, no recording is started', (
      tester,
    ) async {
      final ai = FakeAudioAi(online: false, reply: _audioReply());
      final rec = FakeRecorder();
      final stt = FakeSpeechEngine();
      await _pump(tester, ai, rec, stt: stt);
      await _tapMic(tester);
      expect(rec.starts, 0);
      expect(stt.listenCalls, 1);
      stt.say('Eat ramen with Maya', isFinal: true);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('capture_text_field')))
            .controller!
            .text,
        'Eat ramen with Maya',
      );
      await settle(tester, 4500);
    });

    testWidgets('a denied microphone permission falls back to dictation', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply());
      final rec = FakeRecorder()..permission = false;
      final stt = FakeSpeechEngine();
      await _pump(tester, ai, rec, stt: stt);
      await _tapMic(tester);
      expect(rec.starts, 0);
      expect(stt.listenCalls, 1);
      await settle(tester, 4500);
    });

    testWidgets('enableAudioCapture: false always uses offline dictation', (
      tester,
    ) async {
      final ai = FakeAudioAi(reply: _audioReply());
      final stt = FakeSpeechEngine();
      await pumpPocko(
        tester,
        AiExpenseCaptureSheet(
          enableAudioCapture: false,
          speechEngineFactory: () => stt,
        ),
        size: const Size(390, 1100),
        ai: ai,
      );
      await _tapMic(tester);
      expect(stt.listenCalls, 1);
      await settle(tester, 4500);
    });
  });

  group('Native, Web and platform wiring for audio', () {
    String read(String path) => File(path).readAsStringSync();

    test('Android passes inline audio to the cloud model chain', () {
      final kt = read(
        'android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt',
      );
      expect(kt, contains('"audioBase64"'));
      expect(kt, contains('"audioMimeType"'));
      expect(kt, contains('inlineData(audioBytes, audioMimeType)'));
      expect(kt, contains('InferenceMode.ONLY_IN_CLOUD'));
      expect(kt, contains('AUDIO_ATTEMPT_TIMEOUT_MS'));
      expect(kt, contains('gemini-3.1-flash-lite'));
      expect(kt, contains('gemini-3.8-flash'));
    });

    test('iOS passes inline audio to the Gemini cloud model', () {
      final swift = read('ios/Runner/HybridAiPlugin.swift');
      expect(swift, contains('args["audioBase64"]'));
      expect(
        swift,
        contains('InlineDataPart(data: audio, mimeType: audioMimeType)'),
      );
      expect(swift, contains('audioAttemptTimeout'));
      expect(swift, contains('gemini-3.1-flash-lite'));
    });

    test('Web bridge sends audioBase64 as inline data, cloud only', () {
      final js = read('web/firebase_ai_web.js');
      expect(js, contains('audioBase64'));
      expect(js, contains('inlineData'));
      expect(js, contains('AUDIO_ATTEMPT_TIMEOUT_MS'));
      expect(js, contains('audio/wav'));
      final bridge = read(
        'lib/services/hybrid_ai/web_hybrid_ai_bridge_web.dart',
      );
      expect(bridge, contains("options['audioBase64']"));
    });

    test('offline dictation is pinned to English dictation mode', () {
      final engine = read('lib/services/speech/speech_engine.dart');
      // English only, but a variant the recognizer really offers (en_US first).
      expect(engine, contains("== 'en_us'"));
      expect(engine, contains("startsWith('en_')"));
      expect(engine, contains('localeId: locale'));
      expect(engine, contains('ListenMode.dictation'));
    });

    test('the microphone permission is declared on every platform', () {
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android.permission.RECORD_AUDIO'),
      );
      expect(
        read('ios/Runner/Info.plist'),
        contains('NSMicrophoneUsageDescription'),
      );
      expect(read('pubspec.yaml'), contains('record:'));
    });
  });
}
