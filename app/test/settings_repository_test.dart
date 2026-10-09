import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/settings/application/settings_controller.dart';
import 'package:naturista_valdivia/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingRepository implements SettingsRepository {
  @override
  Future<AppSettings> read() async => const AppSettings();

  @override
  Future<void> write(AppSettings settings) async => throw const SettingsPersistenceException();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin preferencias guardadas: idioma del sistema y tema del sistema', () async {
    final repo = LocalSettingsRepository(await SharedPreferences.getInstance());
    final settings = await repo.read();
    expect(settings.language, isNull);
    expect(settings.theme, AppThemePreference.system);
  });

  test('guarda y recupera idioma y tema', () async {
    final prefs = await SharedPreferences.getInstance();
    await LocalSettingsRepository(prefs)
        .write(const AppSettings(language: AppLanguage.en, theme: AppThemePreference.dark));

    final restored = await LocalSettingsRepository(prefs).read();
    expect(restored.language, AppLanguage.en);
    expect(restored.theme, AppThemePreference.dark);
  });

  test('ignora valores desconocidos guardados en el dispositivo', () async {
    SharedPreferences.setMockInitialValues({
      LocalSettingsRepository.languageKey: 'klingon',
      LocalSettingsRepository.themeKey: 'neon',
    });
    final settings = await LocalSettingsRepository(await SharedPreferences.getInstance()).read();
    expect(settings.language, isNull);
    expect(settings.theme, AppThemePreference.system);
  });

  test('el controlador expone locale y themeMode', () async {
    final controller = SettingsController(LocalSettingsRepository(await SharedPreferences.getInstance()));
    await controller.load();
    expect(controller.locale, isNull);

    expect(await controller.setLanguage(AppLanguage.en), isTrue);
    expect(controller.locale?.languageCode, 'en');

    expect(await controller.setTheme(AppThemePreference.dark), isTrue);
    expect(controller.themeMode.name, 'dark');
  });

  test('si falla la persistencia, informa del error sin perder el cambio en pantalla', () async {
    final controller = SettingsController(_FailingRepository());
    await controller.load();
    final ok = await controller.setLanguage(AppLanguage.en);
    expect(ok, isFalse);
    expect(controller.lastError, isA<SettingsPersistenceException>());
    expect(controller.locale?.languageCode, 'en');
  });
}
