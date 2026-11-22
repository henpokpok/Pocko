import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/services/speech/dictation_buffer.dart';
import 'package:travmate/services/speech/speech_engine.dart';

import 'test_helpers.dart';

/// A scripted recognizer: the test decides what each callback delivers.
class FakeSpeechEngine implements SpeechEngine {
  void Function(String message, bool permanent)? _onError;
  void Function(String status)? _onStatus;
  SpeechResultCallback? _onResult;
  int listenCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(String status) onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;
    return true;
  }

  @override
  Future<void> listen({
    required SpeechResultCallback onResult,
    required void Function(double level) onSoundLevel,
  }) async {
    listenCalls++;
    _onResult = onResult;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async {}

  void say(String words, {bool isFinal = false}) =>
      _onResult?.call(words, isFinal);

  /// What Android does after a short pause: the session ends.
  void sessionEnds() {
    _onStatus?.call('done');
    _onStatus?.call('notListening');
  }

  void error(String message, {bool permanent = false}) =>
      _onError?.call(message, permanent);
}

Future<FakeSpeechEngine> _pump(
  WidgetTester tester, {
  Duration silence = const Duration(milliseconds: 3500),
}) async {
  final engine = FakeSpeechEngine();
  await pumpPocko(
    tester,
    AiExpenseCaptureSheet(
      speechEngineFactory: () => engine,
      enableAudioCapture: false,
      silenceTimeout: silence,
    ),
    size: const Size(390, 1100),
  );
  return engine;
}

Future<void> _startMic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic_rounded).last);
  await settle(tester, 300);
}

String _text(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('capture_text_field')))
    .controller!
    .text;

/// Still collecting words: the input step is up and no analysis has begun.
bool _stillInput(WidgetTester tester) =>
    find.byKey(const ValueKey('step_input')).evaluate().isNotEmpty &&
    find.byKey(const ValueKey('analyzing_text')).evaluate().isEmpty;

void main() {
  group('DictationBuffer', () {
    test('Android: a second segment appends instead of overwriting', () {
      final b = DictationBuffer();
      expect(
        b.onResult('Eat ramen with Maya', isFinal: true),
        'Eat ramen with Maya',
      );
      expect(b.committed, 'Eat ramen with Maya');
      expect(
        b.onResult('mine 1200 Maya 1800 yen', isFinal: true),
        'Eat ramen with Maya mine 1200 Maya 1800 yen',
      );
    });

    test(
      'partials of the live segment replace each other, never the prefix',
      () {
        final b = DictationBuffer();
        b.onResult('Eat ramen', isFinal: true);
        expect(b.onResult('mine', isFinal: false), 'Eat ramen mine');
        expect(b.onResult('mine 12', isFinal: false), 'Eat ramen mine 12');
        expect(b.onResult('mine 1200', isFinal: false), 'Eat ramen mine 1200');
        expect(b.activeSegment, 'mine 1200');
        expect(b.committed, 'Eat ramen');
      },
    );

    test('Web: a cumulative transcript never duplicates the prefix', () {
      final b = DictationBuffer();
      expect(b.onResult('Eat ramen', isFinal: true), 'Eat ramen');
      expect(b.onResult('Eat ramen with', isFinal: false), 'Eat ramen with');
      expect(
        b.onResult('Eat ramen with Maya', isFinal: true),
        'Eat ramen with Maya',
      );
      expect(
        b.onResult('eat ramen with maya mine 1200', isFinal: true),
        'eat ramen with maya mine 1200',
        reason: 'case-insensitive prefix, no duplication',
      );
    });

    test('a word that merely starts with the prefix is not cumulative', () {
      final b = DictationBuffer()..onResult('coffee', isFinal: true);
      expect(
        b.onResult('coffeeshop 300', isFinal: true),
        'coffee coffeeshop 300',
      );
    });

    test('commitActive keeps the words of an ended session', () {
      final b = DictationBuffer()..onResult('Eat ramen', isFinal: false);
      b.commitActive();
      expect(b.onResult('with Maya', isFinal: true), 'Eat ramen with Maya');
    });

    test('whitespace is normalized to single spaces', () {
      final b = DictationBuffer()..onResult('  Eat   ramen ', isFinal: true);
      expect(b.onResult(' with  Maya ', isFinal: true), 'Eat ramen with Maya');
    });

    test('manual edits and clear reset the committed transcript', () {
      final b = DictationBuffer()..onResult('Eat ramen', isFinal: true);
      b.syncManual('Lunch 500');
      expect(b.onResult('mine 200', isFinal: true), 'Lunch 500 mine 200');
      b.clear();
      expect(b.isEmpty, isTrue);
      expect(b.onResult('Taxi 900', isFinal: true), 'Taxi 900');
    });

    test('empty results never wipe the transcript', () {
      final b = DictationBuffer()..onResult('Eat ramen', isFinal: true);
      expect(b.onResult('', isFinal: true), 'Eat ramen');
    });
  });

  group('DictationBuffer high-water mark (no finalResult from Android)', () {
    test('an empty partial never wipes the words already heard', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya', isFinal: false);
      expect(b.onResult('', isFinal: false), 'Eat ramen with Maya');
      expect(b.activeSegment, 'Eat ramen with Maya');
    });

    test('a confidence dip to a shorter truncation keeps the longer words', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya mine 1200', isFinal: false);
      expect(
        b.onResult('Eat ramen', isFinal: false),
        'Eat ramen with Maya mine 1200',
      );
      expect(
        b.onResult('Eat ramen with Maya mine 1200 yen', isFinal: false),
        'Eat ramen with Maya mine 1200 yen',
        reason: 'growth is accepted again',
      );
    });

    test('done without finalResult commits the longest partial', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya', isFinal: false);
      b.onResult('Eat', isFinal: false); // trailing shorter partial
      b.commitActive(); // onStatus("done") / ("notListening")
      expect(b.committed, 'Eat ramen with Maya');
      expect(b.activeSegment, '');
      expect(
        b.onResult('mine 1200 Maya 1800 yen', isFinal: false),
        'Eat ramen with Maya mine 1200 Maya 1800 yen',
      );
    });

    test('an empty final still commits what was heard', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya', isFinal: false);
      expect(b.onResult('', isFinal: true), 'Eat ramen with Maya');
      expect(b.committed, 'Eat ramen with Maya');
    });

    test('a shorter final that truncates the partial does not lose words', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya', isFinal: false);
      expect(b.onResult('Eat ramen', isFinal: true), 'Eat ramen with Maya');
      expect(b.committed, 'Eat ramen with Maya');
    });

    test('a revision of similar length replaces the hypothesis', () {
      final b = DictationBuffer();
      b.onResult('eat ram in with Mia', isFinal: false);
      expect(
        b.onResult('eat ramen with Maya', isFinal: false),
        'eat ramen with Maya',
      );
    });

    test('a fresh utterance without a final keeps the earlier one', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya and Liam', isFinal: false);
      expect(
        b.onResult('mine', isFinal: false),
        'Eat ramen with Maya and Liam mine',
      );
      expect(
        b.onResult('mine 1200 yen', isFinal: false),
        'Eat ramen with Maya and Liam mine 1200 yen',
      );
    });

    test('a late echo of the committed segment is not appended twice', () {
      final b = DictationBuffer();
      b.onResult('Eat ramen with Maya', isFinal: true);
      expect(b.onResult('Eat ramen', isFinal: false), 'Eat ramen with Maya');
      expect(
        b.onResult('Eat ramen with Maya', isFinal: true),
        'Eat ramen with Maya',
        reason: 'the same final delivered twice',
      );
    });
  });

  group('Continuous voice capture (widget)', () {
    testWidgets(
      'speech, 1.5 s pause, more speech: every word is kept (Android segments)',
      (tester) async {
        final engine = await _pump(tester);
        await _startMic(tester);
        expect(engine.listenCalls, 1);

        engine.say('Eat ramen with Maya');
        engine.say('Eat ramen with Maya', isFinal: true);
        await tester.pump();
        engine.sessionEnds(); // Android stops listening after the pause
        await settle(tester, 300);
        expect(engine.listenCalls, 2, reason: 'listening restarted by itself');
        expect(_text(tester), 'Eat ramen with Maya');

        await settle(tester, 1500); // thinking...
        expect(_stillInput(tester), isTrue, reason: '1.5 s is not dead air');

        engine.say('mine 1200 Maya 1800 yen');
        await tester.pump();
        expect(
          _text(tester),
          'Eat ramen with Maya mine 1200 Maya 1800 yen',
          reason: 'the live segment appends to the committed words',
        );
        engine.say('mine 1200 Maya 1800 yen', isFinal: true);
        await tester.pump();
        expect(_text(tester), 'Eat ramen with Maya mine 1200 Maya 1800 yen');
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('capture_text_field')),
              )
              .controller!
              .selection
              .baseOffset,
          _text(tester).length,
          reason: 'cursor stays at the end',
        );
        await settle(tester, 4500);
      },
    );

    testWidgets('a dip + "done" with no final keeps every word', (
      tester,
    ) async {
      final engine = await _pump(tester);
      await _startMic(tester);
      engine.say('Eat ramen with Maya');
      engine.say(''); // confidence dip
      engine.say('Eat'); // trailing shorter partial
      await tester.pump();
      expect(_text(tester), 'Eat ramen with Maya');
      engine.sessionEnds(); // no finalResult was ever sent
      await settle(tester, 300);
      engine.say('mine 1200 Maya 1800 yen');
      await tester.pump();
      expect(_text(tester), 'Eat ramen with Maya mine 1200 Maya 1800 yen');
      await settle(tester, 4500);
    });

    testWidgets('three breaths in a row keep appending', (tester) async {
      final engine = await _pump(tester);
      await _startMic(tester);
      for (final part in ['Ramen 1200', 'coffee 400', 'taxi 900']) {
        engine.say(part, isFinal: true);
        await tester.pump();
        engine.sessionEnds();
        await settle(tester, 1000);
      }
      expect(_text(tester), 'Ramen 1200 coffee 400 taxi 900');
      expect(engine.listenCalls, 4);
      await settle(tester, 4500);
    });

    testWidgets('Web cumulative callbacks never duplicate words', (
      tester,
    ) async {
      final engine = await _pump(tester);
      await _startMic(tester);
      engine.say('Eat ramen', isFinal: true);
      await tester.pump();
      engine.sessionEnds();
      await settle(tester, 300);
      engine.say('Eat ramen with');
      engine.say('Eat ramen with Maya', isFinal: true);
      await tester.pump();
      expect(_text(tester), 'Eat ramen with Maya');
      engine.sessionEnds();
      await settle(tester, 300);
      engine.say('Eat ramen with Maya mine 1200', isFinal: true);
      await tester.pump();
      expect(_text(tester), 'Eat ramen with Maya mine 1200');
      await settle(tester, 4500);
    });

    testWidgets(
      'analysis starts only after 3.5 s of true silence following the last words',
      (tester) async {
        final engine = await _pump(tester);
        await _startMic(tester);
        engine.say('Eat ramen with Maya', isFinal: true);
        await tester.pump();
        engine.sessionEnds();
        await settle(tester, 3000);
        expect(_stillInput(tester), isTrue);

        // New words at t≈3.3 s reset the dead-air timer.
        engine.say('mine 1200 Maya 1800 yen', isFinal: true);
        await tester.pump();
        await settle(tester, 3000);
        expect(
          _stillInput(tester),
          isTrue,
          reason: 'only 3 s since the last word',
        );
        await settle(tester, 700);
        expect(
          _stillInput(tester),
          isFalse,
          reason: '3.5 s of silence: analyzed',
        );
        await settle(tester, 1500);
      },
    );

    testWidgets('repeated partials of the same words do not reset the timer', (
      tester,
    ) async {
      final engine = await _pump(tester);
      await _startMic(tester);
      engine.say('Eat ramen 1200');
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await settle(tester, 1000);
        engine.say('Eat ramen 1200'); // identical echo
      }
      await settle(tester, 300);
      expect(_stillInput(tester), isFalse);
    });

    testWidgets('tapping Stop analyzes the accumulated text at once', (
      tester,
    ) async {
      final engine = await _pump(tester);
      await _startMic(tester);
      engine.say('Eat ramen 1200', isFinal: true);
      await tester.pump();
      engine.sessionEnds();
      await settle(tester, 300);
      engine.say('with Maya');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
      await settle(tester, 700);
      expect(_stillInput(tester), isFalse);
      expect(engine.stopCalls, greaterThanOrEqualTo(1));
    });

    testWidgets(
      '"no match" while quiet restarts listening; a permanent error stops it',
      (tester) async {
        final engine = await _pump(tester);
        await _startMic(tester);
        engine.say('Ramen 1200', isFinal: true);
        await tester.pump();
        engine.error('error_no_match');
        await settle(tester, 300);
        expect(engine.listenCalls, 2);
        expect(
          find.byIcon(Icons.stop_rounded),
          findsWidgets,
          reason: 'still listening',
        );
        expect(_text(tester), 'Ramen 1200');

        engine.error('error_permission', permanent: true);
        await settle(tester, 300);
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
        expect(_text(tester), 'Ramen 1200');
      },
    );
  });

  group('Manual edit and Clear', () {
    testWidgets(
      'Clear is hidden when empty and wipes the text and the transcript',
      (tester) async {
        final engine = await _pump(tester);
        expect(find.byKey(const ValueKey('clear_transcript')), findsNothing);
        await _startMic(tester);
        engine.say('Eat ramen with Maya', isFinal: true);
        await settle(tester); // the chip grows in
        expect(find.byKey(const ValueKey('clear_transcript')), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('clear_transcript')),
        );
        await tester.tap(find.byKey(const ValueKey('clear_transcript')));
        await settle(tester, 400);
        expect(_text(tester), '');
        expect(find.byKey(const ValueKey('clear_transcript')), findsNothing);

        // Starting over: even a cumulative echo of the old words cannot return.
        engine.say('Taxi 900', isFinal: true);
        await tester.pump();
        expect(_text(tester), 'Taxi 900');
        await settle(tester, 4500);
      },
    );

    testWidgets('typed text is kept and voice appends after it', (
      tester,
    ) async {
      final engine = await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('capture_text_field')),
        'Lunch 500',
      );
      await tester.pump();
      await _startMic(tester);
      engine.say('mine 200', isFinal: true);
      await tester.pump();
      expect(_text(tester), 'Lunch 500 mine 200');
      await settle(tester, 4500);
    });
  });

  group('Mic ripple never moves the layout', () {
    testWidgets('the expanding ring paints outside a fixed orb box', (
      tester,
    ) async {
      final engine = await _pump(tester);
      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final orbBefore = rect('mic_orb');
      final areaBefore = rect('input_area');
      final modesBefore = rect('mode_row');

      await _startMic(tester);
      expect(find.byKey(const ValueKey('mic_ripple')), findsOneWidget);

      // Sample the ring across its whole growth cycle, loud and quiet.
      var maxRing = 0.0;
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        maxRing =
            maxRing <
                tester.getSize(find.byKey(const ValueKey('mic_ripple'))).width
            ? tester.getSize(find.byKey(const ValueKey('mic_ripple'))).width
            : maxRing;
        expect(
          rect('mic_orb'),
          orbBefore,
          reason: 'orb box is fixed (tick $i)',
        );
        expect(
          rect('input_area'),
          areaBefore,
          reason: 'siblings stay put (tick $i)',
        );
        expect(
          rect('mode_row'),
          modesBefore,
          reason: 'mode row stays put (tick $i)',
        );
      }
      expect(
        maxRing,
        greaterThan(orbBefore.width),
        reason: 'the ring really does grow beyond the orb',
      );
      engine.say('Ramen 1200', isFinal: true);
      await settle(tester);
      expect(rect('mic_orb').size, orbBefore.size);
      await settle(tester, 4500);
    });
  });
}
