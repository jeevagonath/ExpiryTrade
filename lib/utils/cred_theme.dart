import 'package:flutter/material.dart';

class CredColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF111111);
  static const Color card = Color(0xFF1A1A1A);
  
  static const Color primary = Color(0xFF818CF8); // Indigo
  static const Color secondary = Color(0xFFC084FC); // Purple
  static const Color accent = Color(0xFF2DD4BF); // Teal
  
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  
  static const Color textBody = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF94A3B8);
}

class CredShadows {
  static List<BoxShadow> neumorphicRaised = [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.05),
      offset: const Offset(-5, -5),
      blurRadius: 10,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      offset: const Offset(5, 5),
      blurRadius: 10,
    ),
  ];

  static List<BoxShadow> neumorphicShadow = neumorphicRaised;

  static List<BoxShadow> neumorphicPressed = [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.02),
      offset: const Offset(2, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      offset: const Offset(-2, -2),
      blurRadius: 4,
    ),
  ];
}

class CredGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
  );

  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF000000), Color(0xFF0F172A)],
  );
}

class CredTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: CredColors.background,
      primaryColor: CredColors.primary,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: CredColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: CredColors.primary,
        secondary: CredColors.secondary,
        surface: CredColors.surface,
        error: CredColors.error,
      ),
      cardTheme: CardThemeData(
        color: CredColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: CredColors.textBody),
        bodyMedium: TextStyle(color: CredColors.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CredColors.surface,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 10,
      ),
    );
  }
}
