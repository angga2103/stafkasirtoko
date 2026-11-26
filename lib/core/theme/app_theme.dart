import 'package:flutter/material.dart';

class AppBreakpoints {
  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000;
}

class AppTheme {
  static const Color primaryGreen = Color(0xFF0A8754);
  static const Color primaryGreenDark = Color(0xFF065F3B);
  static const Color primaryGreenSoft = Color(0xFFE7F5EE);
  static const Color accentIndigo = Color(0xFF4F46E5);
  static const Color accentRed = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color success = Color(0xFF16A34A);
  static const Color darkBg = Color(0xFF111827);
  static const Color surfaceWhite = Colors.white;
  static const Color surfaceGray = Color(0xFFF3F6F9);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFE5E7EB);

  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
        color: color ?? surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          surface: surfaceWhite,
        ),
        scaffoldBackgroundColor: surfaceGray,
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: borderLight),
          ),
        ),
      );
}
