import 'package:flutter/material.dart';

import '../data/settings_repository.dart';

/// Estado de preferencias de la app. Cambia idioma y tema al instante y
/// persiste el cambio; si la persistencia falla, el cambio se mantiene en
/// pantalla y se expone el error para avisar al usuario.
class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;

  AppSettings _settings = const AppSettings();
  Object? _lastError;

  AppSettings get settings => _settings;
  Object? get lastError => _lastError;

  Locale? get locale {
    final language = _settings.language;
    return language == null ? null : Locale(language.name);
  }

  ThemeMode get themeMode => switch (_settings.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };

  Future<void> load() async {
    try {
      _settings = await _repository.read();
      _lastError = null;
    } catch (error) {
      _lastError = error;
    }
    notifyListeners();
  }

  Future<bool> setLanguage(AppLanguage language) =>
      _update(_settings.copyWith(language: language));

  Future<bool> setTheme(AppThemePreference theme) =>
      _update(_settings.copyWith(theme: theme));

  Future<bool> completeOnboarding() => _update(_settings.copyWith(onboardingDone: true));

  Future<bool> _update(AppSettings next) async {
    if (next == _settings) return true;
    _settings = next;
    notifyListeners();
    try {
      await _repository.write(next);
      _lastError = null;
      return true;
    } catch (error) {
      _lastError = error;
      notifyListeners();
      return false;
    }
  }
}

/// Expone el [SettingsController] al árbol de widgets.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({super.key, required SettingsController controller, required super.child})
      : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope no encontrado en el árbol de widgets.');
    return scope!.notifier!;
  }

  /// Sin suscribirse a cambios (para callbacks).
  static SettingsController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
