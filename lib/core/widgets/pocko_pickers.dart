import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pocko look (emerald, 28 px corners) for `showDatePicker` / `showTimePicker`:
/// pass as `builder: pockoPickerBuilder`.
Widget pockoPickerBuilder(BuildContext context, Widget? child) {
  final base = Theme.of(context);
  return Theme(
    data: base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppTheme.primaryEmerald,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: AppTheme.textDark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        dialBackgroundColor: AppTheme.primaryEmeraldSubtle,
        hourMinuteColor: AppTheme.primaryEmeraldLight,
        hourMinuteTextColor: AppTheme.primaryEmeraldDark,
        dayPeriodColor: AppTheme.primaryEmeraldLight,
        dayPeriodTextColor: AppTheme.primaryEmeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.primaryEmeraldDark,
        ),
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Tappable pill showing a picked value (date, time...), Pocko style.
class PockoValuePill extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const PockoValuePill({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      shape: const StadiumBorder(
        side: BorderSide(color: AppTheme.borderColor, width: 2),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryEmeraldDark),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.tabularNumberStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
