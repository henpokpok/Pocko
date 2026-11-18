import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// How long every toast stays on screen. It is enforced by an explicit
/// [Timer], so it holds even when an action button is shown (Flutter's own
/// `SnackBar` keeps action snacks around until dismissed).
const Duration kPockoToastDuration = Duration(seconds: 5);

enum PockoToastKind { success, info, error }

/// The toast currently on screen. Only one is ever shown: a new one replaces
/// the old one so rapid actions never queue up.
_ToastHandle? _current;

class _ToastHandle {
  final OverlayEntry entry;
  final VoidCallback dismiss;
  _ToastHandle(this.entry, this.dismiss);
}

/// Dismisses the toast that is currently showing, if any.
void hidePockoToast() {
  final h = _current;
  _current = null;
  h?.dismiss();
}

/// A sleek floating pill card:
/// * a status / category icon in a pastel circle,
/// * a bold [message] with an optional helpful [detail] subtitle,
/// * an optional [actionLabel] chip (e.g. `Undo`),
/// * a progress bar that shrinks over 5 seconds, after which the toast always
///   dismisses itself.
///
/// It lives in the root [Overlay], so it survives route pops and the
/// disposal of the widget that raised it.
void showPockoToast(
  BuildContext context, {
  required String message,
  String? detail,
  IconData? icon,
  PockoToastKind kind = PockoToastKind.success,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = kPockoToastDuration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  hidePockoToast();

  late final OverlayEntry entry;
  final key = GlobalKey<_PockoToastCardState>();
  entry = OverlayEntry(
    builder: (ctx) => _PockoToastCard(
      key: key,
      message: message,
      detail: detail,
      icon: icon,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      onGone: () {
        if (entry.mounted) entry.remove();
        entry.dispose();
        if (_current?.entry == entry) _current = null;
      },
    ),
  );
  _current = _ToastHandle(entry, () => key.currentState?.dismiss());
  overlay.insert(entry);
}

class _PockoToastCard extends StatefulWidget {
  final String message;
  final String? detail;
  final IconData? icon;
  final PockoToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;

  const _PockoToastCard({
    super.key,
    required this.message,
    required this.detail,
    required this.icon,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onGone,
  });

  @override
  State<_PockoToastCard> createState() => _PockoToastCardState();
}

class _PockoToastCardState extends State<_PockoToastCard>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _progress;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    // The shrinking bar is purely visual...
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    // ...the dismissal is guaranteed by this explicit timer.
    _timer = Timer(widget.duration, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) {
      try {
        await _enter.reverse();
      } catch (_) {}
    }
    widget.onGone();
  }

  ({Color tint, Color accent, IconData icon}) get _look {
    switch (widget.kind) {
      case PockoToastKind.error:
        return (
          tint: const Color(0xFFFFE4E1),
          accent: AppTheme.coralOwesText,
          icon: widget.icon ?? Icons.error_rounded,
        );
      case PockoToastKind.info:
        return (
          tint: const Color(0xFFDCF0FF),
          accent: const Color(0xFF3B82F6),
          icon: widget.icon ?? Icons.info_rounded,
        );
      case PockoToastKind.success:
        return (
          tint: AppTheme.primaryEmeraldLight,
          accent: AppTheme.primaryEmeraldDark,
          icon: widget.icon ?? Icons.check_circle_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 768;
    final look = _look;
    final curved = CurvedAnimation(
      parent: _enter,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      left: 16,
      right: 16,
      bottom: (wide ? 16.0 : 96.0) + media.viewInsets.bottom,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(curved),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    key: const ValueKey('pocko_toast'),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppTheme.textDark,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 22,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Row(
                            children: [
                              Container(
                                key: const ValueKey('toast_icon'),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: look.tint,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  look.icon,
                                  size: 20,
                                  color: look.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.message,
                                      key: const ValueKey('toast_message'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (widget.detail != null &&
                                        widget.detail!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          widget.detail!,
                                          key: const ValueKey('toast_detail'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.actionLabel != null &&
                                  widget.onAction != null) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  key: const ValueKey('toast_action'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    widget.onAction!();
                                    dismiss();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryEmerald,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      widget.actionLabel!,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Shrinking time bar: full at the start, empty after 5 s.
                        AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: (1 - _progress.value).clamp(
                                0.0,
                                1.0,
                              ),
                              child: Container(
                                key: const ValueKey('toast_progress'),
                                height: 3,
                                color:
                                    look.accent == AppTheme.primaryEmeraldDark
                                    ? AppTheme.primaryEmerald
                                    : look.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
