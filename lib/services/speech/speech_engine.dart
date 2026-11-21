import 'dart:async';

import 'package:flutter/foundation.dart';
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
  String? _localeId;
  bool _localeResolved = false;

  // The default recognizer (Speech Services by Google) needs its own offline
  // pack: the Samsung keyboard's "Voice input" download is a different engine.
  // When it fails with "language unavailable" / "network", try the phone's
  // on-device recognizer once, silently, before telling the user.
  bool _onDevice = false;
  bool _triedOnDevice = false;
  SpeechResultCallback? _lastResult;
  void Function(double level)? _lastLevel;

  /// English on purpose (a phone set to Thai would match English speech
  /// against the wrong phonemes), but only a variant this recognizer actually
  /// offers: `en_US`, else any `en_*`, else the system default (`null`).
  Future<String?> _pickLocale() async {
    if (_localeResolved) return _localeId;
    _localeResolved = true;
    try {
      final locales = await _speech.locales();
      String norm(String id) => id.replaceAll('-', '_').toLowerCase();
      for (final l in locales) {
        if (norm(l.localeId) == 'en_us') return _localeId = l.localeId;
      }
      for (final l in locales) {
        if (norm(l.localeId).startsWith('en_')) return _localeId = l.localeId;
      }
    } catch (_) {}
    return _localeId = null;
  }

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(String status) onStatus,
  }) {
    return _speech.initialize(
      onError: (e) {
        final m = e.errorMsg.toLowerCase();
        final retryable =
            m.contains('language_unavailable') ||
            m.contains('language_not_supported') ||
            m.contains('network') ||
            m.contains('server');
        final result = _lastResult;
        final level = _lastLevel;
        if (retryable && !_triedOnDevice && result != null && level != null) {
          _triedOnDevice = true;
          _onDevice = true;
          debugPrint(
            '[STT] ${e.errorMsg}: retrying with the on-device recognizer',
          );
          unawaited(
            listen(onResult: result, onSoundLevel: level).catchError((_) {}),
          );
          return;
        }
        onError(e.errorMsg, e.permanent);
      },
      onStatus: onStatus,
    );
  }

  @override
  Future<void> listen({
    required SpeechResultCallback onResult,
    required void Function(double level) onSoundLevel,
  }) async {
    _lastResult = onResult;
    _lastLevel = onSoundLevel;
    final locale = await _pickLocale();
    return _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onSoundLevel,
      listenOptions: stt.SpeechListenOptions(
        localeId: locale,
        onDevice: _onDevice,
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
