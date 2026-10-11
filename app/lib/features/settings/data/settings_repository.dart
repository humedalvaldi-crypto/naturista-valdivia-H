import 'package:shared_preferences/shared_preferences.dart';

/// Idiomas admitidos. Debe coincidir con `l10n/app_*.arb`.
/// [nativeName] se muestra siempre en el propio idioma.
enum AppLanguage {
  es('Español'),
  en('English'),
  arn('Mapudungun', draft: true),
  pt('Português', machine: true),
  fr('Français', machine: true),
  de('Deutsch', machine: true),
  it('Italiano', machine: true),
  zh('中文（简体）', machine: true),
  ja('日本語', machine: true),
  ko('한국어', machine: true),
  ar('العربية', machine: true),
  ru('Русский', machine: true),
  hi('हिन्दी', machine: true);

  const AppLanguage(this.nativeName, {this.draft = false, this.machine = false});

  final String nativeName;

  /// Traducción parcial que deben revisar hablantes (lo demás, en español).
  final bool draft;

  /// Traducción completa preparada con ayuda de IA.
  final bool machine;

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

/// Tamaño inicial de un sticker en la página (unidades del lienzo de 1000).
const stickerSizeOptions = [180.0, 260.0, 360.0];

/// Colores de portada de cuaderno (los mismos del diálogo "Nuevo cuaderno").
const notebookColorOptions = ['#2E5B2A', '#2F6F7E', '#8A5A2B', '#7A3E65', '#B3261E', '#C9A646'];

/// Preferencias guardadas en este dispositivo.
class AppSettings {
  const AppSettings({
    this.language,
    this.theme = AppThemePreference.system,
    this.onboardingDone = false,
    this.textScale = 1.0,
    this.highContrast = false,
    this.reduceMotion = false,
    this.mapBase = MapBasePreference.streets,
    this.mapShowObservations = true,
    this.mapShowPlaces = true,
    this.observationsPrivate = false,
    this.hideLocationByDefault = false,
    this.notebookColor = '#2E5B2A',
    this.notebookPublic = false,
    this.stickerSize = 260,
    this.favoriteStickers = const [],
    this.use24h = true,
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

  /// Mapa base y capas con que se abre el mapa de biodiversidad.
  final MapBasePreference mapBase;
  final bool mapShowObservations;
  final bool mapShowPlaces;

  /// Las observaciones nuevas empiezan como privadas / con la ubicación oculta.
  final bool observationsPrivate;
  final bool hideLocationByDefault;

  /// Color y visibilidad con que se crean los cuadernos nuevos.
  final String notebookColor;
  final bool notebookPublic;

  /// Tamaño con que se pega un sticker y stickers favoritos (aparecen primero).
  final double stickerSize;
  final List<String> favoriteStickers;

  /// Reloj de 24 horas (si no, de 12 horas con a. m./p. m.).
  final bool use24h;

  AppSettings copyWith({
    AppLanguage? language,
    AppThemePreference? theme,
    bool? onboardingDone,
    double? textScale,
    bool? highContrast,
    bool? reduceMotion,
    MapBasePreference? mapBase,
    bool? mapShowObservations,
    bool? mapShowPlaces,
    bool? observationsPrivate,
    bool? hideLocationByDefault,
    String? notebookColor,
    bool? notebookPublic,
    double? stickerSize,
    List<String>? favoriteStickers,
    bool? use24h,
  }) =>
      AppSettings(
        language: language ?? this.language,
        theme: theme ?? this.theme,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        mapBase: mapBase ?? this.mapBase,
        mapShowObservations: mapShowObservations ?? this.mapShowObservations,
        mapShowPlaces: mapShowPlaces ?? this.mapShowPlaces,
        observationsPrivate: observationsPrivate ?? this.observationsPrivate,
        hideLocationByDefault: hideLocationByDefault ?? this.hideLocationByDefault,
        notebookColor: notebookColor ?? this.notebookColor,
        notebookPublic: notebookPublic ?? this.notebookPublic,
        stickerSize: stickerSize ?? this.stickerSize,
        favoriteStickers: favoriteStickers ?? this.favoriteStickers,
        use24h: use24h ?? this.use24h,
      );

  List<Object?> get _props => [
        language, theme, onboardingDone, textScale, highContrast, reduceMotion, mapBase, mapShowObservations,
        mapShowPlaces, observationsPrivate, hideLocationByDefault, notebookColor, notebookPublic, stickerSize,
        use24h, ...favoriteStickers,
      ];

  @override
  bool operator ==(Object other) {
    if (other is! AppSettings || other.favoriteStickers.length != favoriteStickers.length) return false;
    final a = _props, b = other._props;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);
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
  static const mapShowObservationsKey = 'settings.mapShowObservations';
  static const mapShowPlacesKey = 'settings.mapShowPlaces';
  static const hideLocationKey = 'settings.hideLocationByDefault';
  static const notebookColorKey = 'settings.notebookColor';
  static const notebookPublicKey = 'settings.notebookPublic';
  static const stickerSizeKey = 'settings.stickerSize';
  static const favoriteStickersKey = 'settings.favoriteStickers';
  static const use24hKey = 'settings.use24h';

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
      mapShowObservations: _prefs.getBool(mapShowObservationsKey) ?? true,
      mapShowPlaces: _prefs.getBool(mapShowPlacesKey) ?? true,
      hideLocationByDefault: _prefs.getBool(hideLocationKey) ?? false,
      notebookColor: notebookColorOptions.contains(_prefs.getString(notebookColorKey))
          ? _prefs.getString(notebookColorKey)!
          : notebookColorOptions.first,
      notebookPublic: _prefs.getBool(notebookPublicKey) ?? false,
      stickerSize: stickerSizeOptions.contains(_prefs.getDouble(stickerSizeKey)) ? _prefs.getDouble(stickerSizeKey)! : 260,
      favoriteStickers: _prefs.getStringList(favoriteStickersKey) ?? const [],
      use24h: _prefs.getBool(use24hKey) ?? true,
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
      _prefs.setBool(mapShowObservationsKey, settings.mapShowObservations),
      _prefs.setBool(mapShowPlacesKey, settings.mapShowPlaces),
      _prefs.setBool(hideLocationKey, settings.hideLocationByDefault),
      _prefs.setString(notebookColorKey, settings.notebookColor),
      _prefs.setBool(notebookPublicKey, settings.notebookPublic),
      _prefs.setDouble(stickerSizeKey, settings.stickerSize),
      _prefs.setStringList(favoriteStickersKey, settings.favoriteStickers),
      _prefs.setBool(use24hKey, settings.use24h),
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
