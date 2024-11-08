
import 'package:flutter/material.dart';

class AppTheme {
  static const Color constantBlack = Color(0xFF000000);  // Cor preta constante
  static const Color constantGreen = Color(0xFF00FF00);  // Cor verde constante para todos os temas
  static const Color constantShadow = Color(0x00000066);

  static final lightTheme = ThemeData(
    primaryColor: const Color(0xFF6B00E3),
    scaffoldBackgroundColor: const Color(0xFFFFFFFF),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF6B00E3),
      secondary: Color(0xFFFFFFFF),
      tertiary: Color(0xFF933FFC),
      background: Color(0xFFE4E9F7),
      surface: Color(0xFFDED0E0),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF242321),
      onBackground: Color(0xFF18191A),
      onSurface: Color(0xFF000000),
      error: Color(0xFFFF5963),
      onError: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF383838), // Accent1
      secondaryContainer: Color(0xFF716f6f), // Accent2
      outline: Color(0xFFFFFFFF),
      inverseSurface: Color(0xFF707070),
      shadow: constantBlack,
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
    cardColor: const Color(0xffffffff),
    shadowColor: constantBlack, // Exemplo de uso
  );

  static final darkTheme = ThemeData(
    primaryColor: const Color(0xFF6B00E3),
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF6B00E3),
      secondary: Color(0xFF0D1117),
      tertiary: Color(0xFF933FFC),
      background: Color(0xFF18191A),
      surface: Color(0xFFE8D5FF),
      onPrimary: Color(0xFF0D1117),
      onSecondary: Color(0xFFFFFFFF),
      onBackground: Color(0xFFFFFFFF),
      onSurface: Color(0xFFFFFFFF),
      error: Color(0xFFFF5963),
      onError: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFafafaf), // Accent1
      secondaryContainer: Color(0xFFe2e2e2), // Accent2
      outline: Color(0xFFFFFFFF),
      inverseSurface: Color(0xFF707070),
      shadow: constantBlack,
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
    cardColor: const Color(0xFF18191A),
    shadowColor: constantBlack, // Exemplo de uso
  );
}
