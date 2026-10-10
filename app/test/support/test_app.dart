import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/app.dart';
import 'package:naturista_valdivia/core/network/api_client.dart';
import 'package:naturista_valdivia/features/auth/application/auth_controller.dart';
import 'package:naturista_valdivia/features/settings/application/settings_controller.dart';
import 'package:naturista_valdivia/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

class TestHarness {
  TestHarness(this.settings, this.auth, this.repo);
  final SettingsController settings;
  final AuthController auth;
  final FakeAuthRepository repo;
}

/// Monta la app completa con autenticación falsa. Por defecto en español,
/// con la bienvenida ya vista y en un teléfono (400×800).
Future<TestHarness> pumpTestApp(
  WidgetTester tester, {
  FakeAuthRepository? repo,
  String? at,
  bool onboardingDone = true,
  String language = 'es',
  Size size = const Size(400, 800),
  ApiClient Function(FakeAuthRepository repo)? api,
}) async {
  SharedPreferences.setMockInitialValues({
    LocalSettingsRepository.languageKey: language,
    LocalSettingsRepository.onboardingKey: onboardingDone,
  });
  final settings = SettingsController(LocalSettingsRepository(await SharedPreferences.getInstance()));
  await settings.load();
  final fake = repo ?? FakeAuthRepository();
  final auth = AuthController(fake);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(NaturistaApp(settings: settings, auth: auth, api: api?.call(fake), initialLocation: at));
  await tester.pumpAndSettle();
  return TestHarness(settings, auth, fake);
}
