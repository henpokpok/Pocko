import 'package:flutter/material.dart';

/// Specifies the execution source of the AI inference
enum InferenceSource {
  onDevice(
    'on_device',
    '🟢 On-Device',
    'Gemini Nano / Apple Foundation Models',
    Color(0xFF047857),
    Color(0xFFE8F8F0),
  ),
  inCloud(
    'in_cloud',
    '☁️ Cloud Fallback',
    'Gemini Flash (Firebase AI Logic)',
    Color(0xFF1D4ED8),
    Color(0xFFE6F0FF),
  ),
  manual(
    'manual',
    '✏️ Manual Entry',
    'User manually entered',
    Color(0xFF475569),
    Color(0xFFEEF2F6),
  );

  final String rawValue;
  final String badgeLabel;
  final String description;
  final Color foregroundColor;
  final Color backgroundColor;

  const InferenceSource(
    this.rawValue,
    this.badgeLabel,
    this.description,
    this.foregroundColor,
    this.backgroundColor,
  );

  static InferenceSource fromRaw(String? raw) {
    if (raw == null) return InferenceSource.manual;
    final normalized = raw.toLowerCase().trim();
    if (normalized == 'on_device' ||
        normalized == 'local' ||
        normalized == 'ondevice') {
      return InferenceSource.onDevice;
    }
    if (normalized == 'in_cloud' ||
        normalized == 'cloud' ||
        normalized == 'incloud') {
      return InferenceSource.inCloud;
    }
    return InferenceSource.manual;
  }

  /// Short engine name for telemetry pills, derived from the reported model.
  /// Examples: `Gemini Nano`, `Apple FM`, `Chrome AI`, `Gemini Flash`.
  String engineLabel([String? modelInfo]) {
    final info = (modelInfo ?? '').toLowerCase();
    switch (this) {
      case InferenceSource.onDevice:
        if (info.contains('apple')) return 'Apple FM';
        if (info.contains('chrome')) return 'Gemini Nano (Chrome)';
        return 'Gemini Nano';
      case InferenceSource.inCloud:
        return 'Gemini Flash';
      case InferenceSource.manual:
        return 'Manual';
    }
  }
}

/// Hybrid inference preference requested by the client
enum InferenceMode {
  preferOnDevice(
    'PREFER_ON_DEVICE',
    'prefer_on_device',
    'Prefer Local (On-Device + Cloud Fallback)',
  ),
  onlyOnDevice('ONLY_ON_DEVICE', 'only_on_device', 'Strictly On-Device Only'),
  onlyInCloud('ONLY_IN_CLOUD', 'only_in_cloud', 'Cloud Only (Gemini Flash)');

  /// Upper-case name used by the native MethodChannel bridges (Kotlin / Swift).
  final String wireName;

  /// Lower-case value used by the Firebase JS SDK (`InferenceMode.PREFER_ON_DEVICE === 'prefer_on_device'`).
  final String webName;
  final String displayLabel;

  const InferenceMode(this.wireName, this.webName, this.displayLabel);

  /// Parses Remote Config / platform strings in any casing.
  static InferenceMode fromRaw(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    switch (normalized) {
      case 'only_on_device':
      case 'onlyondevice':
        return InferenceMode.onlyOnDevice;
      case 'only_in_cloud':
      case 'onlyincloud':
      case 'prefer_in_cloud':
        return InferenceMode.onlyInCloud;
      default:
        return InferenceMode.preferOnDevice;
    }
  }
}
