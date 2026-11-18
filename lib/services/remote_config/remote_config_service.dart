import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable model of active Firebase Remote Config parameters
class RemoteConfigData {
  final bool isConfigured;
  final String aiInferenceMode;
  final String cloudFallbackModel;
  final String promptTemplateOverride;
  final int maxOutputTokens;
  final String lastStatus;
  final DateTime? lastFetchTime;

  const RemoteConfigData({
    required this.isConfigured,
    required this.aiInferenceMode,
    required this.cloudFallbackModel,
    required this.promptTemplateOverride,
    required this.maxOutputTokens,
    required this.lastStatus,
    this.lastFetchTime,
  });

  factory RemoteConfigData.initial() {
    return const RemoteConfigData(
      isConfigured: false,
      aiInferenceMode: 'prefer_on_device',
      cloudFallbackModel: 'gemini-3.1-flash-lite',
      promptTemplateOverride: '',
      maxOutputTokens: 512,
      lastStatus: 'Defaults (Local)',
    );
  }

  RemoteConfigData copyWith({
    bool? isConfigured,
    String? aiInferenceMode,
    String? cloudFallbackModel,
    String? promptTemplateOverride,
    int? maxOutputTokens,
    String? lastStatus,
    DateTime? lastFetchTime,
  }) {
    return RemoteConfigData(
      isConfigured: isConfigured ?? this.isConfigured,
      aiInferenceMode: aiInferenceMode ?? this.aiInferenceMode,
      cloudFallbackModel: cloudFallbackModel ?? this.cloudFallbackModel,
      promptTemplateOverride:
          promptTemplateOverride ?? this.promptTemplateOverride,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      lastStatus: lastStatus ?? this.lastStatus,
      lastFetchTime: lastFetchTime ?? this.lastFetchTime,
    );
  }
}

final remoteConfigProvider =
    NotifierProvider<RemoteConfigNotifier, RemoteConfigData>(
      RemoteConfigNotifier.new,
    );

class RemoteConfigNotifier extends Notifier<RemoteConfigData> {
  @override
  RemoteConfigData build() {
    return RemoteConfigService.instance.currentData;
  }

  Future<bool> refresh() async {
    final success = await RemoteConfigService.instance.forceRefresh();
    state = RemoteConfigService.instance.currentData;
    return success;
  }
}

/// Firebase Remote Config Service for Dynamic AI Policy & Prompt Overrides
class RemoteConfigService {
  static final RemoteConfigService instance = RemoteConfigService._();
  RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfigInstance;
  bool _isConfigured = false;
  DateTime? _lastFetchTime;
  String _lastStatus = 'Defaults (Local)';

  RemoteConfigService({FirebaseRemoteConfig? remoteConfig})
    : _remoteConfigInstance = remoteConfig;

  FirebaseRemoteConfig? get _remoteConfig {
    if (_remoteConfigInstance != null) return _remoteConfigInstance;
    try {
      _remoteConfigInstance = FirebaseRemoteConfig.instance;
      return _remoteConfigInstance;
    } catch (e) {
      return null;
    }
  }

  static const String keyInferenceMode = 'ai_inference_mode';
  static const String keyCloudFallbackModel = 'cloud_fallback_model';
  static const String keyPromptTemplateOverride = 'prompt_template_override';
  static const String keyMaxOutputTokens = 'max_output_tokens';

  static const Map<String, dynamic> _defaultValues = {
    keyInferenceMode: 'prefer_on_device',
    keyCloudFallbackModel: 'gemini-3.1-flash-lite',
    keyPromptTemplateOverride: '',
    keyMaxOutputTokens: 512,
  };

  bool get isConfigured => _isConfigured;
  DateTime? get lastFetchTime => _lastFetchTime;
  String get lastStatus => _lastStatus;

  /// Returns the live Remote Config string, or the local default when Remote
  /// Config is not linked or the remote value is blank.
  String _stringValue(String key) {
    final fallback = _defaultValues[key] as String;
    if (!_isConfigured) return fallback;
    final rc = _remoteConfig;
    if (rc == null) return fallback;
    try {
      final value = rc.getString(key).trim();
      return value.isEmpty && key != keyPromptTemplateOverride
          ? fallback
          : value;
    } catch (_) {
      return fallback;
    }
  }

  /// One of `prefer_on_device`, `only_on_device`, `only_in_cloud` (any casing is accepted).
  String get aiInferenceMode => _stringValue(keyInferenceMode);

  String get cloudFallbackModel => _stringValue(keyCloudFallbackModel);

  String get promptTemplateOverride => _stringValue(keyPromptTemplateOverride);

  /// Clamped to a sane range so a bad remote value can never break inference.
  int get maxOutputTokens {
    final fallback = _defaultValues[keyMaxOutputTokens] as int;
    if (!_isConfigured) return fallback;
    final rc = _remoteConfig;
    if (rc == null) return fallback;
    try {
      final value = rc.getInt(keyMaxOutputTokens);
      return value <= 0 ? fallback : value.clamp(64, 8192);
    } catch (_) {
      return fallback;
    }
  }

  RemoteConfigData get currentData => RemoteConfigData(
    isConfigured: isConfigured,
    aiInferenceMode: aiInferenceMode,
    cloudFallbackModel: cloudFallbackModel,
    promptTemplateOverride: promptTemplateOverride,
    maxOutputTokens: maxOutputTokens,
    lastStatus: lastStatus,
    lastFetchTime: lastFetchTime,
  );

  Future<void> initializeAndFetch() async {
    try {
      final rc = _remoteConfig;
      if (rc == null) {
        _isConfigured = false;
        _lastStatus = 'Offline Defaults';
        return;
      }

      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 1),
        ),
      );

      await rc.setDefaults(_defaultValues);
      final updated = await rc.fetchAndActivate();
      _isConfigured = true;
      _lastFetchTime = DateTime.now();
      _lastStatus = updated ? 'Updated from Cloud' : 'Active (No Change)';
      debugPrint(
        '[RemoteConfig] Fetched successfully. Mode: $aiInferenceMode ($lastStatus)',
      );
    } catch (e) {
      _isConfigured = false;
      _lastStatus = 'Offline Defaults ($e)';
      debugPrint('[RemoteConfig] Standalone / test fallback ($e)');
    }
  }

  Future<bool> forceRefresh() async {
    try {
      final rc = _remoteConfig;
      if (rc == null) {
        _lastStatus = 'Standby (Offline Test Mode)';
        return false;
      }
      final updated = await rc.fetchAndActivate();
      _isConfigured = true;
      _lastFetchTime = DateTime.now();
      _lastStatus = updated ? 'Refreshed from Cloud' : 'Up to date';
      return true;
    } catch (e) {
      _lastStatus = 'Refresh error: $e';
      return false;
    }
  }
}
