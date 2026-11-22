import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/inference_source.dart';
import '../../core/enums/slip_status.dart';
import '../../models/expense_item.dart';
import '../remote_config/remote_config_service.dart';
import 'ai_unavailable.dart';
import 'expense_normalizer.dart';
import 'expense_prompt_builder.dart';
import 'local_expense_parser.dart';
import 'parsed_expense_draft.dart';
import '../network/network_probe.dart';
import 'web_hybrid_ai_bridge.dart';

/// Shared hybrid AI runtime. Override in tests with a mock / zero-latency service.
final hybridAiServiceProvider = Provider<HybridAiService>(
  (ref) => HybridAiService(),
);

/// Decides, within a strict time budget, whether a real hybrid runtime should be
/// used for a request, and bounds the call itself.
///
/// * `probe` answers "is anything configured / ready?" and is capped by
///   [probeTimeout]; an unconfigured environment therefore reaches the local
///   parser almost instantly instead of waiting on CDN imports or model checks.
/// * A positive answer is cached for [cacheFor], so configured runtimes run
///   directly with zero extra blocking on later requests.
/// * `call` is capped by [callTimeout] so a stuck runtime never hangs the UI.
class LiveInferenceGate {
  final Duration probeTimeout;
  final Duration callTimeout;
  final Duration cacheFor;

  bool? _cachedReady;
  DateTime? _cachedAt;

  /// The last error that made a live call return `null` (for honest messages).
  String? lastError;

  LiveInferenceGate({
    this.probeTimeout = const Duration(milliseconds: 450),
    // The native chain can spend ~8 s on-device + 2 x 10 s cloud attempts.
    this.callTimeout = const Duration(seconds: 40),
    this.cacheFor = const Duration(seconds: 30),
  });

  Future<bool> _ready(Future<bool> Function() probe) async {
    final at = _cachedAt;
    if (at != null && DateTime.now().difference(at) < cacheFor) {
      return _cachedReady ?? false;
    }
    bool ready;
    try {
      ready = await probe().timeout(probeTimeout);
    } catch (_) {
      ready = false;
    }
    _cachedReady = ready;
    _cachedAt = DateTime.now();
    return ready;
  }

  /// Runs [call] only when [probe] says a runtime is reachable. Returns `null`
  /// when it is not, when the call fails, or when it exceeds [callTimeout].
  Future<T?> run<T>({
    required Future<bool> Function() probe,
    required Future<T?> Function() call,
    Duration? timeout,
  }) async {
    lastError = null;
    if (!await _ready(probe)) {
      lastError = 'No Firebase AI runtime is ready in this browser';
      return null;
    }
    try {
      return await call().timeout(timeout ?? callTimeout);
    } catch (e) {
      lastError = e.toString();
      debugPrint('[LiveInferenceGate] live call failed or timed out: $e');
      // Re-probe next time instead of trusting a runtime that just failed.
      _cachedAt = null;
      return null;
    }
  }
}

/// Structured AI response contract as mandated by technical specifications
class HybridAiResult {
  final String rawJson;
  final InferenceSource inferenceSource;
  final int latencyMs;
  final String modelInfo;
  final Map<String, dynamic>? parsedData;
  final bool hasReceipt;

  /// `true` when the answer came from the built-in offline heuristic engine
  /// instead of a real on-device / cloud model (headless tests, unconfigured
  /// simulators, mock mode). The UI labels such results honestly.
  final bool isSimulated;

  const HybridAiResult({
    required this.rawJson,
    required this.inferenceSource,
    required this.latencyMs,
    required this.modelInfo,
    this.parsedData,
    this.hasReceipt = false,
    this.isSimulated = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'rawJson': rawJson,
      'inferenceSource': inferenceSource.rawValue,
      'latencyMs': latencyMs,
      'modelInfo': modelInfo,
      'hasReceipt': hasReceipt,
      'isSimulated': isSimulated,
    };
  }

  factory HybridAiResult.fromMap(
    Map<String, dynamic> map, {
    bool hasReceipt = false,
  }) {
    final rawJson = map['rawJson'] as String? ?? '{}';
    final parsed = ExpensePromptBuilder.parseJson(rawJson);
    return HybridAiResult(
      rawJson: rawJson,
      inferenceSource: InferenceSource.fromRaw(
        map['inferenceSource'] as String?,
      ),
      latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
      modelInfo: map['modelInfo'] as String? ?? 'Unknown Model',
      parsedData: parsed,
      hasReceipt: (map['hasReceipt'] as bool?) ?? hasReceipt,
      isSimulated: (map['isSimulated'] as bool?) ?? false,
    );
  }

  /// The verbatim words Gemini heard in a recorded voice clip (audio requests
  /// only), or `null` for text requests.
  String? get transcript {
    final t = parsedData?['transcript'];
    if (t is! String) return null;
    final clean = t.trim();
    return clean.isEmpty ? null : clean;
  }

  /// Extracts the list of parsed expense items
  List<Map<String, dynamic>> get items {
    final data = parsedData;
    if (data == null) return const [];

    if (data['items'] is List) {
      final list = data['items'] as List;
      return list
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    }

    if (data.containsKey('amount') || data.containsKey('title')) {
      return [data];
    }

    return const [];
  }

  /// The items as typed drafts (unit amount, mode, quantity, percent), in the
  /// same order as [items] / [toExpenseItems].
  List<ParsedExpenseDraft> get drafts => [
    for (final m in items) ParsedExpenseDraft.fromMap(m),
  ];

  /// Receipt view of the payload (Smart Slip Matcher).
  ReceiptData? get receipt {
    final data = parsedData;
    if (data == null) return null;
    final total =
        (data['total'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble();
    if (total == null) return null;
    final lineItems = <ReceiptLine>[];
    final rawLines = data['lineItems'];
    if (rawLines is List) {
      for (final l in rawLines.whereType<Map>()) {
        lineItems.add(
          ReceiptLine(
            name: l['name']?.toString() ?? 'Item',
            amount: (l['amount'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }
    }
    return ReceiptData(
      merchant: (data['merchant'] ?? data['title'] ?? '').toString(),
      total: total,
      currency: (data['currency'] ?? '').toString().toUpperCase(),
      category: ExpenseCategory.fromString(data['category']?.toString()),
      lineItems: lineItems,
    );
  }

  /// Whether at least one expense with a positive amount was understood.
  bool get hasParsedAmount =>
      items.any((i) => ParsedExpenseDraft.fromMap(i).unitAmount > 0);

  static String? _resolveId(
    String? raw,
    Map<String, String>? nameToIdMap,
    String selfId,
  ) {
    if (raw == null || nameToIdMap == null) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'me' || lower == 'myself' || lower == 'i') return selfId;
    for (final entry in nameToIdMap.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// Converts the AI result into a list of domain ExpenseItems (multi-expense support)
  List<ExpenseItem> toExpenseItems({
    String? idPrefix,
    String defaultCurrency = 'JPY',
    String defaultPayerId = 'you',
    List<String> allMemberIds = const ['you'],
    Map<String, String>? nameToIdMap,
    bool? overrideReceipt,
  }) {
    final itemList = items;
    final prefix = idPrefix ?? 'exp_${DateTime.now().millisecondsSinceEpoch}';
    final effectiveSlipStatus = (overrideReceipt ?? hasReceipt)
        ? SlipStatus.matched
        : SlipStatus.waitingForSlip;

    if (itemList.isEmpty) {
      // Fallback single item
      return [
        ExpenseItem(
          id: '${prefix}_0',
          title: 'Expense',
          amount: 0.0,
          currency: defaultCurrency,
          payerId: defaultPayerId,
          splitWithMemberIds: allMemberIds,
          createdAt: DateTime.now(),
          inferenceSource: inferenceSource,
          modelInfo: modelInfo,
          latencyMs: latencyMs,
          slipStatus: effectiveSlipStatus,
        ),
      ];
    }

    final results = <ExpenseItem>[];
    for (int i = 0; i < itemList.length; i++) {
      final data = itemList[i];
      final title = (data['title'] as String?)?.isNotEmpty == true
          ? data['title'] as String
          : 'Expense ${i + 1}';
      final draft = ParsedExpenseDraft.fromMap(
        data,
        defaultCurrency: defaultCurrency,
      );
      final category = ExpenseCategory.fromString(data['category'] as String?);

      final payerId =
          _resolveId(data['payer'] as String?, nameToIdMap, defaultPayerId) ??
          defaultPayerId;

      final rawSplit = data['splitWith'] as List<dynamic>?;
      final splitWithIds = <String>[];
      if (rawSplit != null) {
        for (final item in rawSplit) {
          final id = _resolveId(item.toString(), nameToIdMap, defaultPayerId);
          if (id != null && !splitWithIds.contains(id)) splitWithIds.add(id);
        }
      }
      // Itemized bill: exact per-person shares keyed by member id.
      Map<String, double>? customById;
      if (draft.isItemized) {
        final byId = <String, double>{};
        draft.customSplits!.forEach((name, value) {
          final id = _resolveId(name, nameToIdMap, defaultPayerId);
          if (id != null) byId[id] = (byId[id] ?? 0) + value;
        });
        if (byId.length >= 2) {
          customById = byId;
          for (final id in byId.keys) {
            if (!splitWithIds.contains(id)) splitWithIds.add(id);
          }
        }
      }
      if (splitWithIds.isEmpty) splitWithIds.addAll(allMemberIds);
      // Dart computes the exact total (unit x quantity x people x percent, or
      // the sum of the itemized shares).
      final amount = draft.totalFor(splitWithIds.length);

      results.add(
        ExpenseItem(
          id: '${prefix}_$i',
          title: title,
          amount: amount,
          currency: draft.currency,
          category: category,
          payerId: payerId,
          splitWithMemberIds: splitWithIds,
          customSplits: customById,
          createdAt: DateTime.now(),
          inferenceSource: inferenceSource,
          modelInfo: modelInfo,
          latencyMs: latencyMs,
          slipStatus: effectiveSlipStatus,
        ),
      );
    }

    return results;
  }

  /// Converts the AI result into a single domain ExpenseItem (backward-compatible)
  ExpenseItem toExpenseItem({
    required String id,
    String defaultCurrency = 'JPY',
    String defaultPayerId = 'you',
    List<String> allMemberIds = const ['you'],
    Map<String, String>? nameToIdMap,
    bool? overrideReceipt,
  }) {
    final list = toExpenseItems(
      idPrefix: id,
      defaultCurrency: defaultCurrency,
      defaultPayerId: defaultPayerId,
      allMemberIds: allMemberIds,
      nameToIdMap: nameToIdMap,
      overrideReceipt: overrideReceipt,
    );
    return list.first.copyWith(id: id);
  }
}

class ReceiptLine {
  final String name;
  final double amount;
  const ReceiptLine({required this.name, required this.amount});
}

class ReceiptData {
  final String merchant;
  final double total;
  final String currency;
  final ExpenseCategory category;
  final List<ReceiptLine> lineItems;

  const ReceiptData({
    required this.merchant,
    required this.total,
    required this.currency,
    required this.category,
    this.lineItems = const [],
  });
}

/// Effective AI policy after applying Firebase Remote Config.
class AiPolicy {
  final InferenceMode mode;
  final String cloudModel;
  final int maxOutputTokens;
  final String promptTemplate;

  const AiPolicy({
    required this.mode,
    required this.cloudModel,
    required this.maxOutputTokens,
    required this.promptTemplate,
  });

  factory AiPolicy.fromRemoteConfig(RemoteConfigData data) => AiPolicy(
    mode: InferenceMode.fromRaw(data.aiInferenceMode),
    cloudModel: data.cloudFallbackModel.trim().isEmpty
        ? 'gemini-3.1-flash-lite'
        : data.cloudFallbackModel.trim(),
    maxOutputTokens: data.maxOutputTokens <= 0 ? 512 : data.maxOutputTokens,
    promptTemplate: data.promptTemplateOverride,
  );
}

/// State of the Gemini Nano model on this device (Android AICore).
class OnDeviceAiStatus {
  /// `available`, `downloadable`, `downloading`, `unavailable` or
  /// `unsupported` (no on-device runtime to manage: web, iOS, tests).
  final String state;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  const OnDeviceAiStatus(
    this.state, {
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  static const unsupported = OnDeviceAiStatus('unsupported');

  bool get isAvailable => state == 'available';
  bool get canDownload => state == 'downloadable';
  bool get isDownloading => state == 'downloading';
  bool get isManageable => state != 'unsupported';

  factory OnDeviceAiStatus.fromMap(Map<dynamic, dynamic> m) => OnDeviceAiStatus(
    (m['state'] ?? 'unavailable').toString(),
    downloadedBytes: (m['downloadedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
    error: m['error']?.toString(),
  );
}

/// Service governing Hybrid AI Inference across the Firebase AI Logic JS SDK
/// (Chrome), native MethodChannels (Android AICore Gemini Nano & iOS Apple
/// Foundation Models) and an honest offline heuristic engine.
class HybridAiService {
  static const MethodChannel _channel = MethodChannel(
    'com.hybridtrip.ai/inference',
  );

  /// Test seam only: swaps every real runtime for the deterministic
  /// [LocalExpenseParser]. Production code never sets it, and without it an
  /// expense that no real model can read raises [AiUnavailableException].
  bool isMockEnabled;

  /// Adds a realistic 70–130 ms (on-device) / 450–700 ms (cloud) delay to the
  /// simulated engine. Disabled in unit tests.
  final bool simulateLatency;

  final RemoteConfigData Function()? _policyReader;

  /// Time-boxes the "is a real runtime reachable?" probe and the live call.
  final LiveInferenceGate _gate;

  /// The last native error (PlatformException / timeout) for honest messages.
  String? _nativeError;

  HybridAiService({
    this.isMockEnabled = false,
    this.simulateLatency = true,
    this._policyReader,
    LiveInferenceGate? gate,
  }) : _gate = gate ?? LiveInferenceGate();

  /// Current policy (Remote Config values with safe local defaults).
  AiPolicy get policy {
    try {
      final data =
          (_policyReader ?? () => RemoteConfigService.instance.currentData)();
      return AiPolicy.fromRemoteConfig(data);
    } catch (_) {
      return AiPolicy.fromRemoteConfig(RemoteConfigData.initial());
    }
  }

  /// Whether Gemini Nano is downloaded on this Android phone (AICore). "On-device
  /// model is not available" usually just means it has not been downloaded yet.
  Future<OnDeviceAiStatus> onDeviceStatus() async {
    if (isMockEnabled || kIsWeb) return OnDeviceAiStatus.unsupported;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'onDeviceStatus',
      );
      if (res != null) return OnDeviceAiStatus.fromMap(res);
    } on MissingPluginException {
      return OnDeviceAiStatus.unsupported;
    } catch (e) {
      debugPrint('[HybridAiService] onDeviceStatus failed: $e');
    }
    return OnDeviceAiStatus.unsupported;
  }

  /// Starts the one-time Gemini Nano download (needs internet); poll
  /// [onDeviceStatus] for progress.
  Future<void> downloadOnDeviceModel() async {
    if (isMockEnabled || kIsWeb) return;
    try {
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'downloadOnDeviceModel',
      );
    } catch (e) {
      debugPrint('[HybridAiService] downloadOnDeviceModel failed: $e');
    }
  }

  /// Checks whether On-Device AI (Chrome Prompt API, AICore or Apple FM) is ready.
  Future<Map<String, dynamic>> checkModelStatus() async {
    if (isMockEnabled) {
      return {
        'isAvailable': true,
        'status': 'SIMULATED',
        'modelInfo': 'Gemini Nano (simulated engine)',
        'runtime': 'simulated',
      };
    }

    if (kIsWeb) {
      try {
        final webStatus = await WebHybridAiBridge.checkModelStatus();
        if (webStatus != null) return webStatus;
      } catch (_) {}
      return {
        'isAvailable': false,
        'status': 'BRIDGE_UNAVAILABLE',
        'modelInfo':
            'Firebase AI web bridge not loaded (simulated engine active)',
        'runtime': 'simulated',
      };
    }

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'checkModelStatus',
      );
      if (res != null) return {...res, 'runtime': 'native'};
    } catch (e) {
      debugPrint('[HybridAiService] checkModelStatus native unavailable: $e');
    }
    return {
      'isAvailable': false,
      'status': 'NATIVE_UNAVAILABLE',
      'modelInfo': 'No native runtime (simulated engine active)',
      'runtime': 'simulated',
    };
  }

  /// Parses natural language expense text into structured JSON output (single or multi-expense).
  /// When [mode] is omitted the Remote Config `ai_inference_mode` applies.
  Future<HybridAiResult> parseExpenseText({
    required String text,
    InferenceMode? mode,
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
    bool hasReceipt = false,
    bool fromSpeech = false,
  }) async {
    final p = policy;
    final effectiveMode = mode ?? p.mode;
    final prompt = ExpensePromptBuilder.buildPrompt(
      userInput: text,
      fromSpeech: fromSpeech,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
      templateOverride: p.promptTemplate,
    );

    final live = await _tryLiveInference(
      prompt: prompt,
      rawText: text,
      mode: effectiveMode,
      policy: p,
      hasReceipt: hasReceipt,
    );
    if (live != null) {
      return _normalizeLive(
        live,
        userInput: text,
        tripCurrency: tripCurrency,
        memberNames: memberNames,
        defaultPayer: defaultPayer,
      );
    }

    if (!isMockEnabled) throw await _unavailable();
    return _simulateExpenseInference(
      rawText: text,
      mode: effectiveMode,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
      hasReceipt: hasReceipt,
    );
  }

  /// Builds the honest "no real model answered" error: offline vs. timeout vs.
  /// rejected, with the runtime's own last error as detail.
  Future<AiUnavailableException> _unavailable() async {
    final online = await NetworkProbe.check();
    return AiUnavailableException.fromError(
      _gate.lastError ?? _nativeError,
      online: online,
    );
  }

  /// Runs a real model answer through [ExpenseNormalizer]. Unparseable answers
  /// are returned untouched so the caller's "could not find an amount" path
  /// still applies.
  HybridAiResult _normalizeLive(
    HybridAiResult live, {
    required String userInput,
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    if (live.items.isEmpty) return live;
    final fixed = ExpenseNormalizer.normalize(
      live.items,
      userInput: userInput,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    final payload = <String, dynamic>{
      'items': fixed,
      if (fixed.isNotEmpty) ...fixed.first,
    };
    return HybridAiResult(
      rawJson: jsonEncode(payload),
      inferenceSource: live.inferenceSource,
      latencyMs: live.latencyMs,
      modelInfo: live.modelInfo,
      parsedData: payload,
      hasReceipt: live.hasReceipt,
      isSimulated: live.isSimulated,
    );
  }

  /// Whether a recorded voice clip can be sent to Gemini right now: a real
  /// (non-simulated) runtime is configured **and** the device is online. When
  /// this is `false` the capture sheet uses offline dictation instead.
  Future<bool> canTranscribeAudio() async {
    if (isMockEnabled) return false;
    if (!await NetworkProbe.check()) return false;
    if (kIsWeb) {
      return WebHybridAiBridge.quickProbe(timeout: _gate.probeTimeout);
    }
    final status = await checkModelStatus();
    return status['isAvailable'] == true && status['runtime'] == 'native';
  }

  /// Sends one **uninterrupted voice recording** to Gemini (`gemini-3.1-flash-lite`,
  /// fallback `gemini-3.8-flash`) as inline audio together with the trip context
  /// and returns the verbatim [HybridAiResult.transcript] plus the parsed items
  /// in a single call. Throws [AiUnavailableException] when no live runtime
  /// answered (the caller shows why and offers to retry the same recording).
  Future<HybridAiResult> parseExpenseAudio({
    required String audioBase64,
    String audioMimeType = 'audio/mp4',
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
  }) async {
    final prompt = ExpensePromptBuilder.buildAudioPrompt(
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    final live = await _tryLiveInference(
      prompt: prompt,
      rawText: '',
      mode: InferenceMode.onlyInCloud,
      policy: policy,
      hasReceipt: false,
      audioBase64: audioBase64,
      audioMimeType: audioMimeType,
      // The transcript is part of the answer: leave room for it.
      maxOutputTokens: policy.maxOutputTokens < 1024
          ? 1024
          : policy.maxOutputTokens,
      timeout: const Duration(seconds: 55),
    );
    debugPrint(
      '[HybridAiService] audio analysis ${live == null ? 'unavailable' : 'in ${live.latencyMs} ms via ${live.modelInfo}'}',
    );
    if (live == null) throw await _unavailable();
    return normalizeAudioResult(
      live,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
  }

  /// Fast transcription-only call for the same recording: returns just the
  /// verbatim words (or `null`). The capture sheet fires it **in parallel**
  /// with [parseExpenseAudio] and shows the words as soon as they arrive, while
  /// the full analysis is still running.
  Future<String?> transcribeAudio({
    required String audioBase64,
    String audioMimeType = 'audio/mp4',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
  }) async {
    try {
      final live = await _tryLiveInference(
        prompt: ExpensePromptBuilder.buildTranscribePrompt(
          memberNames: memberNames,
        ),
        rawText: '',
        mode: InferenceMode.onlyInCloud,
        policy: policy,
        hasReceipt: false,
        audioBase64: audioBase64,
        audioMimeType: audioMimeType,
        maxOutputTokens: 384,
      );
      debugPrint(
        '[HybridAiService] audio transcript preview in ${live?.latencyMs} ms',
      );
      return live?.transcript;
    } catch (e) {
      debugPrint('[HybridAiService] transcribeAudio failed: $e');
      return null;
    }
  }

  /// Runs a Gemini audio answer through the same [ExpenseNormalizer] safety net
  /// as typed text (using the model's own transcript as the reference
  /// sentence) and keeps the verbatim `transcript` in the payload.
  @visibleForTesting
  HybridAiResult normalizeAudioResult(
    HybridAiResult live, {
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    final transcript = live.transcript ?? '';
    final normalized = _normalizeLive(
      live,
      userInput: transcript,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    final data = {...?normalized.parsedData, 'transcript': transcript};
    return HybridAiResult(
      rawJson: jsonEncode(data),
      inferenceSource: normalized.inferenceSource,
      latencyMs: normalized.latencyMs,
      modelInfo: normalized.modelInfo,
      parsedData: data,
      hasReceipt: normalized.hasReceipt,
      isSimulated: normalized.isSimulated,
    );
  }

  /// Suggests a category for a typed expense title (Manual Expense auto-assist).
  ///
  /// Runs a tiny `PREFER_ON_DEVICE` request (Gemini Nano first, cloud only if
  /// needed) with a hard 8 s cap, and falls back to the offline keyword
  /// classifier whenever no real model answers. Returns [ExpenseCategory.MISC]
  /// when nothing matches, so callers can stay quiet.
  Future<ExpenseCategory> suggestCategory(String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return ExpenseCategory.MISC;
    final offline = ExpenseCategory.fromString(clean);
    if (isMockEnabled) return offline;
    try {
      final live = await _tryLiveInference(
        prompt: ExpensePromptBuilder.buildCategoryPrompt(clean),
        rawText: clean,
        mode: InferenceMode.preferOnDevice,
        policy: policy,
        hasReceipt: false,
      ).timeout(const Duration(seconds: 8));
      final raw = live?.parsedData?['category']?.toString();
      if (raw != null) {
        final fromModel = ExpenseCategory.fromString(raw);
        if (fromModel != ExpenseCategory.MISC) return fromModel;
      }
    } catch (e) {
      debugPrint('[HybridAiService] suggestCategory fell back to keywords: $e');
    }
    return offline;
  }

  /// Parses an (already PII-masked) receipt / bank notification into a structured
  /// receipt. [forceCloud] routes itemized foreign receipts to the cloud model;
  /// everything else stays on-device first. [receiptBase64] attaches a photo.
  Future<HybridAiResult> parseReceipt({
    required String maskedText,
    String tripCurrency = 'JPY',
    bool forceCloud = false,
    String? receiptBase64,
    String? mimeType,
  }) async {
    final p = policy;
    final mode = forceCloud ? InferenceMode.onlyInCloud : p.mode;
    final prompt = ExpensePromptBuilder.buildReceiptPrompt(
      maskedText: maskedText,
      tripCurrency: tripCurrency,
    );

    final live = await _tryLiveInference(
      prompt: prompt,
      rawText: maskedText,
      mode: mode,
      policy: p,
      hasReceipt: true,
      receiptBase64: receiptBase64,
      mimeType: mimeType,
    );
    if (live != null) return live;

    final useOnDevice = mode != InferenceMode.onlyInCloud;
    final delay = _simulatedDelay(useOnDevice);
    if (simulateLatency) await Future.delayed(Duration(milliseconds: delay));
    final payload = LocalExpenseParser.parseReceipt(
      maskedText,
      tripCurrency: tripCurrency,
    );
    return HybridAiResult(
      rawJson: jsonEncode(payload),
      inferenceSource: useOnDevice
          ? InferenceSource.onDevice
          : InferenceSource.inCloud,
      latencyMs: simulateLatency ? delay : (useOnDevice ? 84 : 612),
      modelInfo: useOnDevice
          ? 'Gemini Nano • simulated engine'
          : '${p.cloudModel} • simulated engine',
      parsedData: payload,
      hasReceipt: true,
      isSimulated: true,
    );
  }

  int _simulatedDelay(bool onDevice) =>
      onDevice ? 70 + Random().nextInt(60) : 450 + Random().nextInt(250);

  /// Real inference through the Firebase JS SDK (Chrome) or native bridges.
  /// Returns `null` when no live runtime is reachable so callers can fall back.
  Future<HybridAiResult?> _tryLiveInference({
    required String prompt,
    required String rawText,
    required InferenceMode mode,
    required AiPolicy policy,
    required bool hasReceipt,
    String? receiptBase64,
    String? mimeType,
    String? audioBase64,
    String? audioMimeType,
    int? maxOutputTokens,
    Duration? timeout,
  }) async {
    if (isMockEnabled) return null;
    _nativeError = null;

    if (kIsWeb) {
      // Fast path: no bridge / no real config / no downloaded model -> null at once.
      return _gate.run<HybridAiResult>(
        probe: () => WebHybridAiBridge.quickProbe(timeout: _gate.probeTimeout),
        call: () async {
          final webResult = await WebHybridAiBridge.generateContent(
            prompt: prompt,
            mode: mode.webName,
            cloudFallbackModel: policy.cloudModel,
            maxOutputTokens: maxOutputTokens ?? policy.maxOutputTokens,
            receiptBase64: receiptBase64,
            audioBase64: audioBase64,
            mimeType: audioBase64 != null ? audioMimeType : mimeType,
          );
          return HybridAiResult.fromMap(webResult, hasReceipt: hasReceipt);
        },
        timeout: timeout,
      );
    }

    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('parseExpenseText', {
            'prompt': prompt,
            'rawText': rawText,
            'mode': mode.wireName,
            'cloudFallbackModel': policy.cloudModel,
            'maxOutputTokens': maxOutputTokens ?? policy.maxOutputTokens,
            'receiptBase64': ?receiptBase64,
            'mimeType': ?mimeType,
            'audioBase64': ?audioBase64,
            'audioMimeType': ?audioMimeType,
          })
          .timeout(timeout ?? _gate.callTimeout);
      if (result != null) {
        return HybridAiResult.fromMap(result, hasReceipt: hasReceipt);
      }
    } on TimeoutException {
      _nativeError = 'timeout: the native AI runtime did not answer in time';
      debugPrint('[HybridAiService] Native runtime timed out.');
    } on MissingPluginException {
      _nativeError = 'native AI bridge is not available on this platform';
    } on PlatformException catch (e) {
      _nativeError = '${e.code}: ${e.message}';
      debugPrint(
        '[HybridAiService] Native runtime unavailable (${e.code}): ${e.message}',
      );
    } catch (e) {
      _nativeError = '$e';
      debugPrint('[HybridAiService] Native MethodChannel error: $e');
    }
    return null;
  }

  Future<HybridAiResult> _simulateExpenseInference({
    required String rawText,
    required InferenceMode mode,
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
    bool hasReceipt = false,
  }) async {
    final stopwatch = Stopwatch()..start();

    final bool useOnDevice = mode != InferenceMode.onlyInCloud;
    final int delay = _simulatedDelay(useOnDevice);
    if (simulateLatency) await Future.delayed(Duration(milliseconds: delay));
    stopwatch.stop();

    final parsedItems = LocalExpenseParser.parseExpenses(
      rawText,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );

    final Map<String, dynamic> jsonPayload = {
      'items': parsedItems,
      if (parsedItems.isNotEmpty) ...parsedItems.first,
    };

    final source = useOnDevice
        ? InferenceSource.onDevice
        : InferenceSource.inCloud;
    return HybridAiResult(
      rawJson: jsonEncode(jsonPayload),
      inferenceSource: source,
      latencyMs: simulateLatency
          ? stopwatch.elapsedMilliseconds
          : (useOnDevice ? 84 : 612),
      modelInfo: useOnDevice
          ? 'Gemini Nano • simulated engine'
          : '${policy.cloudModel} • simulated engine',
      parsedData: jsonPayload,
      hasReceipt: hasReceipt,
      isSimulated: true,
    );
  }
}
