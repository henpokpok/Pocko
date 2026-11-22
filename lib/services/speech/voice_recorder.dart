import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// One finished microphone recording, ready to be sent to Gemini as inline
/// audio.
class RecordedAudio {
  final Uint8List bytes;

  /// `audio/mp4` (AAC in an M4A container) on Android / iOS, `audio/wav` on Web.
  final String mimeType;
  final Duration duration;

  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.duration,
  });
}

/// The slice of a microphone recorder the capture sheet needs. The production
/// implementation wraps the `record` package; tests inject a scripted fake.
abstract class VoiceRecorder {
  /// Asks for (or confirms) the microphone permission.
  Future<bool> hasPermission();

  /// Starts **one uninterrupted recording** (no recognizer restarts, so no
  /// dropped words) and reports the input level in dBFS (about -60 silence to
  /// 0 clipping) every ~100 ms through [onAmplitude].
  Future<void> start({required void Function(double db) onAmplitude});

  /// Stops and returns the audio, or `null` when nothing usable was captured.
  Future<RecordedAudio?> stop();

  /// Stops and throws the audio away.
  Future<void> cancel();

  Future<void> dispose();
}

/// `record`-package recorder: AAC-LC / M4A at 16 kHz mono on Android and iOS
/// (small, speech-grade, `audio/mp4`), 16-bit PCM wrapped as `audio/wav` on Web.
class PlatformVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<Uint8List>? _pcmSub;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  String? _path;
  DateTime? _startedAt;

  static const int _sampleRate = 16000;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start({required void Function(double db) onAmplitude}) async {
    _startedAt = DateTime.now();
    _pcm.clear();
    if (kIsWeb) {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _pcmSub = stream.listen(_pcm.add);
    } else {
      _path =
          '${Directory.systemTemp.path}/pocko_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          sampleRate: _sampleRate,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: _path!,
      );
    }
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) => onAmplitude(a.current));
  }

  @override
  Future<RecordedAudio?> stop() async {
    final started = _startedAt;
    await _ampSub?.cancel();
    _ampSub = null;
    final String? out = await _recorder.stop();
    await _pcmSub?.cancel();
    _pcmSub = null;
    final duration = started == null
        ? Duration.zero
        : DateTime.now().difference(started);

    if (kIsWeb) {
      final pcm = _pcm.takeBytes();
      if (pcm.isEmpty) return null;
      return RecordedAudio(
        bytes: pcmToWav(pcm, sampleRate: _sampleRate),
        mimeType: 'audio/wav',
        duration: duration,
      );
    }
    final path = out ?? _path;
    if (path == null) return null;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      unawaited(file.delete().catchError((_) => file));
      if (bytes.isEmpty) return null;
      return RecordedAudio(
        bytes: bytes,
        mimeType: 'audio/mp4',
        duration: duration,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    await _ampSub?.cancel();
    _ampSub = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    _pcm.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }

  /// Wraps raw 16-bit little-endian mono PCM in a 44-byte WAV header.
  static Uint8List pcmToWav(Uint8List pcm, {required int sampleRate}) {
    const channels = 1;
    const bits = 16;
    final byteRate = sampleRate * channels * bits ~/ 8;
    final header = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * bits ~/ 8, Endian.little);
    header.setUint16(34, bits, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    final out = Uint8List(44 + pcm.length);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, out.length, pcm);
    return out;
  }
}

/// Decides, from a stream of microphone levels, when the user has finished
/// speaking: once speech has started and the level stays below the silence
/// threshold for [silence] (3.5 s) the recording should end.
///
/// The threshold adapts to the room: the first [calibrationSamples] readings
/// (about half a second, before anyone speaks) set the noise floor, and speech
/// is anything [margin] dB above it, clamped to a sane range.
class SilenceDetector {
  final Duration silence;
  final int calibrationSamples;
  final double margin;
  final double minThresholdDb;
  final double maxThresholdDb;

  SilenceDetector({
    this.silence = const Duration(milliseconds: 3500),
    this.calibrationSamples = 5,
    this.margin = 10,
    this.minThresholdDb = -45,
    this.maxThresholdDb = -25,
  });

  final List<double> _floorSamples = [];
  double? _threshold;
  bool _speechStarted = false;
  Duration? _lastLoudAt;

  /// Whether the user has said something yet.
  bool get speechStarted => _speechStarted;

  /// The level (dBFS) above which a reading counts as speech.
  double? get thresholdDb => _threshold;

  /// Feeds one reading taken [at] a time since the recording started. Returns
  /// `true` when the dead-air timeout has elapsed after speech.
  bool update(double db, Duration at) {
    if (_threshold == null) {
      _floorSamples.add(db);
      if (_floorSamples.length < calibrationSamples) return false;
      final floor =
          _floorSamples.reduce((a, b) => a + b) / _floorSamples.length;
      _threshold = (floor + margin).clamp(minThresholdDb, maxThresholdDb);
    }
    if (db > _threshold!) {
      _speechStarted = true;
      _lastLoudAt = at;
      return false;
    }
    final last = _lastLoudAt;
    return _speechStarted && last != null && at - last >= silence;
  }

  void reset() {
    _floorSamples.clear();
    _threshold = null;
    _speechStarted = false;
    _lastLoudAt = null;
  }
}
