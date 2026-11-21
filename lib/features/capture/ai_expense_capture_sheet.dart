import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/speech/dictation_buffer.dart';
import '../../services/speech/speech_engine.dart';
import '../../services/speech/voice_recorder.dart';

import '../../core/enums/expense_category.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_selector.dart';
import '../../core/widgets/pocko_toast.dart';
import '../../core/widgets/tactile.dart';
import '../../core/widgets/telemetry_pill.dart';
import '../../models/expense_item.dart';
import '../../models/raw_prompt_note.dart';
import '../../services/hybrid_ai/parsed_expense_draft.dart';
import '../../services/hybrid_ai/ai_unavailable.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';
import '../../services/hybrid_ai/spoken_numbers.dart';
import '../trip/trip_controller.dart';
import 'expense_preview_card.dart';
import 'logged_celebration.dart';
import 'member_pill.dart';
import 'selected_names.dart';
import 'transcript_tokens.dart';

enum CaptureStep { input, processing, review, logged }

/// How the user prefers to enter text on the input step.
enum CaptureInputMode { voice, type }

class _EditTarget {
  final int index;
  final bool isAmount;
  const _EditTarget(this.index, this.isAmount);
}

/// "Light Intelligence" capture overlay.
///
/// Hosted by `PockoMainShell`, which dims the live page with a light scrim and
/// scales it back (no blur, so it stays at full frame rate) while a giant hero
/// Pocko springs in. Speak (auto-analyzed after a natural pause) or type: the
/// text glows with a moving green gradient, Pocko juggles while the words
/// shimmer, and the transcript returns with tappable title / price / category
/// pills. A permanent group-member strip lets you tag people up front; Pocko
/// auto-selects the people it detected. "Confirm" analyzes, "Confirm" again saves.
class AiExpenseCaptureSheet extends ConsumerStatefulWidget {
  /// Set to `false` to skip the platform speech engine and always use the demo
  /// dictation (headless tests, kiosk demos).
  final bool enableSpeechRecognition;

  /// Silence after the last spoken word that triggers the analysis (offline
  /// dictation).
  final Duration silenceTimeout;

  /// Dead air that ends a **recording** for Gemini. Long on purpose: a 2 to 5
  /// second thinking pause never ends (or resets) the one continuous clip.
  final Duration audioSilenceTimeout;

  /// Called when the overlay wants to go away (close button, after "Logged").
  /// Defaults to popping the current route when the sheet is shown standalone.
  final VoidCallback? onClose;

  /// Called by the subtle "Manual Expense" action. The host closes the overlay
  /// and opens the standard Add Expense sheet.
  final VoidCallback? onManualExpense;

  /// Replaces the platform speech engine (tests script multi-segment dictation).
  final SpeechEngine Function()? speechEngineFactory;

  /// Voice goes through **Gemini multimodal audio** (one uninterrupted
  /// recording, transcribed and parsed in a single call) whenever a live
  /// runtime is reachable and the device is online. `false` forces the
  /// offline `speech_to_text` dictation path.
  final bool enableAudioCapture;

  /// Replaces the platform microphone recorder (tests script recordings).
  final VoiceRecorder Function()? voiceRecorderFactory;

  const AiExpenseCaptureSheet({
    super.key,
    this.speechEngineFactory,
    this.enableAudioCapture = true,
    this.voiceRecorderFactory,
    this.enableSpeechRecognition = true,
    this.silenceTimeout = const Duration(milliseconds: 3500),
    this.audioSilenceTimeout = const Duration(seconds: 6),
    this.onClose,
    this.onManualExpense,
  });

  @override
  ConsumerState<AiExpenseCaptureSheet> createState() =>
      _AiExpenseCaptureSheetState();
}

class _AiExpenseCaptureSheetState extends ConsumerState<AiExpenseCaptureSheet>
    with TickerProviderStateMixin {
  // Shared geometry of every highlighted pill in the transcript (title, price
  // and member names) so they read as one family.
  static const double _pillFontSize = 26;
  static const double _pillRadius = 16;
  static const double _pillBorderWidth = 2;
  static const EdgeInsets _pillMargin = EdgeInsets.symmetric(
    horizontal: 2,
    vertical: 3,
  );
  static const EdgeInsets _pillPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 4,
  );
  static const Color _memberPillTint = Color(0xFFE4DBFF);
  static const Color _memberPillBorder = Color(0xFF8B5CF6);

  CaptureStep _step = CaptureStep.input;
  CaptureInputMode _mode = CaptureInputMode.voice;

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _isListening = false;
  String? _inputError;

  SpeechEngine? _speech;
  bool? _speechReady;

  /// Everything said so far: finalized segments + the live one. Never lets a
  /// pause overwrite earlier words (see [DictationBuffer]).
  final DictationBuffer _dictation = DictationBuffer();

  // --- Gemini audio capture (one uninterrupted recording) --------------------
  VoiceRecorder? _recorder;
  bool _audioActive = false;
  bool _processingAudio = false;

  /// The recording that just failed to reach Gemini, kept so "Try again"
  /// re-sends the same audio instead of asking the user to speak again.
  RecordedAudio? _pendingAudio;

  /// Why the last analysis failed (drives the pinned red banner).
  AiUnavailableException? _aiFailure;

  /// Whether the text being analyzed came from offline dictation.
  bool _textFromSpeech = false;
  SilenceDetector _detector = SilenceDetector();
  int _ampTicks = 0;
  Timer? _maxRecordTimer;
  Timer? _revealTimer;
  DateTime? _previewShownAt;
  static const Duration _maxRecording = Duration(seconds: 60);
  static const Duration _minRecording = Duration(milliseconds: 800);
  static const Duration _previewHold = Duration(milliseconds: 900);
  bool _applyingVoice = false;
  bool _restartPending = false;
  Timer? _dictationTimer;
  Timer? _silenceTimer;
  final ValueNotifier<double> _voiceLevel = ValueNotifier<double>(0);

  late final AnimationController _zoom;
  late final AnimationController _aura;
  late final AnimationController _ripple;
  late final AnimationController _sweep;

  /// Members tagged on the strip before analysis (empty = let Pocko decide).
  final Set<String> _preselected = <String>{};

  HybridAiResult? _aiResult;
  List<ExpenseItem> _items = [];

  /// The AI's typed reading of each item (unit amount, each / quantity /
  /// percent), parallel to [_items]. `null` once the user typed a price by
  /// hand, which detaches the item from the live per-person maths.
  List<ParsedExpenseDraft?> _drafts = [];

  /// The per-person prices the AI read for each itemized item (by member id),
  /// so toggling a friend off and on restores their dish.
  final Map<int, Map<String, double>> _originalCustom = {};

  /// The exact words the user spoke or typed (the audit trail).
  String _rawPrompt = '';
  TokenizeResult _tokens = const TokenizeResult([], {}, {});
  int _focused = 0;
  _EditTarget? _editing;
  final GlobalKey _editorKey = GlobalKey();
  final TextEditingController _editController = TextEditingController();
  int _runToken = 0;

  /// Text of the celebratory pill: "✓ Logged ¥8,000 • Ramen".
  String _loggedLabel = '';

  @override
  void initState() {
    super.initState();
    // Pocko springs in from 0.55 -> 1.0 while the scrim fades in.
    _zoom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();
    _aura = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Drives the moving green gradient and the analyzing shimmer.
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // A manual edit or clear becomes the new committed transcript.
    _text.addListener(() {
      if (!_applyingVoice) _dictation.syncManual(_text.text);
    });

    _focus.addListener(() {
      if (_focus.hasFocus && mounted && _mode != CaptureInputMode.type) {
        if (_isListening) _stopListening();
        setState(() => _mode = CaptureInputMode.type);
      }
    });
  }

  @override
  void dispose() {
    _runToken++;
    _dictationTimer?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _revealTimer?.cancel();
    final recorder = _recorder;
    if (recorder != null) unawaited(recorder.dispose());
    _zoom.dispose();
    _aura.dispose();
    _ripple.dispose();
    _sweep.dispose();
    try {
      _speech?.cancel();
    } catch (_) {}
    _voiceLevel.dispose();
    _focus.dispose();
    _text.dispose();
    _editController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Voice
  // ---------------------------------------------------------------------------

  Future<bool> _ensureSpeech() async {
    if (_speechReady != null) return _speechReady!;
    if (!widget.enableSpeechRecognition) return _speechReady = false;
    try {
      _speech = widget.speechEngineFactory?.call() ?? PlatformSpeechEngine();
      _speechReady = await _speech!
          .initialize(onError: _onSpeechError, onStatus: _onSpeechStatus)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } catch (e) {
      debugPrint('[STT unavailable → demo dictation]: $e');
      _speechReady = false;
    }
    return _speechReady!;
  }

  void _onSpeechError(String message, bool permanent) {
    debugPrint('[STT Error]: $message');
    if (!mounted || !_isListening) return;
    final quiet =
        message.contains('no_match') || message.contains('speech_timeout');
    // "Heard nothing" is just a pause: keep listening until the dead-air
    // timer fires. Anything else (permission, busy engine) stops the mic.
    if (quiet && !permanent) {
      _onSegmentEnded();
    } else {
      _stopListening();
    }
  }

  void _onSpeechStatus(String status) {
    if (status != 'done' && status != 'notListening') return;
    if (!mounted || !_isListening || _step != CaptureStep.input) return;
    _onSegmentEnded();
  }

  /// The recognizer ended a segment (Android stops after ~1 s of silence even
  /// with a longer `pauseFor`). Keep its words and, while the dead-air timer
  /// has not fired, listen again so the user can pause and keep talking.
  void _onSegmentEnded() {
    _dictation.commitActive();
    _restartListening();
  }

  Future<void> _restartListening() async {
    if (_restartPending) return;
    _restartPending = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || !_isListening || _step != CaptureStep.input) return;
      await _listenSession();
    } catch (e) {
      debugPrint('[STT restart failed → analyze what we have]: $e');
      if (mounted && _isListening) _autoAnalyze();
    } finally {
      _restartPending = false;
    }
  }

  Future<void> _listenSession() {
    return _speech!.listen(
      onResult: _onSpeechResult,
      onSoundLevel: (level) {
        final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
        _voiceLevel.value = _voiceLevel.value * 0.6 + normalized * 0.4;
      },
    );
  }

  /// One recognizer callback: append to (never overwrite) the transcript and
  /// restart the dead-air timer only when the text actually changed.
  void _onSpeechResult(String words, bool isFinal) {
    if (!mounted || !_isListening) return;
    final before = _text.text;
    final full = _dictation.onResult(words, isFinal: isFinal);
    if (full == before) return;
    setState(() => _setTranscript(full));
    _armSilenceTimer();
  }

  /// Writes [full] into the text box with the cursor at the end, without
  /// treating it as a manual edit.
  void _setTranscript(String full) {
    _applyingVoice = true;
    _text.value = TextEditingValue(
      text: full,
      selection: TextSelection.collapsed(offset: full.length),
    );
    _applyingVoice = false;
  }

  /// 1-tap "start over": clears the box and the committed transcript.
  void _clearTranscript() {
    _dictation.clear();
    setState(() {
      _inputError = null;
      _aiFailure = null;
      _pendingAudio = null;
      _setTranscript('');
    });
    if (_isListening) _armSilenceTimer();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      // Tapping Stop analyzes straight away when there is something to parse.
      _autoAnalyze();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    _focus.unfocus();
    // Words already in the box (typed or from an earlier take) are kept: the
    // new dictation is appended after them.
    _dictation.syncManual(_text.text);
    setState(() {
      _isListening = true;
      _mode = CaptureInputMode.voice;
      _inputError = null;
    });
    _ripple.repeat();

    // Primary path: one uninterrupted recording for Gemini (online).
    if (await _tryStartAudio()) return;
    if (!mounted || !_isListening) return;

    final ready = await _ensureSpeech();
    if (!mounted || !_isListening) return;

    if (ready && _speech != null) {
      try {
        await _listenSession();
        // True silence from now on ends the capture after the timeout.
        _armSilenceTimer();
        return;
      } catch (e) {
        debugPrint('[STT Listen failed]: $e');
      }
    }
    if (widget.enableSpeechRecognition) {
      // A real device without a working recognizer: say so honestly instead of
      // typing a made-up sentence.
      _stopListening();
      if (mounted) {
        setState(() {
          _mode = CaptureInputMode.type;
          _inputError =
              'Voice input is not available on this device right now. Type '
              'what you spent instead.';
        });
      }
      return;
    }
    _startDemoDictation();
  }

  // ---------------------------------------------------------------------------
  // Gemini multimodal audio (primary online path)
  // ---------------------------------------------------------------------------

  /// Starts the single uninterrupted recording when Gemini can transcribe it
  /// (live runtime + online + microphone permission). Returns `false` to fall
  /// back to offline `speech_to_text` dictation.
  Future<bool> _tryStartAudio() async {
    if (!widget.enableSpeechRecognition || !widget.enableAudioCapture) {
      return false;
    }
    try {
      final ai = ref.read(hybridAiServiceProvider);
      if (!await ai.canTranscribeAudio()) return false;
      final recorder = _recorder ??=
          (widget.voiceRecorderFactory?.call() ?? PlatformVoiceRecorder());
      if (!await recorder.hasPermission()) return false;
      if (!mounted || !_isListening) return true; // cancelled meanwhile
      _detector = SilenceDetector(silence: widget.audioSilenceTimeout);
      _ampTicks = 0;
      _audioActive = true;
      await recorder.start(onAmplitude: _onAmplitude);
      _maxRecordTimer?.cancel();
      _maxRecordTimer = Timer(_maxRecording, _autoAnalyze);
      return true;
    } catch (e) {
      debugPrint('[Audio capture → offline dictation]: $e');
      _audioActive = false;
      _maxRecordTimer?.cancel();
      try {
        await _recorder?.cancel();
      } catch (_) {}
      return false;
    }
  }

  /// Microphone level (dBFS, ~every 100 ms): drives Pocko's voice glow and the
  /// 3.5 s dead-air detector (silence after speech has started).
  void _onAmplitude(double db) {
    if (!mounted || !_audioActive) return;
    final level = ((db + 55) / 45).clamp(0.0, 1.0);
    _voiceLevel.value = _voiceLevel.value * 0.6 + level * 0.4;
    _ampTicks++;
    if (_detector.update(db, Duration(milliseconds: _ampTicks * 100))) {
      _autoAnalyze();
    }
  }

  /// Stops the recording and sends it to Gemini; the verbatim transcript fills
  /// the capture view and is saved as the Original Voice Prompt.
  Future<void> _finishRecording() async {
    if (!_audioActive) return;
    _audioActive = false;
    _maxRecordTimer?.cancel();
    _silenceTimer?.cancel();
    _ripple.stop();
    _ripple.reset();
    _voiceLevel.value = 0;
    if (mounted) setState(() => _isListening = false);

    RecordedAudio? audio;
    try {
      audio = await _recorder?.stop();
    } catch (e) {
      debugPrint('[Audio stop failed]: $e');
    }
    if (!mounted) return;
    if (audio == null) {
      setState(
        () => _inputError = 'Pocko could not record. Check the microphone permission and try again.',
      );
      return;
    }
    if (audio.duration < _minRecording) {
      setState(
        () =>
            _inputError = 'I did not hear anything. Tap the mic and try again.',
      );
      return;
    }

    final recorded = audio;
    _pendingAudio = recorded;
    await _runAudio(recorded);
  }

  /// Sends one recording to Gemini (transcribe + parse in one call). Used for
  /// the first attempt and for "Try again" with the very same audio.
  Future<void> _runAudio(RecordedAudio recorded) async {
    final state = ref.read(tripControllerProvider);
    await _analyze(
      audioParse: () async {
        final ai = ref.read(hybridAiServiceProvider);
        final self =
            state.memberById(state.currentMemberId) ?? state.trip.members.first;
        final b64 = base64Encode(recorded.bytes);
        final names = state.trip.members.map((m) => m.name).toList();
        final token = _runToken;
        _previewShownAt = null;

        // Live feel: a fast transcription-only call runs next to the full
        // analysis and the words appear (word by word) while it is still going.
        unawaited(
          ai
              .transcribeAudio(
                audioBase64: b64,
                audioMimeType: recorded.mimeType,
                memberNames: names,
              )
              .then((words) {
                if (words == null ||
                    !mounted ||
                    token != _runToken ||
                    _step != CaptureStep.processing) {
                  return;
                }
                _revealTranscript(words, token);
              })
              .catchError((_) {}),
        );

        final result = await ai.parseExpenseAudio(
          audioBase64: b64,
          audioMimeType: recorded.mimeType,
          tripCurrency: state.trip.baseCurrency,
          memberNames: names,
          defaultPayer: self.name,
        );
        _revealTimer?.cancel();
        // If the preview just appeared, let it be read before the review.
        final shown = _previewShownAt;
        if (shown != null) {
          final since = DateTime.now().difference(shown);
          if (since < _previewHold) {
            await Future<void>.delayed(_previewHold - since);
          }
        }
        return result;
      },
    );
  }

  /// "Try again" on the failure banner: same recording or same text.
  void _retryAnalysis() {
    final audio = _pendingAudio;
    if (audio != null) {
      _runAudio(audio);
    } else {
      _analyze(fromSpeech: _textFromSpeech);
    }
  }

  /// Restarts the "natural pause" timer: when no new word arrives for
  /// [AiExpenseCaptureSheet.silenceTimeout] the transcript is analyzed.
  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    if (!_isListening) return;
    _silenceTimer = Timer(widget.silenceTimeout, _autoAnalyze);
  }

  void _autoAnalyze() {
    _silenceTimer?.cancel();
    if (!mounted) return;
    if (_audioActive) {
      _finishRecording();
      return;
    }
    final hasText = _text.text.trim().isNotEmpty;
    _stopListening();
    if (hasText && _step == CaptureStep.input) _analyze(fromSpeech: true);
  }

  void _stopListening() {
    _dictationTimer?.cancel();
    _silenceTimer?.cancel();
    if (_audioActive) {
      // Switching to typing (or an error) discards the recording.
      _audioActive = false;
      _maxRecordTimer?.cancel();
      unawaited(
        (_recorder?.cancel() ?? Future<void>.value()).catchError((_) {}),
      );
    }
    _ripple.stop();
    _ripple.reset();
    _voiceLevel.value = 0;
    if (_speechReady == true) {
      try {
        _speech?.stop();
      } catch (_) {}
    }
    if (mounted) setState(() => _isListening = false);
  }

  /// Types a demo phrase word by word with a fake voice envelope (no speech
  /// engine available). The silence timer then analyzes it like real speech.
  void _startDemoDictation() {
    final state = ref.read(tripControllerProvider);
    final others = state.trip.members
        .where((m) => m.id != state.currentMemberId)
        .toList();
    final a = others.isNotEmpty ? others[0].name : 'Alex';
    final b = others.length > 1 ? others[1].name : 'Maya';
    final words =
        'Ichiran ramen 4800 split with $a and $b, and coffee 1200 for me'.split(
          ' ',
        );
    var i = 0;
    _text.clear();

    _dictationTimer?.cancel();
    _dictationTimer = Timer.periodic(const Duration(milliseconds: 140), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _voiceLevel.value = 0.35 + 0.55 * math.Random().nextDouble();
      if (i < words.length) {
        setState(() => _text.text = words.sublist(0, i + 1).join(' '));
        i++;
        _armSilenceTimer();
      } else {
        t.cancel();
        _voiceLevel.value = 0;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Input helpers
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Analysis
  // ---------------------------------------------------------------------------

  /// A realistic visual beat for local analysis: long enough to read as work,
  /// short enough to feel instant. Live runtimes that take longer are never
  /// delayed any further.
  static const Duration _minAnalyzeBeat = Duration(milliseconds: 500);

  /// Combines the people tagged up front with the people Pocko detected:
  /// nothing tagged -> AI's pick; tagged at least as many as detected -> the
  /// user's tags; fewer -> tags plus every detected member (auto-selected).
  List<String> _mergeSplit(List<String> detected, List<String> memberOrder) {
    if (_preselected.isEmpty) return detected;
    if (_preselected.length >= detected.length) {
      return [
        for (final id in memberOrder)
          if (_preselected.contains(id)) id,
      ];
    }
    final union = {..._preselected, ...detected};
    return [
      for (final id in memberOrder)
        if (union.contains(id)) id,
    ];
  }

  Future<void> _analyze({
    Future<HybridAiResult> Function()? audioParse,
    bool fromSpeech = false,
  }) async {
    final fromAudio = audioParse != null;
    var text = _text.text.trim();
    if (!fromAudio && text.isEmpty) {
      setState(
        () => _inputError =
            'Say or type what you spent first, or tap a quick phrase below.',
      );
      return;
    }
    if (_isListening) _stopListening();
    _focus.unfocus();

    // Dictation hears "2,200" as "2 200": one number, before any model sees it.
    if (!fromAudio) {
      final collapsed = SpokenNumbers.collapseSpacedThousands(text);
      if (collapsed != text) {
        text = collapsed;
        _dictation.syncManual(text);
        _setTranscript(text);
      }
      _textFromSpeech = fromSpeech;
    }

    final token = ++_runToken;
    setState(() {
      _step = CaptureStep.processing;
      _inputError = null;
      _aiFailure = null;
      _processingAudio = fromAudio;
    });

    final state = ref.read(tripControllerProvider);
    final self =
        state.memberById(state.currentMemberId) ?? state.trip.members.first;
    final started = DateTime.now();

    try {
      final result = fromAudio
          ? await audioParse()
          : await ref
                .read(hybridAiServiceProvider)
                .parseExpenseText(
                  text: text,
                  tripCurrency: state.trip.baseCurrency,
                  memberNames: state.trip.members.map((m) => m.name).toList(),
                  defaultPayer: self.name,
                  fromSpeech: fromSpeech,
                );
      _pendingAudio = null;
      if (fromAudio) {
        // Gemini's verbatim transcript is the text the user "said": it fills
        // the capture view (word / price / member highlighting) and becomes
        // the Original Voice Prompt saved in Expense.note.
        text = (result.transcript ?? _fallbackTranscript(result)).trim();
        _dictation.syncManual(text);
        _setTranscript(text);
      }

      // Let the juggling morph breathe so the transition never flashes.
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minAnalyzeBeat) {
        await Future<void>.delayed(_minAnalyzeBeat - elapsed);
      }
      if (!mounted || token != _runToken) return;

      if (!result.hasParsedAmount) {
        setState(() {
          _step = CaptureStep.input;
          _inputError = fromAudio
              ? 'Pocko could not find an amount in that recording. Try again, or type it.'
              : 'Pocko could not find an amount. Try something like "Ramen 4800 split 4 ways".';
        });
        return;
      }

      final memberIds = state.trip.members.map((m) => m.id).toList();
      final built = result.toExpenseItems(
        defaultCurrency: state.trip.baseCurrency,
        defaultPayerId: self.id,
        allMemberIds: memberIds,
        nameToIdMap: {for (final m in state.trip.members) m.name: m.id},
      );
      final readings = result.drafts;
      final items = <ExpenseItem>[];
      final drafts = <ParsedExpenseDraft?>[];
      for (var i = 0; i < built.length; i++) {
        final e = built[i];
        if (e.amount <= 0) continue;
        final draft = i < readings.length ? readings[i] : null;
        // An itemized bill is exactly the people who named a price.
        final split = e.isItemized
            ? e.splitWithMemberIds
            : _mergeSplit(e.splitWithMemberIds, memberIds);
        items.add(
          e.copyWith(
            splitWithMemberIds: split,
            // "500 yen each" x the people actually in the split.
            amount: draft?.totalFor(split.length) ?? e.amount,
          ),
        );
        drafts.add(draft);
      }
      _rawPrompt = text;

      setState(() {
        _aiResult = result;
        _items = items;
        _drafts = drafts;
        _originalCustom
          ..clear()
          ..addAll({
            for (var i = 0; i < items.length; i++)
              if (items[i].customSplits != null) i: items[i].customSplits!,
          });
        _tokens = tokenizeTranscript(
          text,
          [
            for (var i = 0; i < items.length; i++)
              (
                title: items[i].title,
                // The number the user actually said (500), not the total (1500).
                amount: drafts[i]?.unitAmount ?? items[i].amount,
              ),
          ],
          members: [
            for (final m in state.trip.members) (id: m.id, name: m.name),
          ],
          selfId: self.id,
        );
        _focused = 0;
        _editing = null;
        _step = CaptureStep.review;
      });
    } on AiUnavailableException catch (e) {
      // No real model answered: say so, with the reason. No regex fallback.
      debugPrint('[AI unavailable]: $e');
      _revealTimer?.cancel();
      if (mounted && token == _runToken) {
        setState(() {
          _step = CaptureStep.input;
          _aiFailure = e;
        });
      }
    } catch (e) {
      debugPrint('[AI Processing Error]: $e');
      if (mounted && token == _runToken) {
        setState(() {
          _step = CaptureStep.input;
          _inputError = 'Something went wrong while parsing. Please try again.';
        });
      }
    }
  }

  /// Shows Gemini's quick transcript word by word in the analyzing view.
  void _revealTranscript(String words, int token) {
    final parts = words.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return;
    _revealTimer?.cancel();
    _previewShownAt = DateTime.now();
    var shown = 0;
    // Whole reveal takes at most ~0.9 s, however long the sentence is.
    final step = Duration(
      milliseconds: (900 / parts.length).clamp(25, 70).round(),
    );
    _revealTimer = Timer.periodic(step, (t) {
      if (!mounted || token != _runToken || _step != CaptureStep.processing) {
        t.cancel();
        return;
      }
      shown++;
      setState(() => _setTranscript(parts.take(shown).join(' ')));
      if (shown >= parts.length) t.cancel();
    });
  }

  /// A readable stand-in when Gemini returned items but no transcript.
  String _fallbackTranscript(HybridAiResult result) {
    final parts = [
      for (final i in result.items)
        '${i['title'] ?? 'Expense'} ${i['unitAmount'] ?? i['amount'] ?? ''}'
            .trim(),
    ];
    return parts.join(', ');
  }

  void _cancelProcessing() {
    _runToken++;
    setState(() => _step = CaptureStep.input);
  }

  // ---------------------------------------------------------------------------
  // Review: focus & inline editing
  // ---------------------------------------------------------------------------

  void _focusItem(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() => _focused = i);
  }

  void _startEdit(int i, {required bool isAmount}) {
    _focusItem(i);
    final e = _items[i];
    _editController.text = isAmount
        ? (e.amount % 1 == 0
              ? e.amount.toStringAsFixed(0)
              : e.amount.toStringAsFixed(2))
        : e.title;
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editController.text.length,
    );
    setState(() {
      _editing = _EditTarget(i, isAmount);
      _inputError = null;
    });
    // Make sure the inline editor is never hidden behind the member bar.
    _revealEditor();
  }

  Future<void> _revealEditor() async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    final ctx = _editorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        alignment: 0.5,
      );
    }
  }

  void _saveEdit() {
    final target = _editing;
    if (target == null) return;
    final raw = _editController.text.trim();
    final e = _items[target.index];
    if (target.isAmount) {
      final v = double.tryParse(raw.replaceAll(',', ''));
      if (v == null || v <= 0) {
        setState(() => _inputError = 'Enter a price greater than zero.');
        return;
      }
      // A typed total replaces the AI's maths and any itemized shares.
      _items[target.index] = e.copyWith(amount: v, clearCustomSplits: true);
      // A hand-typed total replaces the AI's unit x people maths.
      if (target.index < _drafts.length) _drafts[target.index] = null;
    } else {
      if (raw.isEmpty) {
        setState(() => _inputError = 'Give this item a name.');
        return;
      }
      _items[target.index] = e.copyWith(title: raw);
    }
    setState(() {
      _editing = null;
      _inputError = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _inputError = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _toggleSplit(String memberId) {
    if (_step != CaptureStep.review || _items.isEmpty) {
      // Pre-selection before analysis (empty = "let Pocko decide").
      setState(() {
        if (!_preselected.add(memberId)) _preselected.remove(memberId);
      });
      return;
    }
    final e = _items[_focused];
    final split = List<String>.from(e.splitWithMemberIds);
    if (split.contains(memberId)) {
      if (split.length == 1) return; // never leave an expense with nobody
      split.remove(memberId);
    } else {
      split.add(memberId);
    }
    final draft = _focused < _drafts.length ? _drafts[_focused] : null;
    if (e.isItemized) {
      // Removing a friend removes their dish from the bill; adding one back
      // brings their listed price back (or nothing if they had none).
      final original = _originalCustom[_focused] ?? e.customSplits!;
      final custom = {for (final id in split) id: original[id] ?? 0.0};
      final total = custom.values.fold<double>(0, (a, b) => a + b);
      setState(
        () => _items[_focused] = e.copyWith(
          splitWithMemberIds: split,
          customSplits: custom,
          amount: total > 0 ? total : e.amount,
        ),
      );
      return;
    }
    setState(
      () => _items[_focused] = e.copyWith(
        splitWithMemberIds: split,
        // "500 yen each": the total follows the number of people in the split.
        amount: draft?.totalFor(split.length) ?? e.amount,
      ),
    );
  }

  void _setPayer(String memberId) {
    setState(
      () => _items[_focused] = _items[_focused].copyWith(payerId: memberId),
    );
  }

  void _setCurrency(String code) {
    if (_items.isEmpty) return;
    setState(() {
      _items[_focused] = _items[_focused].copyWith(currency: code);
      final d = _focused < _drafts.length ? _drafts[_focused] : null;
      if (d != null) _drafts[_focused] = d.copyWith(currency: code);
    });
  }

  void _setCategory(int i, ExpenseCategory c) {
    setState(() => _items[i] = _items[i].copyWith(category: c));
  }

  // ---------------------------------------------------------------------------
  // Confirm
  // ---------------------------------------------------------------------------

  void _close() {
    final cb = widget.onClose;
    if (cb != null) {
      cb();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _manualExpense() {
    if (_isListening) _stopListening();
    _focus.unfocus();
    final cb = widget.onManualExpense;
    if (cb != null) {
      cb();
    } else {
      _close();
    }
  }

  Future<void> _confirm() async {
    if (_items.isEmpty || _items.any((e) => e.amount <= 0)) return;
    final controller = ref.read(tripControllerProvider.notifier);
    // Audit trail: every item keeps the exact words that produced it.
    final committed = [
      for (final e in _items)
        _rawPrompt.isEmpty
            ? e
            : e.copyWith(
                note: RawPromptNote.compose(_rawPrompt, extra: e.note),
              ),
    ];
    controller.addExpenses(committed);
    final all = ref.read(tripControllerProvider).trip.expenses;
    final ids = all
        .skip(all.length - committed.length)
        .map((e) => e.id)
        .toList();

    final base = ref.read(tripControllerProvider).trip.baseCurrency;
    final total = committed.fold<double>(0, (sum, e) => sum + e.amountIn(base));
    _loggedLabel = committed.length == 1
        ? '✓ Logged ${CurrencyHelper.formatAmount(committed.first.amountIn(base), base)} • ${committed.first.title}'
        : '✓ Logged ${committed.length} expenses • ${CurrencyHelper.formatAmount(total, base)}';

    setState(() {
      _step = CaptureStep.logged;
      _editing = null;
    });
    final first = committed.first;
    final each = committed.length == 1
        ? 'Split ${first.splitWithMemberIds.length} ways • '
        : '';
    showPockoToast(
      context,
      message: committed.length == 1
          ? '${first.title} logged'
          : '${committed.length} expenses logged',
      detail:
          '$each${CurrencyHelper.formatAmount(total, base)} total • balances updated',
      icon: first.category.icon,
      actionLabel: 'Undo',
      onAction: () {
        for (final id in ids) {
          controller.removeExpense(id);
        }
      },
    );

    // Joyful "Logged ✓" beat, then fade back to the live page underneath.
    await Future<void>.delayed(kLoggedBeat);
    if (mounted) _close();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboard > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : screenHeight;
        // Height the user can actually see (the keyboard eats the rest).
        final avail = height - keyboard;
        final tight = keyboardOpen || avail < 560;

        // Giant hero on standard / tall viewports; it only shrinks when the
        // keyboard is open (or the viewport is genuinely short).
        final baseHero = keyboardOpen
            ? (avail < 420 ? 56.0 : 72.0)
            : avail >= 760
            ? 240.0
            : avail >= 660
            ? 190.0
            : avail >= 560
            ? 140.0
            : 100.0;
        // With a failure banner on screen Pocko makes room so the banner and
        // the Clear pill never need scrolling.
        final showingError =
            _step == CaptureStep.input &&
            (_aiFailure != null || _inputError != null);
        final heroSize = _step == CaptureStep.review
            ? math.min(baseHero, keyboardOpen ? 56.0 : 120.0)
            : (showingError ? math.min(baseHero, 110.0) : baseHero);
        final showModes = avail >= 600 && _step == CaptureStep.input;
        final showManual =
            _step == CaptureStep.input && !keyboardOpen && avail >= 540;
        // Below ~430 px of visible height the bar no longer fits beside the footer.
        final showBar = avail >= 430 && _step != CaptureStep.logged;
        final compactBar = avail < 520;

        final mood = switch (_step) {
          CaptureStep.input =>
            _isListening ? PockoMood.listening : PockoMood.waving,
          CaptureStep.processing => PockoMood.juggling,
          CaptureStep.review => PockoMood.waving,
          CaptureStep.logged => PockoMood.celebrating,
        };

        return Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Soft green aura behind Pocko. No blur filter anywhere: the
                // dim scrim and page scale live in the host, so the overlay
                // stays at full frame rate.
                AnimatedBuilder(
                  animation: _aura,
                  builder: (context, _) => Positioned(
                    top: height * 0.02,
                    left: (constraints.maxWidth - 360) / 2,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.28 + _aura.value * 0.22,
                        child: Transform.scale(
                          scale: 0.92 + _aura.value * 0.16,
                          child: Container(
                            width: 360,
                            height: 360,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x7034D399),
                                  Color(0x3038BDF8),
                                  Colors.transparent,
                                ],
                                stops: [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: !keyboardOpen,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: keyboardOpen ? keyboard : 0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            _topBar(),
                            if (_step == CaptureStep.logged)
                              Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  _hero(heroSize, mood),
                                  Positioned.fill(
                                    child: Center(
                                      child: LoggedBurst(size: heroSize * 0.8),
                                    ),
                                  ),
                                ],
                              )
                            else
                              _hero(heroSize, mood),
                            Expanded(
                              // A soft dark vignette (a plain gradient, no
                              // blur) keeps the big text legible over the
                              // still-visible page.
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: RadialGradient(
                                    radius: 0.85,
                                    colors: [
                                      Color(0x66000000),
                                      Color(0x00000000),
                                    ],
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                  child: switch (_step) {
                                    CaptureStep.input => _inputBody(
                                      tight: tight,
                                      showModes: showModes,
                                    ),
                                    CaptureStep.processing => _processingBody(
                                      tight: tight,
                                    ),
                                    CaptureStep.review => _reviewBody(
                                      tight: tight,
                                      keyboardOpen: keyboardOpen,
                                    ),
                                    CaptureStep.logged => _loggedStep(),
                                  },
                                ),
                              ),
                            ),
                            if (showBar) _memberBar(compact: compactBar),
                            _footer(
                              tight: tight,
                              keyboardOpen: keyboardOpen,
                              showManual: showManual,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hero(double size, PockoMood mood) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: size + 8,
      alignment: Alignment.center,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.55,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutBack)),
        child: ValueListenableBuilder<double>(
          valueListenable: _voiceLevel,
          builder: (context, level, _) => Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                key: const ValueKey('hero_pocko'),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                width: size,
                height: size,
                child: PockoMascot(
                  mood: mood,
                  size: size,
                  voiceLevel: _isListening ? level : 0,
                ),
              ),
              if (_step == CaptureStep.logged)
                Positioned(
                  right: size * 0.06,
                  bottom: size * 0.04,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.elasticOut,
                    builder: (context, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Container(
                      width: size * 0.3,
                      height: size * 0.3,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryEmerald,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: size * 0.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: AppTheme.pillRadius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: Color(0xFF34D399),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Pocko AI Capture Ready',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tactile(
            onTap: _close,
            semanticLabel: 'Close capture',
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step A: input (moving green gradient on the live text)
  // ---------------------------------------------------------------------------

  static const _emerald = Color(0xFF10B981);
  static const _mint = Color(0xFF6EE7B7);
  static const _teal = Color(0xFF14B8A6);

  LinearGradient _liveGradient(double t) => LinearGradient(
    colors: const [_emerald, _mint, _teal, _emerald],
    stops: const [0.0, 0.4, 0.75, 1.0],
    tileMode: TileMode.mirror,
    transform: _SlideGradient(t * 2),
  );

  Widget _inputBody({required bool tight, required bool showModes}) {
    final typing = _mode == CaptureInputMode.type;
    final fontSize = tight ? 24.0 : 30.0;
    final hasText = _text.text.trim().isNotEmpty;
    final glowing = hasText || _isListening;

    // ONE permanently mounted TextField: the controller and FocusNode live in
    // the State, and the widget sits at the same tree path (AnimatedBuilder >
    // ShaderMask > TextField) for 0, 1 and N characters, so typing the first
    // character can never remount it or drop focus.
    final field = TextField(
      key: const ValueKey('capture_text_field'),
      controller: _text,
      focusNode: _focus,
      textAlign: TextAlign.center,
      maxLines: null,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _analyze(),
      onChanged: (_) {
        if (_inputError != null || _aiFailure != null) {
          setState(() {
            _inputError = null;
            _aiFailure = null;
            _pendingAudio = null;
          });
        } else {
          setState(() {});
        }
      },
      style: GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1.3,
        letterSpacing: -0.3,
      ),
      cursorColor: _mint,
      decoration: InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: _isListening
            ? 'Listening…'
            : (typing
                  ? 'Type what you spent…'
                  : 'Tap the mic and just say it…'),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: tight ? 18 : 24,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.62),
        ),
      ),
    );
    final glowField = AnimatedBuilder(
      // Idle: a static animation, so no per-frame rebuild until text appears.
      animation: glowing ? _sweep : kAlwaysDismissedAnimation,
      child: field,
      builder: (context, child) => RepaintBoundary(
        child: ShaderMask(
          key: const ValueKey('live_gradient'),
          // Idle: BlendMode.dst paints the text untouched. Glowing: the moving
          // green gradient replaces the glyph colour (srcIn).
          blendMode: glowing ? BlendMode.srcIn : BlendMode.dst,
          shaderCallback: (bounds) =>
              _liveGradient(_sweep.value).createShader(bounds),
          child: child,
        ),
      ),
    );

    return Column(
      key: const ValueKey('step_input'),
      children: [
        if (showModes)
          Padding(
            key: const ValueKey('mode_row'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _BigModeButton(
                    icon: Icons.mic_rounded,
                    label: 'Voice',
                    selected: !typing,
                    compact: tight,
                    onTap: () {
                      _focus.unfocus();
                      setState(() => _mode = CaptureInputMode.voice);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BigModeButton(
                    icon: Icons.keyboard_rounded,
                    label: 'Type',
                    selected: typing,
                    compact: tight,
                    onTap: () {
                      if (_isListening) _stopListening();
                      setState(() => _mode = CaptureInputMode.type);
                      _focus.requestFocus();
                    },
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          key: const ValueKey('input_area'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // The transcript scrolls inside whatever room is left; the Clear
            // pill and the red banner below it are pinned and never leave the
            // visible area, however long the sentence gets.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('transcript_scroll'),
                    reverse: true,
                    physics: const BouncingScrollPhysics(),
                    child: glowField,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  child: hasText
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _clearChip(),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: (_aiFailure == null && _inputError == null)
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _errorBanner(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Red banner pinned under the transcript: why capture failed, and (for AI
  /// failures) a one-tap "Try again" that re-sends the same words or audio.
  Widget _errorBanner() {
    final failure = _aiFailure;
    final message = failure?.userMessage ?? _inputError ?? '';
    return Container(
      key: ValueKey(
        failure != null ? 'ai_failure_banner' : 'input_error_banner',
      ),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Color(0xFFFECACA),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (failure?.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      failure!.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (failure != null && failure.kind != AiFailureKind.offline) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('retry_ai_button'),
              onPressed: _retryAnalysis,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
              child: Text(
                'Try again',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Subtle 1-tap "Clear" pill so starting over is effortless.
  Widget _clearChip() {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: StadiumBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        key: const ValueKey('clear_transcript'),
        customBorder: const StadiumBorder(),
        onTap: _clearTranscript,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                'Clear',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Emerald "Confirm" pill with a clean checkmark (no emoji).
  /// Thumb-friendly Confirm: 58px tall, generous padding, 17.5 / w700 text and
  /// a 22px checkmark (no emoji).
  Widget _confirmButton({required VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      key: const ValueKey('confirm_button'),
      onPressed: onPressed,
      icon: const Icon(Icons.check_rounded, size: 22),
      label: const Text(
        'Confirm',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryEmerald,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white24,
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.pillRadius),
        elevation: 4,
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Matching large Back button.
  Widget _backButton({required VoidCallback onPressed}) {
    return OutlinedButton(
      key: const ValueKey('back_button'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.pillRadius),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: const Text('Back'),
    );
  }

  Widget _footer({
    required bool tight,
    required bool keyboardOpen,
    required bool showManual,
  }) {
    switch (_step) {
      case CaptureStep.input:
        final typing = _mode == CaptureInputMode.type;
        final hasText = _text.text.trim().isNotEmpty;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, tight ? 6 : 10, 20, tight ? 8 : 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!typing || !keyboardOpen) _micOrb(tight: tight),
                  if (typing || hasText) ...[
                    const SizedBox(width: 16),
                    Flexible(child: _confirmButton(onPressed: _analyze)),
                  ],
                ],
              ),
              if (showManual)
                TextButton.icon(
                  key: const ValueKey('manual_expense_button'),
                  onPressed: _manualExpense,
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  label: const Text('Manual Expense'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.7),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      case CaptureStep.processing:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton(
            onPressed: _cancelProcessing,
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        );
      case CaptureStep.review:
        final state = ref.watch(tripControllerProvider);
        final base = state.trip.baseCurrency;
        final total = _items.fold<double>(0, (s, e) => s + e.amountIn(base));
        final canConfirm =
            _items.isNotEmpty && _items.every((e) => e.amount > 0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_items.length} expense${_items.length == 1 ? '' : 's'} • ${CurrencyHelper.formatAmount(total, base)} total',
                style: AppTheme.tabularNumberStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _backButton(
                    onPressed: () => setState(() => _step = CaptureStep.input),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _confirmButton(
                      onPressed: canConfirm ? _confirm : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case CaptureStep.logged:
        return const SizedBox(height: 16);
    }
  }

  // ---------------------------------------------------------------------------
  // Group member tag bar (always visible, from the very first stage)
  // ---------------------------------------------------------------------------

  Widget _memberBar({required bool compact}) {
    final state = ref.watch(tripControllerProvider);
    final members = state.trip.members;
    final inReview = _step == CaptureStep.review && _items.isNotEmpty;
    final focusedItem = inReview
        ? _items[_focused.clamp(0, _items.length - 1)]
        : null;
    final selected = focusedItem != null
        ? focusedItem.splitWithMemberIds.toSet()
        : _preselected;
    // Explicit names instead of a bare count: "(3) Liam, Maya, Alex".
    final selectedIds = focusedItem != null
        ? focusedItem.splitWithMemberIds
        : _preselected.toList();
    // With several expenses the caption also says which one is being edited.
    final multi = focusedItem != null && _items.length > 1;
    final caption = selectedIds.isEmpty
        ? 'Tap to tag who is in, or let Pocko pick'
        : '${multi ? '${focusedItem.title} · ' : ''}${formatSelectedNames([for (final id in selectedIds) state.nameOf(id)], maxChars: multi ? 26 : 34)}';

    return Column(
      key: const ValueKey('member_bar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          key: focusedItem != null ? const ValueKey('focus_label') : null,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: compact ? 46 : 56,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final m in members)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 3 : 4,
                      ),
                      child: MemberPill(
                        key: ValueKey('member_${m.id}'),
                        name: state.displayName(m),
                        selected: selected.contains(m.id),
                        compact: compact,
                        onTap: () => _toggleSplit(m.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _micOrb({required bool tight}) {
    final size = tight ? 64.0 : 88.0;
    // The ripple is purely decorative: it paints OUTSIDE the orb's fixed
    // box (negative Positioned insets, no clipping) and never takes part in
    // layout, so growing it cannot push the other elements around.
    const maxGrow = 46.0; // 24 + level(1) * 22
    return ValueListenableBuilder<double>(
      valueListenable: _voiceLevel,
      builder: (context, level, _) => SizedBox(
        key: const ValueKey('mic_orb'),
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (_isListening)
              Positioned(
                left: -maxGrow,
                top: -maxGrow,
                right: -maxGrow,
                bottom: -maxGrow,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _ripple,
                      builder: (context, _) {
                        final grow = 24 + level * 22;
                        final d = size + _ripple.value * grow;
                        return Container(
                          key: const ValueKey('mic_ripple'),
                          width: d,
                          height: d,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryEmerald.withValues(
                                alpha: 1.0 - _ripple.value,
                              ),
                              width: 2.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            // Soft glow as a pre-computed radial gradient (only its opacity
            // follows the voice level), instead of an animated blurred shadow.
            Positioned(
              left: -26,
              top: -26,
              right: -26,
              bottom: -26,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('mic_glow'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primaryEmerald.withValues(
                          alpha: 0.4 + level * 0.3,
                        ),
                        AppTheme.primaryEmerald.withValues(alpha: 0),
                      ],
                      stops: const [0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Tactile(
              onTap: _toggleListening,
              pressedScale: 0.92,
              semanticLabel: _isListening
                  ? 'Stop and analyze'
                  : 'Start voice dictation',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: AppTheme.emeraldShineGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: size * 0.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step B: analyzing (Pocko juggles, the user's words shimmer in place)
  // ---------------------------------------------------------------------------

  Widget _processingBody({required bool tight}) {
    return Center(
      key: const ValueKey('step_processing'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnalyzingText(
                key: const ValueKey('analyzing_text'),
                text: _text.text.trim().isEmpty && _processingAudio
                    ? 'Transcribing your voice…'
                    : _text.text.trim(),
                sweep: _sweep,
                fontSize: tight ? 24 : 30,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: AppTheme.pillRadius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  'Pocko is reading your words…',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'On-device first. The cloud is used only if needed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step C: review with inline highlighted transcript
  // ---------------------------------------------------------------------------

  static const _pillTints = [
    Color(0xFFFFD9C7),
    Color(0xFFCFE8FF),
    Color(0xFFE6D9FF),
    Color(0xFFFFF0B8),
  ];

  Widget _pill({
    required int item,
    required String label,
    required bool isAmount,
    required Key key,
  }) {
    final focused = _focused == item;
    final e = _items[item];
    final base = isAmount
        ? const Color(0xFFBFF3DA)
        : _pillTints[item % _pillTints.length];
    return GestureDetector(
      key: key,
      // First tap only selects the item (preview + split pills follow, no
      // keyboard); a second tap on the selected item opens inline editing.
      onTap: () =>
          focused ? _startEdit(item, isAmount: isAmount) : _focusItem(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: _pillMargin,
        padding: _pillPadding,
        decoration: BoxDecoration(
          color: base.withValues(alpha: focused ? 1 : 0.72),
          borderRadius: BorderRadius.circular(_pillRadius),
          // Constant width: focus changes colour and glow, never the size, so
          // every pill (title, price, member) keeps identical metrics.
          border: Border.all(
            color: focused
                ? AppTheme.primaryEmerald
                : Colors.white.withValues(alpha: 0.4),
            width: _pillBorderWidth,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.55),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: isAmount
              ? AppTheme.tabularNumberStyle(
                  fontSize: _pillFontSize,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF064E3B),
                )
              : GoogleFonts.plusJakartaSans(
                  fontSize: _pillFontSize,
                  fontWeight: FontWeight.w900,
                  color: e.category.accentColor,
                ),
        ),
      ),
    );
  }

  /// Category pill on its own centered row under the highlighted text.
  Widget _categoryRow(int item) {
    final e = _items[item];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PockoSelector<ExpenseCategory>(
            key: ValueKey('cat_badge_$item'),
            tooltip: 'Change category',
            label: e.category.displayName,
            leadingIcon: e.category.icon,
            leadingColor: e.category.pastelColor,
            selected: e.category,
            onOpened: () => _focusItem(item),
            onSelected: (c) => _setCategory(item, c),
            entries: [
              for (final c in ExpenseCategory.values)
                PockoMenuEntry<ExpenseCategory>(
                  value: c,
                  label: c.displayName,
                  icon: c.icon,
                  accent: c.accentColor,
                  pastel: c.pastelColor.withValues(alpha: 0.6),
                ),
            ],
          ),
          const SizedBox(width: 8),
          // Explicit edit affordance: opens inline editing (and the keyboard)
          // only when asked, never from a plain selection tap.
          Tooltip(
            message: 'Edit name',
            child: InkResponse(
              key: ValueKey('edit_item_$item'),
              onTap: () => _startEdit(item, isAmount: false),
              radius: 24,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether [memberId] is part of the focused item's split (drives the
  /// highlight of that member's name inside the transcript).
  bool _isMemberHighlighted(String memberId) {
    if (_items.isEmpty) return false;
    return _items[_focused.clamp(0, _items.length - 1)].splitWithMemberIds
        .contains(memberId);
  }

  /// Member name pill: the exact size, weight, padding and corner radius of the
  /// item-title and price pills, in its own soft lavender tint.
  Widget _memberToken({
    required String memberId,
    required String text,
    required Key key,
  }) {
    return GestureDetector(
      key: key,
      onTap: () => _toggleSplit(memberId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: _pillMargin,
        padding: _pillPadding,
        decoration: BoxDecoration(
          color: _memberPillTint,
          borderRadius: BorderRadius.circular(_pillRadius),
          border: Border.all(color: _memberPillBorder, width: _pillBorderWidth),
          boxShadow: [
            BoxShadow(
              color: _memberPillBorder.withValues(alpha: 0.35),
              blurRadius: 12,
            ),
          ],
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: _pillFontSize,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF4C1D95),
          ),
        ),
      ),
    );
  }

  InlineSpan _transcriptSpan(double fontSize) {
    final base = GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.75,
      color: Colors.white.withValues(alpha: 0.92),
    );
    final spans = <InlineSpan>[];
    final mentionCount = <String, int>{};

    for (var i = 0; i < _tokens.tokens.length; i++) {
      final t = _tokens.tokens[i];
      if (t.kind == TranscriptTokenKind.text) {
        spans.add(TextSpan(text: t.text));
        continue;
      }
      if (t.kind == TranscriptTokenKind.member) {
        final id = t.memberId!;
        final ordinal = mentionCount.update(
          id,
          (v) => v + 1,
          ifAbsent: () => 0,
        );
        if (_isMemberHighlighted(id)) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _memberToken(
                memberId: id,
                text: t.text,
                key: ValueKey('member_token_${id}_$ordinal'),
              ),
            ),
          );
        } else {
          // Un-highlighted: the name is plain text again (tap to re-add).
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                key: ValueKey('member_text_${id}_$ordinal'),
                onTap: () => _toggleSplit(id),
                child: Text(
                  t.text,
                  style: base.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        }
        continue;
      }
      final item = t.itemIndex!;
      if (item >= _items.length) {
        spans.add(TextSpan(text: t.text));
        continue;
      }
      final isAmount = t.kind == TranscriptTokenKind.amount;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _pill(
            item: item,
            isAmount: isAmount,
            label: isAmount
                ? CurrencyHelper.formatAmount(
                    _items[item].amount,
                    _items[item].currency,
                  )
                : _items[item].title,
            key: ValueKey('pill_${isAmount ? 'amount' : 'title'}_$item'),
          ),
        ),
      );
    }

    // Entities that were not found verbatim in the transcript still get pills.
    for (var item = 0; item < _items.length; item++) {
      final noTitle = _tokens.missingTitle.contains(item);
      final noAmount = _tokens.missingAmount.contains(item);
      if (!noTitle && !noAmount) continue;
      spans.add(const TextSpan(text: '\n'));
      if (noTitle) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _pill(
              item: item,
              isAmount: false,
              label: _items[item].title,
              key: ValueKey('pill_title_$item'),
            ),
          ),
        );
      }
      if (noAmount) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _pill(
              item: item,
              isAmount: true,
              label: CurrencyHelper.formatAmount(
                _items[item].amount,
                _items[item].currency,
              ),
              key: ValueKey('pill_amount_$item'),
            ),
          ),
        );
      }
    }
    return TextSpan(style: base, children: spans);
  }

  Widget _reviewBody({required bool tight, required bool keyboardOpen}) {
    final state = ref.watch(tripControllerProvider);
    final members = state.trip.members;
    final result = _aiResult;
    final focusedItem = _items.isEmpty
        ? null
        : _items[_focused.clamp(0, _items.length - 1)];
    final fontSize = tight ? 24.0 : 30.0;
    final focusedIndex = focusedItem == null
        ? 0
        : _focused.clamp(0, _items.length - 1);

    return Column(
      key: const ValueKey('step_review'),
      children: [
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TelemetryPill(
              key: const ValueKey('ai_source_badge'),
              onDark: true,
              plain: true,
              source: result.inferenceSource,
              latencyMs: result.latencyMs,
              modelInfo: result.modelInfo,
              simulated: result.isSimulated,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  _transcriptSpan(fontSize),
                  key: const ValueKey('inline_transcript'),
                  textAlign: TextAlign.center,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _editing == null
                      ? const SizedBox(width: double.infinity)
                      : KeyedSubtree(key: _editorKey, child: _inlineEditor()),
                ),
                if (focusedItem != null) ...[
                  // Category pill: its own centered row under the text.
                  _categoryRow(focusedIndex),
                  const SizedBox(height: 12),
                  // Live miniature of the Expenses-list card.
                  ExpensePreviewCard(
                    item: focusedItem,
                    tripState: state,
                    itemized: focusedItem.isItemized,
                    breakdown: focusedItem.isItemized
                        ? '${CurrencyHelper.formatAmount(focusedItem.amount, focusedItem.currency)} (${[for (final id in focusedItem.splitWithMemberIds) '${state.nameOf(id)} ${CurrencyHelper.formatAmount(focusedItem.customSplits![id] ?? 0, focusedItem.currency)}'].join(' · ')})'
                        : (focusedIndex < _drafts.length
                              ? _drafts[focusedIndex]?.breakdown(
                                  focusedItem.splitWithMemberIds.length,
                                )
                              : null),
                    actions: [
                      PockoSelector<String>(
                        key: const ValueKey('payer_menu'),
                        tooltip: 'Who paid?',
                        onDark: false,
                        compact: true,
                        leadingIcon: Icons.payments_rounded,
                        leadingColor: AppTheme.primaryEmeraldDark,
                        label: '${state.nameOf(focusedItem.payerId)} paid',
                        selected: focusedItem.payerId,
                        onSelected: _setPayer,
                        entries: [
                          for (final m in members)
                            PockoMenuEntry<String>(
                              value: m.id,
                              label: '${state.displayName(m)} paid',
                              icon: Icons.payments_rounded,
                            ),
                        ],
                      ),
                      PockoSelector<String>(
                        key: const ValueKey('currency_menu'),
                        tooltip: 'Currency',
                        onDark: false,
                        compact: true,
                        leadingIcon: Icons.currency_exchange_rounded,
                        leadingColor: AppTheme.primaryEmeraldDark,
                        label: focusedItem.currency,
                        selected: focusedItem.currency,
                        onSelected: _setCurrency,
                        entries: [
                          for (final code
                              in CurrencyHelper.currencySymbols.keys)
                            PockoMenuEntry<String>(
                              value: code,
                              label:
                                  '$code ${CurrencyHelper.currencySymbols[code]}',
                              pastel: const Color(0xFFDCF0FF),
                              accent: const Color(0xFF3B82F6),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Sleek inline editor that appears right under the transcript.
  Widget _inlineEditor() {
    final target = _editing!;
    final item = _items[target.index];
    return Container(
      key: const ValueKey('inline_editor'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.isAmount ? 'PRICE (${item.currency})' : 'ITEM NAME',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                  ),
                ),
                TextField(
                  key: const ValueKey('inline_edit_field'),
                  controller: _editController,
                  autofocus: true,
                  keyboardType: target.isAmount
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveEdit(),
                  style: target.isAmount
                      ? AppTheme.tabularNumberStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        )
                      : GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
                if (_inputError != null)
                  Text(
                    _inputError!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.coralOwesText,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: _cancelEdit,
            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
          ),
          IconButton.filled(
            key: const ValueKey('inline_edit_save'),
            tooltip: 'Save',
            onPressed: _saveEdit,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryEmerald,
            ),
            icon: const Icon(Icons.check_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step D: logged
  // ---------------------------------------------------------------------------

  Widget _loggedStep() {
    return Center(
      key: const ValueKey('step_logged'),
      child: LoggedPill(
        label: _loggedLabel,
        subtitle:
            '${_items.length} expense${_items.length == 1 ? '' : 's'} added • balances updated',
      ),
    );
  }
}

class _BigModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _BigModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      semanticLabel: '$label input',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: compact ? 44 : 58,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(compact ? 22 : 29),
          border: Border.all(
            color: selected
                ? AppTheme.primaryEmerald
                : Colors.white.withValues(alpha: 0.16),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.35),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: compact ? 20 : 24,
              color: Colors.white.withValues(alpha: selected ? 1 : 0.7),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: selected ? 1 : 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slides a gradient horizontally by [percent] of the paint bounds' width so a
/// mirrored gradient scrolls seamlessly while the user speaks or types.
class _SlideGradient extends GradientTransform {
  final double percent;
  const _SlideGradient(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
}

/// The user's own words while Pocko analyzes: a luminous emerald-mint shimmer
/// sweeps across the text and each word rides a gentle kinetic wave.
class _AnalyzingText extends StatelessWidget {
  final String text;
  final Animation<double> sweep;
  final double fontSize;

  const _AnalyzingText({
    super.key,
    required this.text,
    required this.sweep,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final style = GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.3,
      letterSpacing: -0.3,
      color: Colors.white,
    );
    return AnimatedBuilder(
      animation: sweep,
      builder: (context, _) {
        final t = sweep.value;
        return RepaintBoundary(
          child: ShaderMask(
            key: const ValueKey('analyzing_shimmer'),
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: const [
                Color(0x8CFFFFFF),
                Color(0x8CFFFFFF),
                Color(0xFF10B981),
                Color(0xFF6EE7B7),
                Color(0xFFFFFFFF),
                Color(0xFF6EE7B7),
                Color(0xFF10B981),
                Color(0x8CFFFFFF),
                Color(0x8CFFFFFF),
              ],
              stops: const [0, 0.18, 0.34, 0.44, 0.5, 0.56, 0.66, 0.82, 1],
              transform: _SlideGradient(t * 2 - 1),
            ).createShader(bounds),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 2,
              children: [
                for (var i = 0; i < words.length; i++)
                  Transform.translate(
                    offset: Offset(0, math.sin(t * 2 * math.pi - i * 0.7) * 4),
                    child: Transform.scale(
                      scale: 1 + 0.025 * math.sin(t * 2 * math.pi - i * 0.7),
                      child: Text(words[i], style: style),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
