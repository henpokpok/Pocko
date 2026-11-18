import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Pocko Design Tokens
  static const Color canvasBackground = Color(0xFFF8FAFB);
  static const Color primaryEmerald = Color(0xFF10B981);
  static const Color primaryEmeraldDark = Color(0xFF059669);
  static const Color primaryEmeraldLight = Color(0xFFD1FAE5);
  static const Color primaryEmeraldSubtle = Color(0xFFECFDF5);

  static const Color coralOwes = Color(0xFFFF7A6B);
  static const Color coralOwesBg = Color(0xFFFFE4E1);
  static const Color coralOwesText = Color(0xFFE11D48);

  static const Color mascotMint = Color(0xFF6EE7B7);
  static const Color mascotMintDark = Color(0xFF34D399);
  static const Color mascotHatYellow = Color(0xFFFDE047);
  static const Color mascotCheekPink = Color(0xFFFCA5A5);

  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF0F172A);
  static const Color textSlate = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color borderColor = Color(0xFFE2E8F0);

  // Soft Pastel Gradients
  static const LinearGradient mintToSkyGradient = LinearGradient(
    colors: [Color(0xFFD2F8E5), Color(0xFFDCF0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient peachToMintGradient = LinearGradient(
    colors: [Color(0xFFFFE8DC), Color(0xFFD2F8E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient apricotToLavenderGradient = LinearGradient(
    colors: [Color(0xFFFFF0E5), Color(0xFFEFE8FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldShineGradient = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Radii
  static final BorderRadius cardRadius = BorderRadius.circular(28);
  static final BorderRadius sheetRadius = const BorderRadius.vertical(
    top: Radius.circular(32),
  );
  static final BorderRadius pillRadius = BorderRadius.circular(999);

  // Shadows
  static const List<BoxShadow> softCardShadow = [
    BoxShadow(color: Color(0x080F172A), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x050F172A), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> emeraldGlowShadow = [
    BoxShadow(color: Color(0x4D10B981), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// Multi-layer elevation used by hero cards: ambient + key + contact shadow.
  static const List<BoxShadow> elevatedCardShadow = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 40, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x080F172A), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const Color glassFill = Color(0xCCFFFFFF);
  static const Color glassBorder = Color(0xB3FFFFFF);

  /// White surface card with a hairline border and soft layered shadow.
  static BoxDecoration surfaceDecoration({
    double radius = 24,
    Color color = Colors.white,
    Color? borderColor,
    bool elevated = false,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? AppTheme.borderColor),
      boxShadow: elevated ? elevatedCardShadow : softCardShadow,
    );
  }

  // Tabular figures text style helper
  static TextStyle tabularNumberStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color color = textDark,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = Typography.material2021().black;
    final jakartaTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      baseTextTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryEmerald,
        primary: primaryEmerald,
        secondary: coralOwes,
        surface: canvasBackground,
      ),
      scaffoldBackgroundColor: canvasBackground,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textDark,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      textTheme: jakartaTextTheme.apply(
        bodyColor: textDark,
        displayColor: textDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryEmerald,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: pillRadius),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primaryEmerald, width: 2),
        ),
      ),
    );
  }
}
