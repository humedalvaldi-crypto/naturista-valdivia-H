import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('arranca en español con navegación inferior en teléfono', (tester) async {
    await pumpTestApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('¿Cómo funciona?'), findsOneWidget);
  });

  testWidgets('usa riel lateral en pantallas anchas', (tester) async {
    await pumpTestApp(tester, size: const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('cambia a inglés sin reiniciar y lo guarda', (tester) async {
    await pumpTestApp(tester, at: '/settings');

    expect(find.text('Configuración'), findsWidgets);
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalSettingsRepository.languageKey), 'en');
  });

  testWidgets('cambia el tema a oscuro', (tester) async {
    await pumpTestApp(tester, at: '/settings');

    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('los módulos no construidos se identifican como planificados', (tester) async {
    await pumpTestApp(tester, at: '/map');

    expect(find.text('Este módulo aún no está disponible'), findsOneWidget);
    expect(find.text('En desarrollo · Fase 7'), findsOneWidget);
  });

  testWidgets('ruta desconocida muestra página no encontrada', (tester) async {
    await pumpTestApp(tester, at: '/no-existe');

    expect(find.text('Página no encontrada'), findsOneWidget);
  });
}
