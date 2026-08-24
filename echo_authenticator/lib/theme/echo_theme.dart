import 'package:flutter/material.dart';

/// Echo Design Tokens matching `public/echo.css`
class EchoTheme {
  // Brand & Palette Tokens
  static const Color accent = Color(0xFF2563EB); // Royal Precision Blue
  static const Color accentHover = Color(0xFF1D4ED8);
  static const Color accentSoft = Color(0x102563EB);
  static const Color accentGlow = Color(0x332563EB);

  static const Color ok = Color(0xFF059669); // Emerald Green
  static const Color okSoft = Color(0x10059669);

  static const Color bad = Color(0xFFDC2626); // Crimson Red
  static const Color badSoft = Color(0x10DC2626);

  static const Color warn = Color(0xFFD97706); // Amber
  static const Color warnSoft = Color(0x10D97706);

  // Light Theme Tokens
  static const Color bgLight = Color(0xFFF0F6FF);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF0F172A);
  static const Color mutedLight = Color(0xFF475569);
  static const Color dimLight = Color(0xFF64748B);
  static const Color borderLight = Color(0x1A2563EB);
  static const Color borderStrongLight = Color(0x2E2563EB);

  // Dark Theme Tokens
  static const Color bgDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF101726);
  static const Color textDark = Color(0xFFF8FAFC);
  static const Color mutedDark = Color(0xFF94A3B8);
  static const Color dimDark = Color(0xFF64748B);
  static const Color borderDark = Color(0x2E3B82F6);
  static const Color borderStrongDark = Color(0x4D3B82F6);

  // Radii & Elevation
  static const double rSm = 8.0;
  static const double rMd = 14.0;
  static const double rLg = 24.0;

  // Spring & Easing Curves
  static const Curve springCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve smoothOut = Cubic(0.16, 1.0, 0.3, 1.0);

  // Light ThemeData
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      colorScheme: const ColorScheme.light(
        primary: accent,
        secondary: accentHover,
        surface: surfaceLight,
        error: bad,
        onPrimary: Colors.white,
        onSurface: textLight,
      ),
      fontFamily: 'Plus Jakarta Sans',
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: const BorderSide(color: borderStrongLight, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textLight,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // Dark ThemeData
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentHover,
        surface: surfaceDark,
        error: bad,
        onPrimary: Colors.white,
        onSurface: textDark,
      ),
      fontFamily: 'Plus Jakarta Sans',
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: const BorderSide(color: borderStrongDark, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
