import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'pocko_mascot.dart';

/// Friendly empty state starring Pocko.
class PockoEmptyState extends StatelessWidget {
  final PockoMood mood;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Defaults to [PockoSizes.hero] (140–160 px).
  final double? mascotSize;

  const PockoEmptyState({
    super.key,
    this.mood = PockoMood.sleepy,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.mascotSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: AppTheme.surfaceDecoration(radius: 28),
          child: Column(
            children: [
              PockoMascot(
                mood: mood,
                size: mascotSize ?? PockoSizes.hero(context),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSlate,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }
}
