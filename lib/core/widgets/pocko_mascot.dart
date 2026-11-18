import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum PockoMood {
  waving,
  listening,
  juggling,
  scanning,
  celebrating,

  /// Eyes closed with floating "z"s — used by empty states.
  sleepy,
}

/// The official vector-rendered animated mascot of Pocko.
///
/// * Blinks every few seconds and its gaze drifts, so it always feels alive.
/// * [voiceLevel] (0–1) makes the listening mouth and sound-wave rings react to
///   live microphone amplitude.
/// * Painted entirely with `CustomPainter` (no emoji glyphs or assets), wrapped in
///   a `RepaintBoundary` so animation stays smooth at 60 fps.
/// Responsive Pocko sizes shared by every screen, so the mascot stays large and
/// friendly without ever overflowing a 320 px phone.
class PockoSizes {
  PockoSizes._();

  /// Tab headers (Home, Expenses, Matcher, Settle, Group): 96–112 px.
  static double header(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.27).clamp(96.0, 112.0);

  /// Empty and celebration states: 140–160 px.
  static double hero(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.38).clamp(140.0, 160.0);
}

class PockoMascot extends StatefulWidget {
  final PockoMood mood;
  final double size;
  final bool animate;
  final bool enableEntranceAnimation;

  /// Microphone amplitude in `0..1` (listening mood only).
  final double voiceLevel;

  const PockoMascot({
    super.key,
    this.mood = PockoMood.waving,
    this.size = 80.0,
    this.animate = true,
    this.enableEntranceAnimation = false,
    this.voiceLevel = 0.0,
  });

  @override
  State<PockoMascot> createState() => _PockoMascotState();
}

class _PockoMascotState extends State<PockoMascot>
    with SingleTickerProviderStateMixin {
  // One long loop drives everything: motion repeats every 2.4 s (3 cycles) while
  // blinks land at irregular points of the 7.2 s loop.
  static const Duration _loop = Duration(milliseconds: 7200);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _loop);
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PockoMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _label(PockoMood mood) {
    switch (mood) {
      case PockoMood.waving:
        return 'Pocko the mascot waving hello';
      case PockoMood.listening:
        return 'Pocko listening with headphones';
      case PockoMood.juggling:
        return 'Pocko juggling while it thinks';
      case PockoMood.scanning:
        return 'Pocko scanning a receipt with a magnifying glass';
      case PockoMood.celebrating:
        return 'Pocko celebrating with sunglasses and confetti';
      case PockoMood.sleepy:
        return 'Pocko napping';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSize = widget.size;

    Widget mascot = Semantics(
      label: _label(widget.mood),
      image: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = widget.animate ? _controller.value : 0.0;
            return SizedBox(
              width: effectiveSize,
              height: effectiveSize,
              child: CustomPaint(
                size: Size(effectiveSize, effectiveSize),
                painter: PockoPainter(
                  mood: widget.mood,
                  animProgress: (t * 3) % 1.0,
                  blink: widget.animate ? PockoPainter.blinkAt(t) : 0.0,
                  gaze: widget.animate ? math.sin(t * 2 * math.pi * 2) : 0.0,
                  voiceLevel: widget.voiceLevel.clamp(0.0, 1.0),
                ),
              ),
            );
          },
        ),
      ),
    );

    if (widget.enableEntranceAnimation && widget.animate) {
      mascot = mascot
          .animate(key: ValueKey('${widget.mood}_${widget.size}'))
          .scale(
            duration: 350.ms,
            begin: const Offset(0.92, 0.92),
            end: const Offset(1.0, 1.0),
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 250.ms);
    }

    return mascot;
  }
}

class PockoPainter extends CustomPainter {
  final PockoMood mood;

  /// 0..1 loop of the primary motion (2.4 s).
  final double animProgress;

  /// 0 (eyes open) .. 1 (eyes closed).
  final double blink;

  /// -1..1 horizontal eye drift.
  final double gaze;

  /// 0..1 microphone amplitude.
  final double voiceLevel;

  PockoPainter({
    required this.mood,
    required this.animProgress,
    this.blink = 0.0,
    this.gaze = 0.0,
    this.voiceLevel = 0.0,
  });

  /// Two quick blinks per 7.2 s loop (~130 ms each).
  static double blinkAt(double t) {
    double bump(double center) {
      final d = (t - center).abs();
      const half = 0.009;
      return d >= half ? 0.0 : 1.0 - d / half;
    }

    return math.max(bump(0.29), bump(0.74));
  }

  static final Map<String, TextPainter> _textCache = {};

  static TextPainter _cachedText(String text, double fontSize, Color color) {
    final key = '$text|$fontSize|${color.toARGB32()}';
    return _textCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;
    canvas.save();
    canvas.scale(scale, scale);

    final wave = math.sin(animProgress * 2 * math.pi);

    // Floating bob + squash & stretch around the "feet" line.
    double bobOffsetY = 0.0;
    double squash = 0.0;
    switch (mood) {
      case PockoMood.waving:
      case PockoMood.celebrating:
        bobOffsetY = wave * 2.5;
        squash = wave * 0.012;
        break;
      case PockoMood.listening:
        bobOffsetY =
            math.sin(animProgress * 4 * math.pi) * (1.2 + voiceLevel * 1.6);
        squash = voiceLevel * 0.018 * math.sin(animProgress * 8 * math.pi);
        break;
      case PockoMood.juggling:
        bobOffsetY = math.sin(animProgress * 4 * math.pi) * 1.2;
        break;
      case PockoMood.scanning:
        bobOffsetY = wave * 1.2;
        break;
      case PockoMood.sleepy:
        bobOffsetY =
            math.sin(animProgress * 2 * math.pi) * 1.6; // slow breathing
        squash = wave * 0.018;
        break;
    }

    canvas.translate(0, bobOffsetY);

    if (mood == PockoMood.juggling) {
      _paintJugglingOrbit(canvas, 50, 52);
    }
    if (mood == PockoMood.listening) {
      _paintListeningRings(canvas, 50, 52);
    }

    // Squash & stretch pivot at the bottom of the body.
    canvas.save();
    canvas.translate(50, 88);
    canvas.scale(1 + squash, 1 - squash);
    canvas.translate(-50, -88);

    _paintFeet(canvas, 50, 88);
    _paintBody(canvas, 50, 56, 32);
    _paintBucketHat(canvas, 50, 30);
    _paintFace(canvas, 50, 58);
    if (mood != PockoMood.waving) _paintRestingArms(canvas, 50, 62);

    switch (mood) {
      case PockoMood.waving:
        _paintRestingArm(canvas, 22, 66, left: true);
        _paintWavingArm(canvas, 78, 52);
        break;
      case PockoMood.listening:
        _paintHeadphones(canvas, 50, 54);
        break;
      case PockoMood.juggling:
        _paintJugglingItems(canvas, 50, 52);
        break;
      case PockoMood.scanning:
        _paintScanningMagnifier(canvas, 68, 62);
        break;
      case PockoMood.celebrating:
        break;
      case PockoMood.sleepy:
        _paintSleepyZs(canvas, 74, 30);
        break;
    }
    canvas.restore();

    if (mood == PockoMood.celebrating) {
      _paintConfetti(canvas);
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Body parts
  // ---------------------------------------------------------------------------

  void _paintFeet(Canvas canvas, double cx, double baseY) {
    final footPaint = Paint()..color = const Color(0xFF34D399);
    final outline = Paint()
      ..color = const Color(0xFF059669)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final dx in [-12.0, 12.0]) {
      final rect = Rect.fromCenter(
        center: Offset(cx + dx, baseY),
        width: 13,
        height: 7,
      );
      canvas.drawOval(rect, footPaint);
      canvas.drawOval(rect, outline);
    }
  }

  void _paintBody(Canvas canvas, double cx, double cy, double radius) {
    // Soft ground shadow
    final shadowPaint = Paint()
      ..color = const Color(0x1F0F172A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + radius + 2),
        width: radius * 1.5,
        height: 6,
      ),
      shadowPaint,
    );

    // Coin Mochi Body with Mint Gradient
    final bodyRect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    final bodyPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.5),
        radius: 1.1,
        colors: [Color(0xFFA7F3D0), Color(0xFF6EE7B7), Color(0xFF34D399)],
        stops: [0.0, 0.45, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(Offset(cx, cy), radius, bodyPaint);

    // Outer subtle rim for coin edge
    final rimPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(cx, cy), radius - 1, rimPaint);

    // Inner glowing rim
    final innerRimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(Offset(cx, cy), radius - 4, innerRimPaint);

    // Specular highlight
    final glossPaint = Paint()..color = Colors.white.withValues(alpha: 0.28);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 14, cy - 8), width: 10, height: 6),
      glossPaint,
    );
  }

  void _paintBucketHat(Canvas canvas, double cx, double cy) {
    final hatDomePath = Path()
      ..moveTo(cx - 18, cy + 8)
      ..cubicTo(cx - 19, cy - 8, cx - 12, cy - 14, cx, cy - 14)
      ..cubicTo(cx + 12, cy - 14, cx + 19, cy - 8, cx + 18, cy + 8)
      ..close();
    canvas.drawPath(hatDomePath, Paint()..color = const Color(0xFFFDE047));

    // Dome highlight
    canvas.drawPath(
      Path()
        ..moveTo(cx - 12, cy - 4)
        ..quadraticBezierTo(cx - 10, cy - 11, cx - 3, cy - 12),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Hat Ribbon Band (Teal Mint)
    final bandPath = Path()
      ..moveTo(cx - 18, cy + 5)
      ..lineTo(cx + 18, cy + 5)
      ..lineTo(cx + 19, cy + 9)
      ..lineTo(cx - 19, cy + 9)
      ..close();
    canvas.drawPath(bandPath, Paint()..color = const Color(0xFF0D9488));

    // Bucket Hat Brim
    final brimRect = Rect.fromCenter(
      center: Offset(cx, cy + 10),
      width: 48,
      height: 12,
    );
    canvas.drawOval(brimRect, Paint()..color = const Color(0xFFFACC15));
    canvas.drawOval(
      brimRect,
      Paint()
        ..color = const Color(0xFFCA8A04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _paintFace(Canvas canvas, double cx, double cy) {
    final eyePaint = Paint()..color = const Color(0xFF0F172A);
    final shinePaint = Paint()..color = Colors.white;
    final drift = gaze * 1.4;

    if (mood == PockoMood.celebrating) {
      _paintSunglasses(canvas, cx, cy - 3);
    } else if (mood == PockoMood.sleepy || blink > 0.85) {
      // Closed eyes: gentle downward arcs
      final lid = Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (final dx in [-11.0, 11.0]) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx + dx, cy - 4), width: 8, height: 6),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          lid,
        );
      }
    } else {
      final open = (1.0 - blink).clamp(0.12, 1.0);
      final baseH = mood == PockoMood.listening ? 9.0 : 8.0;
      final squint = mood == PockoMood.scanning ? 0.62 : 1.0;

      for (final side in [-1.0, 1.0]) {
        final isRight = side > 0;
        final h = baseH * open * (isRight ? squint : 1.0);
        final center = Offset(cx + side * 11 + drift, cy - 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 6, height: h),
            const Radius.circular(3),
          ),
          eyePaint,
        );
        if (open > 0.5) {
          canvas.drawCircle(
            center.translate(-1 + drift * 0.2, -h * 0.28),
            1.8,
            shinePaint,
          );
          canvas.drawCircle(
            center.translate(1 + drift * 0.2, h * 0.22),
            0.9,
            shinePaint,
          );
        }
      }

      // Little eyebrows add expression
      final brow = Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      if (mood == PockoMood.listening) {
        // Raised, attentive brows that lift with the voice
        final lift = voiceLevel * 1.5;
        canvas.drawLine(
          Offset(cx - 14, cy - 12 - lift),
          Offset(cx - 8, cy - 13 - lift),
          brow,
        );
        canvas.drawLine(
          Offset(cx + 8, cy - 13 - lift),
          Offset(cx + 14, cy - 12 - lift),
          brow,
        );
      } else if (mood == PockoMood.scanning) {
        canvas.drawLine(
          Offset(cx + 8, cy - 11),
          Offset(cx + 14, cy - 13),
          brow,
        );
      } else if (mood == PockoMood.juggling) {
        canvas.drawLine(
          Offset(cx - 14, cy - 11),
          Offset(cx - 8, cy - 12.5),
          brow,
        );
        canvas.drawLine(
          Offset(cx + 8, cy - 12.5),
          Offset(cx + 14, cy - 11),
          brow,
        );
      }
    }

    // Rosy Blushing Cheeks
    final cheekPaint = Paint()
      ..color = const Color(0xFFFCA5A5).withValues(alpha: 0.75);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 16, cy + 4), width: 8, height: 5),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 16, cy + 4), width: 8, height: 5),
      cheekPaint,
    );

    _paintMouth(canvas, cx, cy);
  }

  void _paintMouth(Canvas canvas, double cx, double cy) {
    final mouthStroke = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case PockoMood.listening:
        // Small "o" that opens with the voice
        final h = 3.0 + voiceLevel * 5.0;
        final rect = Rect.fromCenter(
          center: Offset(cx, cy + 5),
          width: 5 + voiceLevel * 2,
          height: h,
        );
        canvas.drawOval(rect, Paint()..color = const Color(0xFF7F1D1D));
        canvas.drawOval(rect, mouthStroke..strokeWidth = 1.2);
        return;
      case PockoMood.celebrating:
        // Big open grin
        final grin = Path()
          ..moveTo(cx - 7, cy + 2.5)
          ..quadraticBezierTo(cx, cy + 12, cx + 7, cy + 2.5)
          ..close();
        canvas.drawPath(grin, Paint()..color = const Color(0xFF7F1D1D));
        canvas.drawPath(
          Path()
            ..moveTo(cx - 3.5, cy + 8)
            ..quadraticBezierTo(cx, cy + 5.5, cx + 3.5, cy + 8)
            ..close(),
          Paint()..color = const Color(0xFFFCA5A5),
        );
        canvas.drawPath(grin, mouthStroke..strokeWidth = 1.3);
        return;
      case PockoMood.juggling:
        // Concentrating wiggle
        final wob = math.sin(animProgress * 8 * math.pi) * 0.8;
        canvas.drawLine(
          Offset(cx - 4, cy + 4.5 + wob),
          Offset(cx + 4, cy + 4.5 - wob),
          mouthStroke,
        );
        return;
      case PockoMood.sleepy:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy + 5), width: 3.5, height: 2.6),
          Paint()..color = const Color(0xFF0F172A),
        );
        return;
      case PockoMood.scanning:
      case PockoMood.waving:
        // Tiny :3 cat mouth
        final mouthPath = Path()
          ..moveTo(cx - 5.5, cy + 2.5)
          ..quadraticBezierTo(cx - 2.8, cy + 6.2, cx, cy + 3.2)
          ..quadraticBezierTo(cx + 2.8, cy + 6.2, cx + 5.5, cy + 2.5);
        canvas.drawPath(mouthPath, mouthStroke);
        return;
    }
  }

  void _paintSunglasses(Canvas canvas, double cx, double cy) {
    final glassesPaint = Paint()..color = const Color(0xFF1E293B);
    final framePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final dx in [-11.0, 11.0]) {
      final lens = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + dx, cy), width: 14, height: 10),
        const Radius.circular(4),
      );
      canvas.drawRRect(lens, glassesPaint);
      canvas.drawRRect(lens, framePaint);
    }

    canvas.drawLine(
      Offset(cx - 4, cy - 2),
      Offset(cx + 4, cy - 2),
      Paint()
        ..color = const Color(0xFF0F172A)
        ..strokeWidth = 2.0,
    );

    // Animated glare sweeping across the lenses
    final sweep = (animProgress * 1.4) % 1.0;
    final glareX = -6 + sweep * 12;
    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - 11 + glareX - 2, cy + 2),
      Offset(cx - 11 + glareX + 2, cy - 3),
      sheenPaint,
    );
    canvas.drawLine(
      Offset(cx + 11 + glareX - 2, cy + 2),
      Offset(cx + 11 + glareX + 2, cy - 3),
      sheenPaint,
    );
  }

  void _paintRestingArms(Canvas canvas, double cx, double cy) {
    _paintRestingArm(canvas, cx - 28, cy + 4, left: true);
    _paintRestingArm(canvas, cx + 28, cy + 4, left: false);
  }

  void _paintRestingArm(
    Canvas canvas,
    double x,
    double y, {
    required bool left,
  }) {
    final armPaint = Paint()..color = const Color(0xFF34D399);
    final outline = Paint()
      ..color = const Color(0xFF059669)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(left ? 0.35 : -0.35);
    final rect = Rect.fromCenter(center: Offset.zero, width: 7, height: 12);
    canvas.drawOval(rect, armPaint);
    canvas.drawOval(rect, outline);
    canvas.restore();
  }

  void _paintWavingArm(Canvas canvas, double anchorX, double anchorY) {
    final waveAngle = math.sin(animProgress * 2 * math.pi * 3) * 0.35;
    canvas.save();
    canvas.translate(anchorX, anchorY);
    canvas.rotate(waveAngle);

    final armPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(8, -6, 12, -2)
      ..quadraticBezierTo(14, 4, 6, 6)
      ..close();
    canvas.drawPath(armPath, Paint()..color = const Color(0xFF34D399));
    canvas.drawPath(
      armPath,
      Paint()
        ..color = const Color(0xFF059669)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  void _paintHeadphones(Canvas canvas, double cx, double cy) {
    final bandPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final bandPath = Path()
      ..moveTo(cx - 28, cy - 2)
      ..cubicTo(cx - 28, cy - 36, cx + 28, cy - 36, cx + 28, cy - 2);
    canvas.drawPath(bandPath, bandPaint);

    final cupPaint = Paint()..color = const Color(0xFF0EA5E9);
    final earPaddingPaint = Paint()..color = Colors.white;
    for (final side in [-1.0, 1.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + side * 29, cy - 2),
            width: 8,
            height: 16,
          ),
          const Radius.circular(4),
        ),
        cupPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + side * 26, cy - 2),
            width: 3,
            height: 12,
          ),
          const Radius.circular(2),
        ),
        earPaddingPaint,
      );
    }
  }

  void _paintListeningRings(Canvas canvas, double cx, double cy) {
    final energy = 0.55 + voiceLevel * 0.9;
    for (int i = 0; i < 3; i++) {
      final ringProgress = (animProgress + (i * 0.33)) % 1.0;
      final radius = 34 + (ringProgress * 15 * energy);
      final alpha =
          (1.0 - ringProgress).clamp(0.0, 1.0) * (0.28 + voiceLevel * 0.35);

      final wavePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(Offset(cx, cy), radius, wavePaint);
    }
  }

  void _paintJugglingOrbit(Canvas canvas, double cx, double cy) {
    const orbitRadius = 42.0;
    final orbitPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    const totalDots = 24;
    for (int i = 0; i < totalDots; i++) {
      final angle = (i / totalDots) * 2 * math.pi;
      final dx = cx + math.cos(angle) * orbitRadius;
      final dy = cy + math.sin(angle) * (orbitRadius * 0.7);
      canvas.drawCircle(Offset(dx, dy), 1.0, orbitPaint);
    }
  }

  void _paintJugglingItems(Canvas canvas, double cx, double cy) {
    const orbitRadius = 42.0;
    const colors = [
      Color(0xFFFDE68A),
      Color(0xFFBAE6FD),
      Color(0xFFD2F8E5),
      Color(0xFFFED7AA),
    ];

    // Back items first (sin < 0) so front items overlap Pocko with depth.
    final order = List<int>.generate(4, (i) => i)
      ..sort((a, b) {
        double depth(int i) =>
            math.sin((i / 4) * 2 * math.pi + animProgress * 2 * math.pi);
        return depth(a).compareTo(depth(b));
      });

    for (final i in order) {
      final currentAngle = (i / 4) * 2 * math.pi + animProgress * 2 * math.pi;
      final dx = cx + math.cos(currentAngle) * orbitRadius;
      final dy = cy + math.sin(currentAngle) * (orbitRadius * 0.7);
      final depth = math.sin(currentAngle); // -1 back .. 1 front
      final scale = 0.86 + 0.18 * depth;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale, scale);
      canvas.drawCircle(Offset.zero, 8.5, Paint()..color = colors[i]);
      canvas.drawCircle(
        Offset.zero,
        8.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      switch (i) {
        case 0:
          _paintBowl(canvas);
          break;
        case 1:
          _paintTrain(canvas);
          break;
        case 2:
          final tp = _cachedText('¥', 11, const Color(0xFF047857));
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          break;
        default:
          _paintSparkle(canvas);
      }
      canvas.restore();
    }
  }

  void _paintBowl(Canvas canvas) {
    final bowl = Path()
      ..moveTo(-5, -0.5)
      ..quadraticBezierTo(0, 7, 5, -0.5)
      ..close();
    canvas.drawPath(bowl, Paint()..color = const Color(0xFFEA580C));
    canvas.drawLine(
      const Offset(-4, -1),
      const Offset(4, -1),
      Paint()
        ..color = const Color(0xFFFFF7ED)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    final chop = Paint()
      ..color = const Color(0xFF78350F)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(1, -2), const Offset(5, -6), chop);
    canvas.drawLine(const Offset(2.2, -1.6), const Offset(6, -5), chop);
  }

  void _paintTrain(Canvas canvas) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 0), width: 11, height: 7.5),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF0369A1));
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -0.8), width: 7.5, height: 2.4),
      Paint()..color = const Color(0xFFE0F2FE),
    );
    canvas.drawCircle(
      const Offset(-2.6, 2.2),
      0.8,
      Paint()..color = const Color(0xFFFDE047),
    );
    canvas.drawCircle(
      const Offset(2.6, 2.2),
      0.8,
      Paint()..color = const Color(0xFFFDE047),
    );
  }

  void _paintSparkle(Canvas canvas) {
    final path = Path()
      ..moveTo(0, -6)
      ..quadraticBezierTo(0.8, -0.8, 6, 0)
      ..quadraticBezierTo(0.8, 0.8, 0, 6)
      ..quadraticBezierTo(-0.8, 0.8, -6, 0)
      ..quadraticBezierTo(-0.8, -0.8, 0, -6)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFF59E0B));
  }

  void _paintScanningMagnifier(Canvas canvas, double cx, double cy) {
    final sweepAngle = math.sin(animProgress * 2 * math.pi) * 0.35;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(sweepAngle);

    final beamPath = Path()
      ..moveTo(0, 0)
      ..lineTo(-24, 20)
      ..lineTo(-10, 26)
      ..close();

    final beamPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.38),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 28));
    canvas.drawPath(beamPath, beamPaint);

    canvas.drawCircle(
      Offset.zero,
      8,
      Paint()
        ..color = const Color(0xFFD2F8E5).withValues(alpha: 0.7)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      8,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 5),
      -math.pi * 0.7,
      math.pi * 0.6,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    canvas.drawLine(
      const Offset(6, 6),
      const Offset(14, 14),
      Paint()
        ..color = const Color(0xFF78350F)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  void _paintSleepyZs(Canvas canvas, double x, double y) {
    for (int i = 0; i < 3; i++) {
      final p = (animProgress + i * 0.33) % 1.0;
      final tp = _cachedText(
        'z',
        9.0 + i * 2.0,
        const Color(0xFF64748B).withValues(alpha: 0.9),
      );
      canvas.save();
      canvas.translate(x + i * 5 + p * 5, y - p * 16 - i * 4);
      canvas.saveLayer(
        Rect.fromLTWH(-2, -2, tp.width + 4, tp.height + 4),
        Paint()
          ..color = Colors.white.withValues(alpha: (1.0 - p).clamp(0.0, 1.0)),
      );
      tp.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
  }

  void _paintConfetti(Canvas canvas) {
    const confettiColors = [
      Color(0xFF10B981),
      Color(0xFFFF7A6B),
      Color(0xFFFDE047),
      Color(0xFF60A5FA),
      Color(0xFFA78BFA),
    ];

    for (int i = 0; i < 10; i++) {
      final confettiProgress = (animProgress + (i * 0.1)) % 1.0;
      final angle = (i / 10.0) * 2 * math.pi;
      final distance = 30 + (confettiProgress * 24);
      final dx = 50 + math.cos(angle) * distance;
      final dy =
          50 +
          math.sin(angle) * distance +
          (confettiProgress * confettiProgress * 14);
      final color = confettiColors[i % confettiColors.length].withValues(
        alpha: (1.0 - confettiProgress * 0.55).clamp(0.0, 1.0),
      );

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(confettiProgress * math.pi * 3 + i);
      final paint = Paint()..color = color;
      if (i % 2 == 0) {
        canvas.drawCircle(Offset.zero, 2.2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 4, height: 2.2),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant PockoPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.animProgress != animProgress ||
        oldDelegate.blink != blink ||
        oldDelegate.gaze != gaze ||
        oldDelegate.voiceLevel != voiceLevel;
  }
}
