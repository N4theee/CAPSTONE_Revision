import 'package:flutter/material.dart';

/// Dark UI + teal / mint accents for student flows (history, details, active session).
class StudentAttendanceUi {
  StudentAttendanceUi._();

  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceElevated = Color(0xFF1C232D);
  static const Color borderSubtle = Color(0xFF30363D);
  static const Color accentTeal = Color(0xFF14B8A6);
  static const Color accentTealDark = Color(0xFF0F766E);
  static const Color mint = Color(0xFF5EEAD4);
  static const Color success = Color(0xFF34D399);
  static const Color textSecondary = Color(0xFF8B949E);
  /// Brighter copy for hints, helpers, and field labels on dark fields.
  static const Color textOnField = Color(0xFFE6EDF3);
  static const Color hintOnField = Color(0xFFCBD5E1);

  /// Course tiles on student dashboard (cards in reference).
  static const Color dashboardGradientTop = Color(0xFF0D9488);
  static const Color dashboardGradientBottom = Color(0xFF115E59);
  static const Color dashboardCardTop = Color(0xFF14B8A6);
  static const Color dashboardCardBorder = Color(0xFF5EEAD4);
  static const Color dashboardFooterBar = Color(0xFF134E4A);

  static ThemeData themeOverlay(ThemeData base) {
    final scheme = ColorScheme.dark(
      surface: surface,
      primary: accentTeal,
      onPrimary: Colors.white,
      onSurface: Colors.white,
      secondary: mint,
      onSecondary: Color(0xFF042F2E),
      tertiary: success,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: borderSubtle, thickness: 1),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textOnField, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: mint, fontSize: 14),
        hintStyle: const TextStyle(color: hintOnField, fontSize: 15),
        helperStyle: const TextStyle(color: hintOnField, fontSize: 12),
        errorStyle: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
        prefixIconColor: hintOnField,
        suffixIconColor: hintOnField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentTeal.withValues(alpha: 0.45)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentTeal.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentTeal, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  /// Readable [TextField] on dark exam/attendance screens.
  static TextStyle fieldTextStyle() =>
      const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500);
}
