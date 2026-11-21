import 'package:flutter/material.dart';

/// Hosts the "+" capture overlay on top of the live page with a "light
/// overlap" transition and **no blur**:
///
/// * the page underneath stays **full-bleed at scale 1.0** (no shrink, no
///   rounded inset, so no black frame appears around the screen edges),
/// * a lightweight dim scrim ([scrimColor], ~92%) fades in over [duration] with
///   `Curves.easeOutCubic` across the whole viewport, status and navigation
///   areas included,
/// * the capture UI fades in on top.
///
/// Only opacity is animated (composited on the GPU), so it runs at full frame
/// rate. The overlay is unmounted once the fade-out ends.
class CaptureOverlayHost extends StatefulWidget {
  /// The live app (Scaffold + navigation) that sits underneath.
  final Widget page;

  /// Whether the overlay is requested to be open.
  final bool open;

  /// Builds the capture UI. Only called while the overlay is mounted.
  final WidgetBuilder overlayBuilder;

  /// Dark scrim (~92% opaque) so the page stays recognizable but never
  /// competes with the foreground text and pills.
  static const Color scrimColor = Color(0xEB070F18);
  static const double scrimAlpha = 0.92;
  static const Duration duration = Duration(milliseconds: 240);

  const CaptureOverlayHost({
    super.key,
    required this.page,
    required this.open,
    required this.overlayBuilder,
  });

  @override
  State<CaptureOverlayHost> createState() => _CaptureOverlayHostState();
}

class _CaptureOverlayHostState extends State<CaptureOverlayHost> {
  bool _mounted = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _mounted = widget.open;
    _shown = widget.open;
  }

  @override
  void didUpdateWidget(CaptureOverlayHost old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      // Mount first, then flip on the next frame so the fade-in actually runs.
      setState(() => _mounted = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) setState(() => _shown = true);
      });
    } else {
      setState(() => _shown = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: const ValueKey('capture_page'),
          child: widget.page,
        ),
        if (_mounted)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !widget.open,
              child: AnimatedOpacity(
                key: const ValueKey('capture_overlay_fade'),
                opacity: _shown ? 1.0 : 0.0,
                duration: CaptureOverlayHost.duration,
                curve: Curves.easeOutCubic,
                onEnd: () {
                  if (!_shown && mounted) setState(() => _mounted = false);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      key: const ValueKey('capture_scrim'),
                      color: CaptureOverlayHost.scrimColor,
                    ),
                    widget.overlayBuilder(context),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
