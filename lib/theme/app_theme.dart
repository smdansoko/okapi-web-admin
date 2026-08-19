import 'package:flutter/material.dart';

/// OKAPI Environnement Conseil brand colors
/// Derived from the OKAPI logo: dark maroon/burgundy red gradient + dark green wave
class OkapiColors {
  OkapiColors._();

  // Primary brand color - maroon/burgundy red from logo
  static const Color primary = Color(0xFF6B1F1F);
  static const Color primaryDark = Color(0xFF4A1414);
  static const Color primaryLight = Color(0xFF8F3232);

  // Secondary - dark green wave from logo
  static const Color secondary = Color(0xFF1F4A2E);
  static const Color secondaryLight = Color(0xFF2E6B44);

  // Neutral / background
  static const Color background = Color(0xFFF7F4F2);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF2A1414);
  static const Color textLight = Color(0xFF6B6B6B);

  // Status colors
  static const Color success = Color(0xFF2E6B44);
  static const Color warning = Color(0xFFC77B00);
  static const Color error = Color(0xFFB3261E);
  static const Color info = Color(0xFF1F5A8F);

  // Charts palette (harmonized with brand)
  static const List<Color> chartColors = [
    primary,
    secondary,
    Color(0xFFC77B00),
    Color(0xFF1F5A8F),
    primaryLight,
    secondaryLight,
    Color(0xFF8F3232),
    Color(0xFF6B6B6B),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: OkapiColors.primary,
      primary: OkapiColors.primary,
      secondary: OkapiColors.secondary,
      surface: OkapiColors.surface,
      error: OkapiColors.error,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: OkapiColors.background,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: OkapiColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: OkapiColors.surface,
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: OkapiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: OkapiColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: OkapiColors.error),
        ),
        labelStyle: const TextStyle(color: OkapiColors.textLight),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: OkapiColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: OkapiColors.primary,
          side: const BorderSide(color: OkapiColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: OkapiColors.primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: OkapiColors.primary,
        foregroundColor: Colors.white,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: OkapiColors.primary.withValues(alpha: 0.08),
        labelStyle: const TextStyle(color: OkapiColors.primary, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: OkapiColors.primary,
        unselectedItemColor: OkapiColors.textLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: IconThemeData(color: OkapiColors.primary),
        selectedLabelTextStyle: TextStyle(color: OkapiColors.primary, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: OkapiColors.textDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
