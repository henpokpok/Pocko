import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pocko_mascot.dart';

/// Which of the three landing illustrations to show.
enum StoryScene { cafe, slipMatch, privacyShield }

/// Landing illustration: a rounded card with a painted background, layered
/// UI cards and a large Pocko. All motion comes from one looping controller and
/// plain `CustomPainter`s (no blur filters), so it stays at 60 fps.
class StoryIllustration extends StatelessWidget {
  final StoryScene scene;
  final double height;

  /// Looping animation on/off (off for static layout checks).
  final bool animate;

  const StoryIllustration({
    super.key,
    required this.scene,
    this.height = 250,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: SizedBox(
        key: ValueKey('scene_${scene.name}'),
        height: height,
        width: double.infinity,
        // Its own repaint boundary: the looping scene repaints only itself, and
        // a swipe moves it as one cached texture.
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: switch (scene) {
              StoryScene.cafe => _CafeScene(animate: animate),
              StoryScene.slipMatch => _SlipMatchScene(animate: animate),
              StoryScene.privacyShield => _PrivacyScene(animate: animate),
            },
          ),
        ),
      ),
    );
  }
}

/// Shared looping clock for the scenes.
mixin _Looping<T extends StatefulWidget>
    on State<T>, TickerProviderStateMixin<T> {
  late final AnimationController clock;

  Duration get loopDuration;
  bool get shouldAnimate;

  @override
  void initState() {
    super.initState();
    clock = AnimationController(vsync: this, duration: loopDuration);
    if (shouldAnimate) {
      clock.repeat();
    } else {
      clock.value = 0.92; // a pleasant, "finished" frame
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }
}

double _seg(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

TextStyle _t(double size, FontWeight w, Color c) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c);

/// Text that shrinks instead of overflowing (scenes must fit any phone).
Widget _fit(
  String text,
  TextStyle style, {
  Alignment alignment = Alignment.centerLeft,
}) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: Text(text, style: style, maxLines: 1),
  );
}

// =============================================================================
// Scene 1: log live at a café / market stall, offline, in 3 seconds
// =============================================================================

class _CafeScene extends StatefulWidget {
  final bool animate;
  const _CafeScene({required this.animate});

  @override
  State<_CafeScene> createState() => _CafeSceneState();
}

class _CafeSceneState extends State<_CafeScene>
    with TickerProviderStateMixin, _Looping<_CafeScene> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 4600);
  @override
  bool get shouldAnimate => widget.animate;

  static const String _sentence = 'Ramen 1,200 yen with Maya';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final pocko = math.min(h * 0.62, 150.0);
        return AnimatedBuilder(
          animation: clock,
          builder: (context, _) {
            final t = clock.value;
            final typed = _seg(t, 0.12, 0.62);
            final chars = (_sentence.length * typed).floor();
            final done = _seg(t, 0.66, 0.78);
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _CafePainter(t)),
                // Offline badge.
                Positioned(
                  left: 14,
                  top: h * 0.27,
                  child: Container(
                    key: const ValueKey('scene_offline_chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          size: 14,
                          color: Color(0xFFB45309),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Offline',
                          style: _t(
                            11,
                            FontWeight.w800,
                            const Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Pocko listening, big.
                Positioned(
                  left: 4,
                  bottom: 8,
                  child: PockoMascot(
                    mood: PockoMood.listening,
                    size: pocko,
                    voiceLevel: typed > 0 && typed < 1
                        ? 0.35 + 0.35 * math.sin(t * math.pi * 14).abs()
                        : 0,
                  ),
                ),
                // Speech bubble: waveform -> typed bill -> "in 3s".
                Positioned(
                  right: 12,
                  top: h * 0.2,
                  width: w * 0.56,
                  child: Container(
                    key: const ValueKey('scene_bubble'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 18,
                          child: Row(
                            children: [
                              for (var i = 0; i < 9; i++)
                                Container(
                                  width: 4,
                                  margin: const EdgeInsets.only(right: 3),
                                  height:
                                      4 +
                                      14 *
                                          (typed <= 0 || typed >= 1
                                                  ? 0.25
                                                  : (0.5 +
                                                        0.5 *
                                                            math.sin(
                                                              t * 22 + i * 1.3,
                                                            )))
                                              .abs(),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryEmerald,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        _fit(
                          '${_sentence.substring(0, chars)}${typed < 1 ? '▌' : ''}',
                          _t(13, FontWeight.w800, AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: done,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryEmeraldLight,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: _fit(
                              '✓ Logged in 3s',
                              _t(
                                11.5,
                                FontWeight.w900,
                                AppTheme.primaryEmeraldDark,
                              ),
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CafePainter extends CustomPainter {
  final double t;
  _CafePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm morning sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9D6), Color(0xFFFFF7EC)],
        ).createShader(Offset.zero & size),
    );

    // Sun.
    canvas.drawCircle(
      Offset(w * 0.86, h * 0.34),
      h * 0.09,
      Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 0.9),
    );

    // Market stalls in the back.
    final stall = Paint()..color = const Color(0xFFFBD5C0);
    for (var i = 0; i < 3; i++) {
      final x = w * (0.08 + i * 0.33);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h * 0.46, w * 0.24, h * 0.3),
          const Radius.circular(8),
        ),
        stall,
      );
    }

    // Striped scalloped awning.
    final awningH = h * 0.17;
    const stripes = 9;
    final sw = w / stripes;
    for (var i = 0; i < stripes; i++) {
      final paint = Paint()
        ..color = i.isEven ? const Color(0xFFFB7185) : const Color(0xFFFFFFFF);
      canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw + 0.5, awningH), paint);
      canvas.drawArc(
        Rect.fromLTWH(i * sw, awningH - sw / 2, sw + 0.5, sw),
        0,
        math.pi,
        true,
        paint,
      );
    }

    // String lights swaying.
    final lightLine = Paint()
      ..color = const Color(0x55B45309)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..moveTo(0, awningH + sw * 0.7);
    path.quadraticBezierTo(
      w / 2,
      awningH + sw * 0.7 + 18,
      w,
      awningH + sw * 0.7,
    );
    canvas.drawPath(path, lightLine);
    for (var i = 1; i < 8; i++) {
      final x = w * i / 8;
      final sag = 18 * (1 - math.pow((x - w / 2) / (w / 2), 2));
      final glow = 0.55 + 0.45 * math.sin(t * math.pi * 2 + i);
      canvas.drawCircle(
        Offset(x, awningH + sw * 0.7 + sag * 0.5 + 3),
        3.2,
        Paint()..color = const Color(0xFFFFC857).withValues(alpha: glow),
      );
    }

    // Wooden counter with a bowl and a cup.
    final counterTop = h * 0.8;
    canvas.drawRect(
      Rect.fromLTWH(0, counterTop, w, h - counterTop),
      Paint()..color = const Color(0xFFE9C9A0),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, counterTop, w, 5),
      Paint()..color = const Color(0xFFD7AE7C),
    );
    // Ramen bowl.
    final bowlC = Offset(w * 0.5, counterTop - 2);
    canvas.drawArc(
      Rect.fromCenter(center: bowlC, width: 44, height: 30),
      0,
      math.pi,
      true,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawArc(
      Rect.fromCenter(center: bowlC, width: 44, height: 30),
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFFFB7185)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    // Steam.
    for (var i = 0; i < 3; i++) {
      final sx = bowlC.dx - 10 + i * 10;
      final lift = ((t * 2 + i * 0.3) % 1.0);
      canvas.drawCircle(
        Offset(sx, bowlC.dy - 8 - lift * 20),
        2.2 + lift * 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.8 * (1 - lift)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CafePainter old) => old.t != t;
}

// =============================================================================
// Scene 2: a bank transfer slip snaps onto the waiting expense
// =============================================================================

class _SlipMatchScene extends StatefulWidget {
  final bool animate;
  const _SlipMatchScene({required this.animate});

  @override
  State<_SlipMatchScene> createState() => _SlipMatchSceneState();
}

class _SlipMatchSceneState extends State<_SlipMatchScene>
    with TickerProviderStateMixin, _Looping<_SlipMatchScene> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 5200);
  @override
  bool get shouldAnimate => widget.animate;

  static const _rows = [
    ('Ramen', '¥1,200'),
    ('Taxi', '¥800'),
    ('Museum', '¥2,400'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final narrow = w < 300; // 320 px phones
        final cardW = w * (narrow ? 0.54 : 0.46);
        final cardH = math.min(48.0, h * 0.2);
        // The slip docks beside the card so the amount stays readable.
        final dockX = w * (narrow ? 0.58 : 0.51);
        final slipW = w * (narrow ? 0.38 : 0.43);
        const gap = 10.0;
        final top0 = h * 0.14;
        const targetIndex = 1;
        final targetY = top0 + targetIndex * (cardH + gap);
        final pocko = math.min(h * 0.5, 124.0);

        return AnimatedBuilder(
          animation: clock,
          builder: (context, _) {
            final t = clock.value;
            final fly = Curves.easeInOutCubic.transform(_seg(t, 0.1, 0.55));
            final matched = t >= 0.55;
            // Slip travels from the top-right to dock on the Taxi card.
            final slipStart = Offset(w * 0.5, h * 0.02);
            final slipEnd = Offset(dockX, targetY + 2);
            final slip = Offset.lerp(slipStart, slipEnd, fly)!;
            final tilt = (1 - fly) * 0.18;
            final snap = _seg(t, 0.55, 0.7);
            final pulse = matched ? 1 + 0.06 * math.sin(snap * math.pi) : 1.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _LedgerPainter(
                    t,
                    targetY + cardH / 2,
                    w * 0.18 + cardW,
                  ),
                ),
                for (var i = 0; i < _rows.length; i++)
                  Positioned(
                    left: 14,
                    top: top0 + i * (cardH + gap),
                    width: cardW,
                    height: cardH,
                    child: _ExpenseRow(
                      key: ValueKey('scene_row_$i'),
                      title: _rows[i].$1,
                      amount: _rows[i].$2,
                      matched: i == targetIndex && matched,
                    ),
                  ),
                // The bank slip.
                Positioned(
                  left: slip.dx,
                  top: slip.dy,
                  width: slipW,
                  height: cardH + 10,
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: pulse,
                      child: _BankSlip(
                        key: const ValueKey('scene_slip'),
                        docked: matched,
                      ),
                    ),
                  ),
                ),
                // "Matched!" burst ring on the docking point.
                if (snap > 0 && snap < 1)
                  Positioned(
                    left: dockX + slipW / 2 - 30,
                    top: targetY + cardH / 2 - 30,
                    width: 60,
                    height: 60,
                    child: CustomPaint(painter: _RingPainter(snap)),
                  ),
                Positioned(
                  right: 2,
                  bottom: 4,
                  child: PockoMascot(mood: PockoMood.scanning, size: pocko),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final String title;
  final String amount;
  final bool matched;
  const _ExpenseRow({
    super.key,
    required this.title,
    required this.amount,
    required this.matched,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: matched ? AppTheme.primaryEmerald : AppTheme.borderColor,
          width: matched ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: matched
                  ? AppTheme.primaryEmeraldLight
                  : const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              matched ? Icons.check_rounded : Icons.hourglass_top_rounded,
              size: 14,
              color: matched
                  ? AppTheme.primaryEmeraldDark
                  : const Color(0xFFB45309),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fit(title, _t(12.5, FontWeight.w800, AppTheme.textDark)),
                _fit(
                  matched ? 'Matched' : 'Waiting for slip',
                  _t(
                    9.5,
                    FontWeight.w700,
                    matched
                        ? AppTheme.primaryEmeraldDark
                        : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 58),
            child: _fit(
              amount,
              _t(12.5, FontWeight.w900, AppTheme.textDark),
              alignment: Alignment.centerRight,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankSlip extends StatelessWidget {
  final bool docked;
  const _BankSlip({super.key, required this.docked});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SlipPainter(docked),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fit(
              'TRANSFER ¥800',
              _t(11, FontWeight.w900, const Color(0xFF1E3A8A)),
            ),
            _fit('•••• 4829', _t(10, FontWeight.w700, const Color(0xFF475569))),
          ],
        ),
      ),
    );
  }
}

class _SlipPainter extends CustomPainter {
  final bool docked;
  _SlipPainter(this.docked);

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 2)),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFFEFF6FF));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = docked ? 2 : 1.2
        ..color = docked ? AppTheme.primaryEmerald : const Color(0xFF93C5FD),
    );
    // Perforated bottom edge.
    final dot = Paint()..color = const Color(0xFFBFDBFE);
    for (var x = 6.0; x < size.width - 4; x += 9) {
      canvas.drawCircle(Offset(x, size.height - 3), 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SlipPainter old) => old.docked != docked;
}

class _LedgerPainter extends CustomPainter {
  final double t;
  final double y;
  final double x;
  _LedgerPainter(this.t, this.y, this.x);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD6F5E6), Color(0xFFDDEBFF)],
        ).createShader(Offset.zero & size),
    );
    // Faint ledger lines.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var yy = 24.0; yy < size.height; yy += 26) {
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), line);
    }
    // Dashed guide from the slip's origin to the target card.
    final dash = Paint()
      ..color = AppTheme.primaryEmerald.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.72, 10)
      ..quadraticBezierTo(size.width * 0.9, y * 0.7, x - 6, y);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), dash);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerPainter old) =>
      old.t != t || old.y != y || old.x != x;
}

class _RingPainter extends CustomPainter {
  final double p;
  _RingPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      8 + 22 * Curves.easeOutCubic.transform(p),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - p) + 1
        ..color = AppTheme.primaryEmerald.withValues(alpha: 0.9 * (1 - p)),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p;
}

// =============================================================================
// Scene 3: the privacy shield masks card digits on the device
// =============================================================================

class _PrivacyScene extends StatefulWidget {
  final bool animate;
  const _PrivacyScene({required this.animate});

  @override
  State<_PrivacyScene> createState() => _PrivacySceneState();
}

class _PrivacySceneState extends State<_PrivacyScene>
    with TickerProviderStateMixin, _Looping<_PrivacyScene> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 5200);
  @override
  bool get shouldAnimate => widget.animate;

  static const _groups = ['4539', '1127', '5821'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final cardW = w * 0.78;
        final cardH = math.min(h * 0.42, 118.0);
        final pocko = math.min(h * 0.5, 128.0);

        return AnimatedBuilder(
          animation: clock,
          builder: (context, _) {
            final t = clock.value;
            // The shield's scan beam sweeps across the card and masks digits.
            final sweep = _seg(t, 0.12, 0.62);
            final glow = 0.5 + 0.5 * math.sin(t * math.pi * 2);
            final cardX = (w - cardW) / 2;
            final cardY = h * 0.1;

            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _ShieldBackdropPainter(glow)),
                Positioned(
                  left: cardX,
                  top: cardY,
                  width: cardW,
                  height: cardH,
                  child: Container(
                    key: const ValueKey('scene_card'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.contactless_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const Spacer(),
                            _fit(
                              'BANK CARD',
                              _t(9.5, FontWeight.w800, const Color(0xFF94A3B8)),
                              alignment: Alignment.centerRight,
                            ),
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < _groups.length; i++) ...[
                                _DigitGroup(
                                  key: ValueKey('scene_digits_$i'),
                                  digits: _groups[i],
                                  masked: sweep > (i + 0.5) / 4,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Text(
                                '4829',
                                key: const ValueKey('scene_last4'),
                                style: _t(
                                  17,
                                  FontWeight.w900,
                                  const Color(0xFF6EE7B7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              size: 12,
                              color: Color(0xFF6EE7B7),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _fit(
                                sweep >= 0.85
                                    ? 'Masked on this device'
                                    : 'Scanning…',
                                _t(
                                  10,
                                  FontWeight.w800,
                                  const Color(0xFFA7F3D0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Scan beam.
                Positioned(
                  left: cardX + (cardW - 6) * sweep,
                  top: cardY - 6,
                  width: 6,
                  height: cardH + 12,
                  child: Opacity(
                    opacity: sweep > 0 && sweep < 1 ? 1 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryEmerald.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                // Glowing emerald shield with a check.
                Positioned(
                  // Below the digits (overlapping only the card's bottom edge).
                  right: w * 0.06,
                  top: cardY + cardH * 0.9,
                  child: SizedBox(
                    key: const ValueKey('scene_shield'),
                    width: 78,
                    height: 90,
                    child: CustomPaint(painter: _ShieldPainter(glow)),
                  ),
                ),
                // Synced copy: only the masked number leaves the phone.
                Positioned(
                  left: w * 0.34,
                  bottom: 12,
                  right: w * 0.3,
                  child: Container(
                    key: const ValueKey('scene_sync_chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_done_rounded,
                          size: 15,
                          color: AppTheme.primaryEmeraldDark,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _fit(
                            'Syncs •••• 4829 only',
                            _t(
                              10.5,
                              FontWeight.w900,
                              AppTheme.primaryEmeraldDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 2,
                  child: PockoMascot(size: pocko),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DigitGroup extends StatelessWidget {
  final String digits;
  final bool masked;
  const _DigitGroup({super.key, required this.digits, required this.masked});

  @override
  Widget build(BuildContext context) {
    return Text(
      masked ? '••••' : digits,
      style: _t(
        17,
        FontWeight.w800,
        masked ? Colors.white.withValues(alpha: 0.9) : const Color(0xFFCBD5E1),
      ),
    );
  }
}

class _ShieldBackdropPainter extends CustomPainter {
  final double glow;
  _ShieldBackdropPainter(this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B3B36), Color(0xFF0F5E50)],
        ).createShader(Offset.zero & size),
    );
    // Soft concentric halos (plain translucent circles, no blur).
    final c = Offset(size.width * 0.8, size.height * 0.66);
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(
        c,
        size.height * (0.16 + i * 0.1) * (0.96 + 0.06 * glow),
        Paint()
          ..color = AppTheme.primaryEmerald.withValues(alpha: 0.07 * (4 - i)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShieldBackdropPainter old) => old.glow != glow;
}

class _ShieldPainter extends CustomPainter {
  final double glow;
  _ShieldPainter(this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.72, h * 0.1, w * 0.92, h * 0.12, w, h * 0.14)
      ..lineTo(w, h * 0.5)
      ..cubicTo(w, h * 0.78, w * 0.74, h * 0.92, w * 0.5, h)
      ..cubicTo(w * 0.26, h * 0.92, 0, h * 0.78, 0, h * 0.5)
      ..lineTo(0, h * 0.14)
      ..cubicTo(w * 0.08, h * 0.12, w * 0.28, h * 0.1, w * 0.5, 0)
      ..close();

    // Pulsing glow ring (stroke, not blur).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 + 5 * glow
        ..color = const Color(0xFF6EE7B7).withValues(alpha: 0.22 + 0.2 * glow),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6EE7B7), Color(0xFF10B981)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    // Check mark.
    final check = Path()
      ..moveTo(w * 0.28, h * 0.5)
      ..lineTo(w * 0.45, h * 0.66)
      ..lineTo(w * 0.74, h * 0.34);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter old) => old.glow != glow;
}
