import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_config.dart';
import 'core/l10n/fallback_localizations.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/network/api_client.dart';
import 'core/network/api_scope.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/security/application/app_lock_controller.dart';
import 'features/security/application/consent_controller.dart';
import 'features/security/presentation/lock_screen.dart';
import 'features/settings/application/settings_controller.dart';

/// Raíz de la aplicación. Escucha las preferencias para cambiar idioma y tema
/// sin reiniciar, y la sesión para proteger las rutas privadas.
class NaturistaApp extends StatefulWidget {
  const NaturistaApp({
    super.key,
    required this.settings,
    required this.auth,
    this.api,
    this.initialLocation,
  });

  final SettingsController settings;
  final AuthController auth;

  /// Cliente de la API. Por defecto usa `API_BASE_URL` (vacío = sin servidor).
  final ApiClient? api;

  /// Solo para pruebas: ruta inicial distinta de la del navegador.
  final String? initialLocation;

  @override
  State<NaturistaApp> createState() => _NaturistaAppState();
}

class _NaturistaAppState extends State<NaturistaApp> {
  late final ApiClient _api =
      widget.api ?? ApiClient(baseUrl: AppConfig.apiBaseUrl, auth: widget.auth.repository);

  late final ConsentController _consent = ConsentController(widget.auth, _api);
  late final AppLockController _lock = AppLockController(widget.auth);

  late final GoRouter _router = buildRouter(
    auth: widget.auth,
    settings: widget.settings,
    consent: _consent,
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _consent.dispose();
    _lock.dispose();
    if (widget.api == null) _api.close();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: widget.settings,
      child: AuthScope(
        controller: widget.auth,
        child: ApiScope(
          client: _api,
          child: ConsentScope(
          controller: _consent,
          child: AppLockScope(
          controller: _lock,
          child: ListenableBuilder(
          listenable: Listenable.merge([widget.settings, _lock]),
          builder: (context, _) {
            final prefs = widget.settings.settings;
            return MaterialApp.router(
              onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.resolve(
                brightness: Brightness.light,
                highContrast: prefs.highContrast,
                reduceMotion: prefs.reduceMotion,
              ),
              darkTheme: AppTheme.resolve(
                brightness: Brightness.dark,
                highContrast: prefs.highContrast,
                reduceMotion: prefs.reduceMotion,
              ),
              themeMode: widget.settings.themeMode,
              locale: widget.settings.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                FallbackMaterialLocalizationsDelegate(),
                FallbackCupertinoLocalizationsDelegate(),
                FallbackWidgetsLocalizationsDelegate(),
              ],
                routerConfig: _router,
                // Tamaño de texto y movimiento elegidos en Configuración.
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  final systemScale = media.textScaler.scale(1);
                  return MediaQuery(
                    data: media.copyWith(
                      textScaler: TextScaler.linear((systemScale * prefs.textScale).clamp(0.8, 2.0)),
                      disableAnimations: media.disableAnimations || prefs.reduceMotion,
                      highContrast: media.highContrast || prefs.highContrast,
                      alwaysUse24HourFormat: prefs.use24h,
                    ),
                    // Con el bloqueo activo no se construye nada de la app detrás.
                    // Con el bloqueo, la app sigue montada (no se pierde lo abierto)
                    // pero ni se pinta, ni se anuncia, ni anima.
                    child: Stack(fit: StackFit.expand, children: [
                      Offstage(
                        offstage: _lock.locked,
                        child: ExcludeSemantics(
                          excluding: _lock.locked,
                          child: TickerMode(enabled: !_lock.locked, child: child ?? const SizedBox.shrink()),
                        ),
                      ),
                      if (_lock.locked)
                        Overlay(key: const ValueKey('lock-overlay'), initialEntries: [OverlayEntry(builder: (_) => LockScreen(controller: _lock))]),
                    ]),
                  );
                },
              );
            },
          ),
          ),
          ),
        ),
      ),
    );
  }
}
