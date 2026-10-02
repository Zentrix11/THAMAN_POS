import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF5F7F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF9FBFA);
  static const text = Color(0xFF14211E);
  static const muted = Color(0xFF73817D);
  static const border = Color(0xFFE3E9E6);
  static const primary = Color(0xFF0F4B43);
  static const primaryStrong = Color(0xFF083A34);
  static const primarySoft = Color(0xFFE9F3F0);
  static const accent = Color(0xFFD86B32);
  static const accentSoft = Color(0xFFFFF0E8);
  static const success = Color(0xFF218A6D);
  static const warning = Color(0xFFE5A11A);
  static const danger = Color(0xFFD84B4B);
  static const blue = Color(0xFF3A6FD8);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light).copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.border,
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1.0, color: AppColors.text),
        headlineMedium: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.7, color: AppColors.text),
        titleLarge: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text),
        titleMedium: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.text, height: 1.45),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        labelStyle: const TextStyle(fontSize: 10, color: AppColors.muted),
        hintStyle: const TextStyle(fontSize: 9.7, color: AppColors.muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(fontSize: 9.3, fontWeight: FontWeight.w700),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.text),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryStrong,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class AppBreakpoints {
  static const mobile = 700.0;
  static const tablet = 1080.0;
}
