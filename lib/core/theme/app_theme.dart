import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 24;
}

class AppBreakpoints {
  static const double compactPhone = 360;
  static const double tablet = 680;
  static const double wideTablet = 1024;
  static const double desktop = 1280;

  static bool isCompactPhone(BuildContext context) => MediaQuery.sizeOf(context).width < compactPhone;
  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= tablet;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktop;

  static int productGridCount(double width) {
    if (width >= desktop) return 4;
    if (width >= 960) return 3;
    if (width >= tablet) return 3;
    if (width >= 520) return 3;
    return 2;
  }
}

class AppTheme {
  // Unified KasirToko green-teal palette aligned with KasirToko Admin
  static const Color primaryGreen = Color(0xFF0F766E);
  static const Color primaryGreenDark = Color(0xFF065F3B);
  static const Color primaryGreenLight = Color(0xFF14B8A6);
  static const Color primaryGreenSoft = Color(0xFFE6F7F5);

  static const Color accentIndigo = Color(0xFF4F46E5);
  static const Color accentOrange = Color(0xFFD97706);
  static const Color warning = Color(0xFFD97706);
  static const Color accentRed = Color(0xFFDC2626);
  static const Color accentRedSoft = Color(0xFFFEE2E2);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color success = Color(0xFF16A34A);
  static const Color darkBg = Color(0xFF0F172A);

  static const Color surfaceWhite = Colors.white;
  static const Color surfaceGray = Color(0xFFF8FAFC);
  static const Color background = Color(0xFFF8FAFC);
  static const Color lightGreyBg = Color(0xFFF1F5F9);

  static const Color textDark = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  static BoxDecoration cardDecoration({Color? color, Color? borderColor}) => BoxDecoration(
        color: color ?? surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor ?? borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  static BoxDecoration softBadgeDecoration(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      );

  static InputDecoration denseInputDecoration({
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 19, color: textMuted) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        borderSide: const BorderSide(color: primaryGreen, width: 1.6),
      ),
    );
  }

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          secondary: accentOrange,
          surface: surfaceWhite,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceWhite,
          elevation: 0,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: borderLight, width: 0.9),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryGreen,
            side: const BorderSide(color: primaryGreen, width: 1.3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryGreen, width: 1.8),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          backgroundColor: Colors.white,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
      );
}
