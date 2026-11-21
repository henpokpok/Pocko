import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted-glass style surface (no backdrop blur) with a hairline highlight border and layered shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppTheme.elevatedCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // Frosted look without a BackdropFilter: a near-opaque translucent fill
        // composites for free, a backdrop blur re-samples the page every frame.
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? AppTheme.glassFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppTheme.glassBorder, width: 1.2),
          ),
          child: child,
        ),
      ),
    );
  }
}
