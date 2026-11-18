import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

/// Duration of the whole "Expense Logged!" beat (the overlay stays up this
/// long, then fades back to the page).
const Duration kLoggedBeat = Duration(milliseconds: 950);

/// Pastel confetti palette.
const List<Color> _confettiColors = [
  Color(0xFF6EE7B7), // mint
  Color(0xFFFDE68A), // butter
  Color(0xFFFBCFE8), // blush
  Color(0xFFBAE6FD), // sky
  Color(0xFFDDD6FE), // lavender
  Color(0xFFFED7AA), // peach
];

/// Burst that plays *around Pocko* when an expense is logged: an expanding
/// emerald ring, a checkmark badge that pops in, and floating pastel confetti.
///
/// Pure `CustomPainter` work (no blur, no saveLayer), so it stays at 60 fps.
/// Place it in a `Stack` (clip none) over a box of [size] (the mascot).
class LoggedBurst extends StatelessWidget {
  final double size;

  const LoggedBurst({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('logged_burst'),
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The painter paints well outside the mascot's box.
          Positioned(
            left: -320,
            right: -320,
            top: -260,
            bottom: -420,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1300),
                builder: (context, t, _) => CustomPaint(
                  key: const ValueKey('logged_confetti'),
                  painter: _BurstPainter(t, heroSize: size),
                ),
              ),
            ),
          ),
          // Checkmark badge, bottom-right of Pocko, popping in with a spring.
          Positioned(
            right: size * 0.04,
            bottom: size * 0.04,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                key: const ValueKey('logged_check'),
                width: math.max(34, size * 0.22),
                height: math.max(34, size * 0.22),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryEmerald,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x5534D399), blurRadius: 14),
                  ],
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: math.max(22, size * 0.15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double t;
  final double heroSize;

  _BurstPainter(this.t, {required this.heroSize});

  // Deterministic "random" so every burst looks the same and repaints are cheap.
  static final List<_Particle> _particles = _buildParticles();

  static List<_Particle> _buildParticles() {
    final r = math.Random(7);
    return List.generate(30, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.7;
      return _Particle(
        angle: angle,
        speed: 150 + r.nextDouble() * 210,
        size: 6 + r.nextDouble() * 7,
        spin: (r.nextDouble() - 0.5) * 9,
        color: _confettiColors[i % _confettiColors.length],
        round: i % 3 == 0,
        delay: r.nextDouble() * 0.12,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Origin: the middle of Pocko's box (the painter box is larger than it).
    final origin = Offset(size.width / 2, 260 + heroSize / 2);

    // Expanding emerald ring bursts (two staggered waves).
    for (var wave = 0; wave < 2; wave++) {
      final p = ((t - wave * 0.16) / 0.55).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      final radius = heroSize * (0.42 + 0.62 * eased);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (10 - 8 * p).clamp(1.5, 10.0)
        ..color = AppTheme.primaryEmerald.withValues(alpha: 0.85 * (1 - p));
      canvas.drawCircle(origin, radius, paint);
    }

    // Confetti.
    for (final p in _particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final out = Curves.easeOutCubic.transform(local);
      final dx = math.cos(p.angle) * p.speed * out;
      final dy = math.sin(p.angle) * p.speed * out + 170 * local * local;
      final alpha = local < 0.7 ? 1.0 : (1 - (local - 0.7) / 0.3);
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      final c = origin.translate(dx, dy);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(p.spin * local);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.55,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final bool round;
  final double delay;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
    required this.round,
    required this.delay,
  });
}

/// "✓ Logged ¥8,000 • Ramen": the confirmation pill that bounces in with a
/// spring. Its shadow is constant (only the scale animates), so overshoot
/// curves can never produce an invalid negative blur.
class LoggedPill extends StatelessWidget {
  final String label;
  final String? subtitle;

  const LoggedPill({super.key, required this.label, this.subtitle});

  static const List<BoxShadow> _shadow = [
    BoxShadow(color: Color(0x6634D399), blurRadius: 22, offset: Offset(0, 8)),
  ];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.35, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('logged_pill'),
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.circular(99),
              boxShadow: _shadow,
            ),
            // Long titles shrink to fit instead of being cut off.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
