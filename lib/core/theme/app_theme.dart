import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBackground = Color(0xFF0F0F12);
  static const Color cardBackground = Color(0xFF1E1E24);
  static const Color neonGreen = Color(0xFF00FF7F);
  static const Color neonOrange = Color(0xFFFF8C00);
  static const Color neonBlue = Color(0xFF00BFFF);
  static const Color errorRed = Color(0xFFFF3B30);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9E9EAE);

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: darkBackground,
      primaryColor: neonGreen,
      colorScheme: const ColorScheme.dark(
        primary: neonGreen,
        secondary: neonBlue,
        surface: cardBackground,
        error: errorRed,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  // Tiện ích tạo hiệu ứng kính mờ (Glassmorphism)
  static BoxDecoration glassDecoration({
    Color? color,
    double borderRadius = 16.0,
    double borderWidth = 1.0,
  }) {
    return BoxDecoration(
      color: (color ?? Colors.black).withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.15),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 10,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
