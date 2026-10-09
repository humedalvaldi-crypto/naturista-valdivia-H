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

class AppSettings {
  const AppSettings({
    this.language,
    this.theme = AppThemePreference.system,
    this.onboardingDone = false,
  });

  /// `null` = seguir el idioma del dispositivo.
  final AppLanguage? language;
  final AppThemePreference theme;

  /// La bienvenida ya se mostró en este dispositivo.
  final bool onboardingDone;

  AppSettings copyWith({AppLanguage? language, AppThemePreference? theme, bool? onboardingDone}) => AppSettings(
        language: language ?? this.language,
        theme: theme ?? this.theme,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.theme == theme &&
      other.onboardingDone == onboardingDone;

  @override
  int get hashCode => Object.hash(language, theme, onboardingDone);
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

  final SharedPreferences _prefs;

  @override
  Future<AppSettings> read() async {
    return AppSettings(
      language: AppLanguage.tryParse(_prefs.getString(languageKey)),
      theme: AppThemePreference.tryParse(_prefs.getString(themeKey)) ??
          AppThemePreference.system,
      onboardingDone: _prefs.getBool(onboardingKey) ?? false,
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
    ]);
    if (ok.contains(false)) {
      throw const SettingsPersistenceException();
    }
  }
}

class SettingsPersistenceException implements Exception {
  const SettingsPersistenceException();

  @override
  String toString() => 'No se pudieron guardar las preferencias en el dispositivo.';
}
