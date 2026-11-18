import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/tactile.dart';

/// Clean, name-only group member pill (no initial avatar): a stadium shape
/// with a subtle emerald fill and glowing border when selected.
class MemberPill extends StatelessWidget {
  final String name;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const MemberPill({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      semanticLabel: '${selected ? 'Remove' : 'Add'} $name from the split',
      // A little bounce when (de)selected. The glow keeps the same shadow
      // shape in both states so the implicit animation never lerps a negative
      // blur.
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.97,
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 8 : 10,
          ),
          decoration: ShapeDecoration(
            color: selected
                ? AppTheme.primaryEmerald.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.10),
            shape: StadiumBorder(
              side: BorderSide(
                color: selected
                    ? AppTheme.primaryEmerald
                    : Colors.white.withValues(alpha: 0.28),
                width: selected ? 2 : 1.2,
              ),
            ),
            shadows: [
              BoxShadow(
                color: AppTheme.primaryEmerald.withValues(
                  alpha: selected ? 0.45 : 0.0,
                ),
                blurRadius: 12,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Text(
            name,
            maxLines: 1,
            style: GoogleFonts.plusJakartaSans(
              fontSize: compact ? 13 : 14.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
