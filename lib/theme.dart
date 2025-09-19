import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional medical color palette:
/// Primary: Calming indigo/teal hybrid
/// Accent: Fresh teal & mint for actions
/// Support: Soft blues for surfaces, subtle amber for warnings, rose for errors
class AppColors {
  static const primary = Color(0xFF2F4AA0); // deep clinical indigo
  static const primaryDark = Color(0xFF1F326F);
  static const primaryLight = Color(0xFF5F74C1);

  static const teal = Color(0xFF0F8C8C);
  static const mint = Color(0xFF4CBFA6);

  static const surface = Color(0xFFF6F8FC);
  static const surfaceAlt = Color(0xFFE9EEF7);
  static const outline = Color(0xFFCAD5E6);

  static const success = Color(0xFF168F4E);
  static const warning = Color(0xFFF2B441);
  static const error = Color(0xFFD14155);
  static const info = Color(0xFF2E6FB9);

  static const gradientTop = Color(0xFF324EB0);
  static const gradientBottom = Color(0xFF1A6D93);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.teal,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
  );

  final textTheme = GoogleFonts.sourceSans3TextTheme(base.textTheme).copyWith(
    headlineLarge: GoogleFonts.montserrat(
      fontWeight: FontWeight.w700,
      fontSize: 32,
      letterSpacing: -0.5,
      color: AppColors.primaryDark,
    ),
    headlineMedium: GoogleFonts.montserrat(
      fontWeight: FontWeight.w600,
      fontSize: 24,
      letterSpacing: -0.2,
      color: AppColors.primaryDark,
    ),
    titleLarge: GoogleFonts.sourceSans3(
      fontWeight: FontWeight.w600,
      fontSize: 20,
      color: AppColors.primaryDark,
    ),
    bodyLarge: GoogleFonts.sourceSans3(
      fontSize: 16,
      height: 1.35,
      color: const Color(0xFF1F2430),
    ),
    bodyMedium: GoogleFonts.sourceSans3(
      fontSize: 14,
      height: 1.35,
      color: const Color(0xFF2B3240),
    ),
    labelLarge: GoogleFonts.sourceSans3(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      letterSpacing: 0.3,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primaryDark,
      titleTextStyle: textTheme.titleLarge,
    ),
    // Card styling
  // Temporarily omit custom cardTheme due to version type mismatch; revisit after upgrading Flutter SDK.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: AppColors.surfaceAlt,
  selectedColor: AppColors.primary.withValues(alpha: 0.12),
      side: const BorderSide(color: AppColors.outline),
      labelStyle: GoogleFonts.sourceSans3(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(space: 32, thickness: 1, color: AppColors.outline),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
  indicatorColor: AppColors.primary.withValues(alpha: 0.08),
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.sourceSans3(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
