import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Called with the recognizer's words and whether the segment is final.
typedef SpeechResultCallback = void Function(String words, bool isFinal);

/// The slice of a speech recognizer the capture sheet needs. The production
/// implementation wraps `speech_to_text`; tests inject a scripted fake to
/// simulate multi-segment dictation without a microphone.
abstract class SpeechEngine {
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(String status) onStatus,
  });

  /// Starts one listen session (may end by itself after a pause).
  Future<void> listen({
    required SpeechResultCallback onResult,
    required void Function(double level) onSoundLevel,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// `speech_to_text` (Android SpeechRecognizer, iOS SFSpeechRecognizer, Chrome).
class PlatformSpeechEngine implements SpeechEngine {
  final stt.SpeechToText _speech = stt.SpeechToText();

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(String status) onStatus,
  }) {
    return _speech.initialize(
      onError: (e) => onError(e.errorMsg, e.permanent),
      onStatus: onStatus,
    );
  }

  @override
  Future<void> listen({
    required SpeechResultCallback onResult,
    required void Function(double level) onSoundLevel,
  }) {
    return _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onSoundLevel,
      // English on purpose: phones set to Thai (or any other locale) would
      // otherwise match English speech against the wrong phonemes.
      listenOptions: stt.SpeechListenOptions(
        localeId: 'en_US',
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 45),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
