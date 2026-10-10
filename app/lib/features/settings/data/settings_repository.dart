import 'package:shared_preferences/shared_preferences.dart';

/// Idiomas admitidos. Debe coincidir con `l10n/app_*.arb` y con la API.
enum AppLanguage {
  es,
  en;

  static AppLanguage? tryParse(String? code) {
    for (final value in AppLanguage.values) {
      if (value.name == code) return value;
    }
    return null;
  }
}

/// Tema visual. Los nombres coinciden con la API (`system|light|dark`).
enum AppThemePreference {
  system,
  light,
  dark;

  static AppThemePreference? tryParse(String? code) {
    for (final value in AppThemePreference.values) {
      if (value.name == code) return value;
    }
    return null;
  }
}

/// Mapa base preferido (coincide con `BaseMap` de shared/map).
enum MapBasePreference {
  streets,
  topo;

  static MapBasePreference? tryParse(String? code) {
    for (final value in MapBasePreference.values) {
      if (value.name == code) return value;
    }
    return null;
  }
}

/// Tamaños de texto ofrecidos (factor de escala).
const textScaleOptions = [0.9, 1.0, 1.15, 1.3];

class AppSettings {
  const AppSettings({
    this.language,
    this.theme = AppThemePreference.system,
    this.onboardingDone = false,
    this.textScale = 1.0,
    this.highContrast = false,
    this.reduceMotion = false,
    this.mapBase = MapBasePreference.streets,
    this.observationsPrivate = false,
  });

  /// `null` = seguir el idioma del dispositivo.
  final AppLanguage? language;
  final AppThemePreference theme;

  /// La bienvenida ya se mostró en este dispositivo.
  final bool onboardingDone;

  /// Escala de texto de la app (se multiplica por la del sistema).
  final double textScale;

  /// Colores con más contraste.
  final bool highContrast;

  /// Sin animaciones de transición.
  final bool reduceMotion;

  /// Mapa base con el que se abre el mapa de biodiversidad.
  final MapBasePreference mapBase;

  /// Las observaciones nuevas empiezan como privadas.
  final bool observationsPrivate;

  AppSettings copyWith({
    AppLanguage? language,
    AppThemePreference? theme,
    bool? onboardingDone,
    double? textScale,
    bool? highContrast,
    bool? reduceMotion,
    MapBasePreference? mapBase,
    bool? observationsPrivate,
  }) =>
      AppSettings(
        language: language ?? this.language,
        theme: theme ?? this.theme,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        mapBase: mapBase ?? this.mapBase,
        observationsPrivate: observationsPrivate ?? this.observationsPrivate,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.theme == theme &&
      other.onboardingDone == onboardingDone &&
      other.textScale == textScale &&
      other.highContrast == highContrast &&
      other.reduceMotion == reduceMotion &&
      other.mapBase == mapBase &&
      other.observationsPrivate == observationsPrivate;

  @override
  int get hashCode =>
      Object.hash(language, theme, onboardingDone, textScale, highContrast, reduceMotion, mapBase, observationsPrivate);
}

/// Persistencia de preferencias. La versión local usa SharedPreferences;
/// en la Fase 3 se añade la sincronización con `PATCH /api/v1/me/settings`.
abstract interface class SettingsRepository {
  Future<AppSettings> read();
  Future<void> write(AppSettings settings);
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._prefs);

  static const languageKey = 'settings.language';
  static const themeKey = 'settings.theme';
  static const onboardingKey = 'settings.onboardingDone';
  static const textScaleKey = 'settings.textScale';
  static const highContrastKey = 'settings.highContrast';
  static const reduceMotionKey = 'settings.reduceMotion';
  static const mapBaseKey = 'settings.mapBase';
  static const observationsPrivateKey = 'settings.observationsPrivate';

  final SharedPreferences _prefs;

  @override
  Future<AppSettings> read() async {
    return AppSettings(
      language: AppLanguage.tryParse(_prefs.getString(languageKey)),
      theme: AppThemePreference.tryParse(_prefs.getString(themeKey)) ??
          AppThemePreference.system,
      onboardingDone: _prefs.getBool(onboardingKey) ?? false,
      textScale: _validScale(_prefs.getDouble(textScaleKey)),
      highContrast: _prefs.getBool(highContrastKey) ?? false,
      reduceMotion: _prefs.getBool(reduceMotionKey) ?? false,
      mapBase: MapBasePreference.tryParse(_prefs.getString(mapBaseKey)) ?? MapBasePreference.streets,
      observationsPrivate: _prefs.getBool(observationsPrivateKey) ?? false,
    );
  }

  @override
  Future<void> write(AppSettings settings) async {
    final language = settings.language;
    final ok = await Future.wait([
      if (language == null)
        _prefs.remove(languageKey)
      else
        _prefs.setString(languageKey, language.name),
      _prefs.setString(themeKey, settings.theme.name),
      _prefs.setBool(onboardingKey, settings.onboardingDone),
      _prefs.setDouble(textScaleKey, settings.textScale),
      _prefs.setBool(highContrastKey, settings.highContrast),
      _prefs.setBool(reduceMotionKey, settings.reduceMotion),
      _prefs.setString(mapBaseKey, settings.mapBase.name),
      _prefs.setBool(observationsPrivateKey, settings.observationsPrivate),
    ]);
    if (ok.contains(false)) {
      throw const SettingsPersistenceException();
    }
  }
}

double _validScale(double? value) => textScaleOptions.contains(value) ? value! : 1.0;

class SettingsPersistenceException implements Exception {
  const SettingsPersistenceException();

  @override
  String toString() => 'No se pudieron guardar las preferencias en el dispositivo.';
}
