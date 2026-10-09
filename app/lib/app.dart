import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/application/settings_controller.dart';

/// Raíz de la aplicación. Escucha las preferencias para cambiar idioma y tema
/// sin reiniciar.
class NaturistaApp extends StatefulWidget {
  const NaturistaApp({super.key, required this.settings, this.initialLocation});

  final SettingsController settings;

  /// Solo para pruebas: ruta inicial distinta de `/`.
  final String? initialLocation;

  @override
  State<NaturistaApp> createState() => _NaturistaAppState();
}

class _NaturistaAppState extends State<NaturistaApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          return MaterialApp.router(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: widget.settings.themeMode,
            locale: widget.settings.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
