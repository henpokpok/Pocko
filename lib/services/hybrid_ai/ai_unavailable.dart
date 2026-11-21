/// Why no real model (On-Device AI or Cloud Gemini) answered.
enum AiFailureKind {
  /// No internet and no usable on-device model (Gemini Nano / Apple FM).
  offline,

  /// A runtime was reachable but did not answer in time.
  timeout,

  /// The request was rejected (App Check / authentication / quota).
  rejected,

  /// Any other failure (bridge not loaded, model error, bad answer).
  unavailable,
}

/// Thrown when an expense could not be read by a real model.
///
/// Pocko never substitutes a regex "rule engine" for the AI: the user sees an
/// honest message (and the technical [detail]) instead of a silent downgrade.
class AiUnavailableException implements Exception {
  final AiFailureKind kind;

  /// Short technical reason (last error from the runtime), safe to show.
  final String? detail;

  const AiUnavailableException(this.kind, {this.detail});

  /// Classifies a raw runtime error string.
  factory AiUnavailableException.fromError(
    Object? error, {
    required bool online,
  }) {
    final raw = (error ?? '').toString();
    final text = raw.toLowerCase();
    final AiFailureKind kind;
    if (!online) {
      kind = AiFailureKind.offline;
    } else if (text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('deadline')) {
      kind = AiFailureKind.timeout;
    } else if (text.contains('app check') ||
        text.contains('appcheck') ||
        text.contains('401') ||
        text.contains('403') ||
        text.contains('unauthenticated') ||
        text.contains('permission') ||
        text.contains('api key') ||
        text.contains('quota') ||
        text.contains('429')) {
      kind = AiFailureKind.rejected;
    } else {
      kind = AiFailureKind.unavailable;
    }
    final detail = raw.trim().isEmpty
        ? null
        : (raw.length > 140 ? '${raw.substring(0, 140)}…' : raw);
    return AiUnavailableException(kind, detail: detail);
  }

  /// The banner text shown in the capture sheet.
  String get userMessage {
    switch (kind) {
      case AiFailureKind.offline:
        return 'You are offline, and this device has no On-Device AI '
            '(Gemini Nano / Apple Intelligence) to read your expense. Connect '
            'to the internet, or use a device with On-Device AI.';
      case AiFailureKind.timeout:
        return 'Cloud Gemini did not answer in time. Check your connection '
            'and tap Try again.';
      case AiFailureKind.rejected:
        return 'Cloud Gemini refused the request (security check or quota). '
            'Reload the app and try again.';
      case AiFailureKind.unavailable:
        return 'Pocko AI could not read that right now. Tap Try again.';
    }
  }

  @override
  String toString() => 'AiUnavailableException($kind, $detail)';
}
