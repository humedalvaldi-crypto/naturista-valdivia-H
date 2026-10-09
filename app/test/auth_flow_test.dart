import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)), text);
}

void main() {
  testWidgets('primer arranque: muestra la bienvenida una sola vez', (tester) async {
    final h = await pumpTestApp(tester, onboardingDone: false);
    expect(find.text('Descubre los humedales de Valdivia'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo funciona?'), findsOneWidget);
    expect(h.settings.settings.onboardingDone, isTrue);
  });

  testWidgets('una ruta privada sin sesión lleva al login y vuelve tras entrar', (tester) async {
    await pumpTestApp(tester, at: '/profile');
    expect(find.text('Bienvenido de vuelta, naturalista.'), findsOneWidget);

    await _enter(tester, 'login-email', 'ana@example.test');
    await _enter(tester, 'login-password', 'secreta123');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.byKey(const Key('sign-out')), findsOneWidget);
  });

  testWidgets('credenciales incorrectas muestran un error claro', (tester) async {
    await pumpTestApp(tester, at: '/login');

    await _enter(tester, 'login-email', 'ana@example.test');
    await _enter(tester, 'login-password', 'equivocada');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('valida el formulario antes de enviarlo', (tester) async {
    await pumpTestApp(tester, at: '/login');

    await _enter(tester, 'login-email', 'no-es-un-correo');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
  });

  testWidgets('Google cancelado por el usuario no muestra error', (tester) async {
    final repo = FakeAuthRepository()..googleError = const AuthException(AuthErrorCode.cancelled);
    await pumpTestApp(tester, repo: repo, at: '/login');

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Bienvenido de vuelta, naturalista.'), findsOneWidget);
  });

  testWidgets('entrar con Google lleva al inicio con saludo', (tester) async {
    await pumpTestApp(tester, at: '/login');

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Gabi'), findsOneWidget);
  });

  testWidgets('registro con correo pide verificar el correo', (tester) async {
    final h = await pumpTestApp(tester, at: '/register');

    await _enter(tester, 'register-name', 'Nueva Persona');
    await _enter(tester, 'register-email', 'nueva@example.test');
    await _enter(tester, 'register-password', 'clave-larga-1');
    await _enter(tester, 'register-confirm', 'clave-larga-1');
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Verifica tu correo'), findsOneWidget);
    expect(h.repo.verificationEmails, 1);
  });

  testWidgets('registro rechaza contraseñas cortas o distintas', (tester) async {
    await pumpTestApp(tester, at: '/register');

    await _enter(tester, 'register-name', 'X');
    await _enter(tester, 'register-email', 'x@example.test');
    await _enter(tester, 'register-password', 'corta');
    await _enter(tester, 'register-confirm', 'otra');
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
  });

  testWidgets('recuperar contraseña envía el enlace', (tester) async {
    final h = await pumpTestApp(tester, at: '/forgot-password');

    await _enter(tester, 'forgot-email', 'ana@example.test');
    await tester.tap(find.byKey(const Key('forgot-submit')));
    await tester.pumpAndSettle();

    expect(h.repo.resetEmails, ['ana@example.test']);
    expect(find.textContaining('ana@example.test'), findsOneWidget);
  });

  testWidgets('restaura la sesión guardada al abrir la app', (tester) async {
    final repo = FakeAuthRepository(
      initialUser: const AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true),
    );
    await pumpTestApp(tester, repo: repo, at: '/profile');

    expect(find.text('Eva'), findsOneWidget);
  });

  testWidgets('cerrar sesión pide confirmación y protege el perfil', (tester) async {
    final repo = FakeAuthRepository(
      initialUser: const AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true),
    );
    final h = await pumpTestApp(tester, repo: repo, at: '/profile');

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();

    expect(h.auth.isSignedIn, isFalse);
    expect(find.text('Bienvenido de vuelta, naturalista.'), findsOneWidget);
  });

  testWidgets('con sesión iniciada, /login redirige al inicio', (tester) async {
    final repo = FakeAuthRepository(
      initialUser: const AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true),
    );
    await pumpTestApp(tester, repo: repo, at: '/login');

    expect(find.text('Hola, Eva'), findsOneWidget);
  });
}
