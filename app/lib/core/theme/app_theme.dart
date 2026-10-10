import 'package:flutter/material.dart';

/// Paleta tomada de la lámina de diseño de Naturista Valdivia:
/// papel crema, verde bosque en acciones, verde muy oscuro en el splash y
/// dorado en el logotipo. El verde musgo `#2D5A27` viene de la app anterior.
abstract final class AppColors {
  static const forest = Color(0xFF2E5B2A); // botones y acciones principales
  static const forestDark = Color(0xFF1C3320); // splash y cabeceras oscuras
  static const moss = Color(0xFF2D5A27);
  static const gold = Color(0xFFC9A646); // logotipo
  static const paper = Color(0xFFF7F4EC); // fondo
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6E0D2); // bordes suaves de tarjetas
  static const ink = Color(0xFF22261F); // texto principal
  static const river = Color(0xFF2F6F7E);
  static const copihue = Color(0xFFB3261E);
}

abstract final class AppTheme {
  /// Tema según las preferencias de accesibilidad.
  static ThemeData resolve({required Brightness brightness, bool highContrast = false, bool reduceMotion = false}) {
    var theme = brightness == Brightness.light ? light() : dark();
    if (highContrast) theme = _highContrast(theme);
    if (reduceMotion) {
      theme = theme.copyWith(
        pageTransitionsTheme: PageTransitionsTheme(builders: {
          for (final p in TargetPlatform.values) p: const _NoTransitionsBuilder(),
        }),
      );
    }
    return theme;
  }

  /// Más contraste: texto secundario igual al principal, bordes marcados.
  static ThemeData _highContrast(ThemeData base) {
    final light = base.brightness == Brightness.light;
    final ink = light ? Colors.black : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      brightness: base.brightness,
      contrastLevel: 1.0,
    ).copyWith(
      primary: light ? AppColors.forestDark : const Color(0xFFB8F0A8),
      surface: light ? Colors.white : Colors.black,
      onSurface: ink,
      onSurfaceVariant: ink,
      outline: ink,
      outlineVariant: light ? const Color(0xFF555555) : const Color(0xFFBBBBBB),
    );
    return _build(scheme);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      primary: AppColors.forest,
      secondary: AppColors.river,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
    ).copyWith(
      surfaceContainerLowest: AppColors.card,
      surfaceContainerLow: AppColors.card,
      outlineVariant: AppColors.line,
    );
    return _build(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      secondary: AppColors.river,
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final radius = BorderRadius.circular(10);
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      // Botón principal ancho, como en la lámina.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light ? AppColors.card : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.brightness == Brightness.light ? AppColors.card : null,
        indicatorColor: scheme.primaryContainer,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Cambia de pantalla sin animación (preferencia "reducir movimiento").
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
