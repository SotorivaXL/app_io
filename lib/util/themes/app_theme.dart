
import 'package:flutter/material.dart';

class AppTheme {
  static const Color constantBlack = Color(0xFF000000);  // Cor preta constante
  static const Color constantGreen = Color(0xFF00FF00);  // Cor verde constante para todos os temas
  static const Color constantShadow = Color(0x00000066);

  static final lightTheme = ThemeData(
    primaryColor: const Color(0xFF6B00E3),
    scaffoldBackgroundColor: const Color(0xFFf5f8fe),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF6B00E3),
      secondary: Color(0xFFFFFFFF),
      tertiary: Color(0xFF933FFC),
      background: Color(0xFFf5f8fe),
      surface: Color(0xFF6B00E3),
      surfaceVariant: Color(0xFF000000),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF595959),
      onBackground: Color(0xFF18191A),
      onSurface: Color(0xFFFFFFFF),
      error: Color(0xFFDD000A),
      onError: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF383838), // Accent1
      secondaryContainer: Color(0xFF716f6f), // Accent2
      outline: Color(0xFFFFFFFF),
      inverseSurface: Color(0xFF707070),
      tertiaryContainer: Color(0xFFB7B3C6),
      shadow: Color(0x20000000),
      scrim: Color(0xFF18191a),
      onSecondaryContainer: Color(0xFFFFFFFF),
      onPrimaryContainer: Color(0xFFf5f8fe),
      onTertiaryContainer: Color(0xFFF0F0F3),
      onTertiary: constantGreen,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF000000)),
      bodyMedium: TextStyle(color: Color(0xFF000000)),
      headlineLarge: TextStyle(color: Color(0xFF000000)),
      headlineMedium: TextStyle(color: Color(0xFF000000)),
      headlineSmall: TextStyle(color: Color(0xFF000000)),
      titleLarge: TextStyle(color: Color(0xFF000000)),
      titleMedium: TextStyle(color: Color(0xFF000000)),
      titleSmall: TextStyle(color: Color(0xFF000000)),
      labelLarge: TextStyle(color: Color(0xFFFFFFFF)),
      labelSmall: TextStyle(color: Color(0xFF000000)),
    ),
    cardColor: const Color(0xFFf5f8fe),
    shadowColor: constantBlack,
  );

  static final darkTheme = ThemeData(
    primaryColor: const Color(0xFF6B00E3),
    scaffoldBackgroundColor: const Color(0xFF18191a),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF6B00E3),
      secondary: Color(0xFF252423),
      tertiary: Color(0xFF933FFC),
      background: Color(0xFF18191a),
      surface: Color(0xFF252423),
      surfaceVariant: Color(0xFFFFFFFF),
      onPrimary: Color(0xFF0D1117),
      onSecondary: Color(0xFFFFFFFF),
      onBackground: Color(0xFFFFFFFF),
      onSurface: Color(0xFFFFFFFF),
      error: Color(0xFFDD000A),
      onError: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFafafaf), // Accent1
      secondaryContainer: Color(0xFFe2e2e2), // Accent2
      outline: Color(0xFFFFFFFF),
      inverseSurface: Color(0xFF707070),
      tertiaryContainer: Color(0xFF2F2E32),
      shadow: Color(0x20000000),
      scrim: Color(0xFF18191a),
      onSecondaryContainer: Color(0xFF0F0F0F),
      onPrimaryContainer: Color(0xFFf5f8fe),
      onTertiaryContainer: Color(0xFF2E2E2E),
      onTertiary: constantGreen,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFFFFFFF)),
      bodyMedium: TextStyle(color: Color(0xFFFFFFFF)),
      headlineLarge: TextStyle(color: Color(0xFFFFFFFF)),
      headlineMedium: TextStyle(color: Color(0xFFFFFFFF)),
      headlineSmall: TextStyle(color: Color(0xFFFFFFFF)),
      titleLarge: TextStyle(color: Color(0xFFFFFFFF)),
      titleMedium: TextStyle(color: Color(0xFFFFFFFF)),
      titleSmall: TextStyle(color: Color(0xFFFFFFFF)),
      labelLarge: TextStyle(color: Color(0xFF000000)),
      labelSmall: TextStyle(color: Color(0xFFFFFFFF)),
    ),
    cardColor: const Color(0xFF252423),
    shadowColor: constantBlack,
  );
}
