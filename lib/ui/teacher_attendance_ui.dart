import 'package:flutter/material.dart';

/// Shared dark theme + palette for teacher session history and detail flows.
class TeacherAttendanceUi {
  TeacherAttendanceUi._();

  static const Color background = Color(0xFF0D0E12);
  static const Color surface = Color(0xFF1A1C26);
  static const Color surfaceBorder = Color(0xFF2D3142);
  static const Color accentPurple = Color(0xFF7E57C2);
  static const Color accentPurpleMuted = Color(0xFF5E3FA8);
  static const Color presentGreen = Color(0xFF4CAF50);
  static const Color absentOrange = Color(0xFFFF9800);
  static const Color anomalyRed = Color(0xFFF44336);
  static const Color textSecondary = Color(0xFFB0B3C0);
  static const Color textOnField = Color(0xFFE8EAF0);
  static const Color hintOnField = Color(0xFFD1D5E0);

  static ThemeData themeOverlay(ThemeData base) {
    final scheme = ColorScheme.dark(
      surface: surface,
      primary: accentPurple,
      onPrimary: Colors.white,
      onSurface: Colors.white,
      secondary: accentPurpleMuted,
      onSecondary: Colors.white,
      error: anomalyRed,
      onError: Colors.white,
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
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: surfaceBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: surfaceBorder, thickness: 1),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(surface),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textOnField, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: accentPurple, fontSize: 14),
        hintStyle: const TextStyle(color: hintOnField, fontSize: 15),
        helperStyle: const TextStyle(color: hintOnField, fontSize: 12),
        errorStyle: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
        prefixIconColor: hintOnField,
        suffixIconColor: hintOnField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentPurple.withValues(alpha: 0.45)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentPurple.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentPurple, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: Colors.white,
      ),
    );
  }

  static TextStyle fieldTextStyle() =>
      const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500);
}
