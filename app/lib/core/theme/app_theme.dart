import 'package:flutter/material.dart';

/// Paleta de Naturista Valdivia. El verde musgo proviene de la app anterior
/// (`#2D5A27`) para mantener continuidad visual.
abstract final class AppColors {
  static const moss = Color(0xFF2D5A27);
  static const river = Color(0xFF2F6F7E);
  static const copihue = Color(0xFFB3261E);
  static const paper = Color(0xFFF7F3EA);
}

abstract final class AppTheme {
  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.moss,
          secondary: AppColors.river,
          surface: AppColors.paper,
        ),
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.moss,
          secondary: AppColors.river,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      // Objetivos táctiles de al menos 48 dp.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}
