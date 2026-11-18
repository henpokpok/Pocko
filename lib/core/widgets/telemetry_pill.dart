import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../enums/inference_source.dart';
import '../theme/app_theme.dart';

/// Sleek Hybrid-AI telemetry pill:
///   `🟢 On-Device • Gemini Nano • 92 ms`   or   `☁️ Cloud Fallback • Gemini Flash • 840 ms`.
///
/// Results produced by the offline heuristic engine carry a subtle `SIM` tag so
/// judges can always tell a real runtime from the safety-net simulator.
class TelemetryPill extends StatelessWidget {
  final InferenceSource source;
  final int? latencyMs;
  final String? modelInfo;
  final bool simulated;

  /// Short variant for list rows: `🟢 92 ms`.
  final bool compact;

  /// Render for dark overlays (capture screen).
  final bool onDark;

  const TelemetryPill({
    super.key,
    required this.source,
    this.latencyMs,
    this.modelInfo,
    this.simulated = false,
    this.compact = false,
    this.onDark = false,
  });

  String get _emoji => source == InferenceSource.onDevice
      ? '🟢'
      : (source == InferenceSource.inCloud ? '☁️' : '✏️');

  String get _title {
    switch (source) {
      case InferenceSource.onDevice:
        return 'On-Device';
      case InferenceSource.inCloud:
        return 'Cloud Fallback';
      case InferenceSource.manual:
        return 'Manual';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : source.foregroundColor;
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.14)
        : source.backgroundColor;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.2)
        : source.foregroundColor.withValues(alpha: 0.18);
    final ms = latencyMs;

    final label = compact
        ? (ms != null ? '$_emoji $ms ms' : _emoji)
        : [
            '$_emoji $_title',
            if (source != InferenceSource.manual) source.engineLabel(modelInfo),
          ].join(' • ');

    return Semantics(
      label:
          'AI source $_title${ms != null ? ', $ms milliseconds' : ''}${simulated ? ', simulated' : ''}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 11,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppTheme.pillRadius,
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: compact ? 10.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (!compact && ms != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$ms ms',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            if (simulated) ...[
              const SizedBox(width: 5),
              Tooltip(
                message: 'Offline heuristic engine (no live on-device or cloud model reachable)',
                child: Text(
                  'SIM',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: fg.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact footer badge shown at the very bottom of Matcher and Expense cards:
/// `🟢 (Local) • 92ms`, `☁️ (Cloud) • 640ms` or `🟢 (Sim) • 92ms` when the
/// offline engine answered because no live runtime is configured.
class TelemetryFooter extends StatelessWidget {
  final InferenceSource source;
  final int? latencyMs;
  final bool simulated;

  const TelemetryFooter({
    super.key,
    required this.source,
    this.latencyMs,
    this.simulated = false,
  });

  /// Plain text of the badge (used by tests and semantics).
  static String format(
    InferenceSource source,
    int? latencyMs, {
    bool simulated = false,
  }) {
    final emoji = switch (source) {
      InferenceSource.onDevice => '🟢',
      InferenceSource.inCloud => '☁️',
      InferenceSource.manual => '✏️',
    };
    if (source == InferenceSource.manual) return '$emoji (Manual)';
    final kind = simulated
        ? 'Sim'
        : (source == InferenceSource.onDevice ? 'Local' : 'Cloud');
    return latencyMs == null
        ? '$emoji ($kind)'
        : '$emoji ($kind) • ${latencyMs}ms';
  }

  @override
  Widget build(BuildContext context) {
    final text = format(source, latencyMs, simulated: simulated);
    return Semantics(
      label: 'AI source: $text',
      child: ExcludeSemantics(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
