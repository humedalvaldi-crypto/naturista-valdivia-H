import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/core/router/app_router.dart';
import 'package:naturista_valdivia/features/auth/application/auth_controller.dart';

String? go(String location, {AuthStatus status = AuthStatus.signedOut, bool onboarding = true, bool verify = false}) =>
    resolveRedirect(
      status: status,
      needsEmailVerification: verify,
      onboardingDone: onboarding,
      location: Uri.parse(location),
    );

void main() {
  test('mientras se restaura la sesión muestra el splash y recuerda la ruta', () {
    expect(go('/profile', status: AuthStatus.unknown), '/splash?from=%2Fprofile');
    expect(go('/splash', status: AuthStatus.unknown), isNull);
  });

  test('sale del splash hacia la ruta pedida', () {
    expect(go('/splash?from=%2Fsettings'), '/settings');
    expect(go('/splash'), '/');
  });

  test('bienvenida obligatoria la primera vez', () {
    expect(go('/', onboarding: false), '/welcome');
    expect(go('/welcome', onboarding: false), isNull);
    expect(go('/welcome'), '/');
  });

  test('ver observaciones no exige sesión', () {
    expect(go('/observations'), isNull);
    expect(go('/observations/o1'), isNull);
  });

  test('rutas privadas exigen sesión', () {
    for (final r in ['/profile', '/notebooks', '/messages', '/notifications', '/drawing', '/observations/new', '/observations/o1/edit', '/notebook-pages/pg1', '/notebooks/nb1', '/verify-email']) {
      expect(go(r), startsWith('/login?from='), reason: r);
      expect(go(r, status: AuthStatus.signedIn), isNull, reason: r);
    }
  });

  test('rutas públicas no exigen sesión', () {
    for (final r in ['/', '/map', '/community', '/settings', '/login', '/register']) {
      expect(go(r), isNull, reason: r);
    }
  });

  test('con sesión, el login vuelve a la ruta original', () {
    expect(go('/login?from=%2Fnotebooks', status: AuthStatus.signedIn), '/notebooks');
    expect(go('/login', status: AuthStatus.signedIn), '/');
  });

  test('registro con correo sin verificar va a verificar', () {
    expect(go('/register', status: AuthStatus.signedIn, verify: true), '/verify-email');
  });

  test('no permite redirecciones a otros sitios', () {
    expect(go('/login?from=https%3A%2F%2Fmalicioso.example', status: AuthStatus.signedIn), '/');
    expect(go('/login?from=%2F%2Fmalicioso.example', status: AuthStatus.signedIn), '/');
  });
}
