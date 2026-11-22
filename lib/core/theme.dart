import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF0B6E4F);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

const teamColors = <Color>[
  Color(0xFF0B6E4F),
  Color(0xFF1565C0),
  Color(0xFFC62828),
  Color(0xFFEF6C00),
  Color(0xFF6A1B9A),
  Color(0xFF00838F),
  Color(0xFFAD1457),
  Color(0xFF37474F),
];
