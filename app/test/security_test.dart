import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/security/data/biometric_auth.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

/// Biometría de prueba: devuelve los resultados programados, en orden.
/// Solo existe en las pruebas; la app usa la del sistema operativo.
class _ScriptedBiometrics implements BiometricAuth {
  _ScriptedBiometrics(this.results, {this.availability_ = BiometricAvailability.available});

  final List<BiometricResult> results;
  final BiometricAvailability availability_;
  int prompts = 0;

  @override
  Future<BiometricAvailability> availability() async => availability_;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts++;
    expect(reason, isNotEmpty);
    return results.isEmpty ? BiometricResult.cancelled : results.removeAt(0);
  }
}

void main() {
  late MemoryBiometricStore store;
  setUp(() {
    store = MemoryBiometricStore();
    BiometricStore.instance = store;
  });
  tearDown(() => BiometricAuth.instance = const UnsupportedBiometricAuth());

  testWidgets('con el desbloqueo activo, la app abre bloqueada y la huella la abre', (tester) async {
    store.uid = 'u1';
    final bio = _ScriptedBiometrics([BiometricResult.success]);
    BiometricAuth.instance = bio;
    final repo = FakeAuthRepository(initialUser: _eva);
    await pumpTestApp(tester, repo: repo, at: '/profile');

    // Se pidió la huella al aparecer y se comprobó la sesión con Firebase.
    expect(bio.prompts, 1);
    expect(repo.forcedRefreshes, greaterThan(0));
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(find.byKey(const Key('my-album')), findsOneWidget);
  });

  testWidgets('mientras está bloqueada no se ve el contenido; cancelar no desbloquea', (tester) async {
    store.uid = 'u1';
    BiometricAuth.instance = _ScriptedBiometrics([BiometricResult.cancelled]);
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    expect(find.byKey(const Key('my-album')), findsNothing); // fuera de escena: ni se pinta ni se lee
    expect(find.byKey(const Key('lock-message')), findsNothing);
  });

  testWidgets('tras 5 intentos fallidos exige entrar con la cuenta', (tester) async {
    store.uid = 'u1';
    final bio = _ScriptedBiometrics(List.filled(5, BiometricResult.failed, growable: true));
    BiometricAuth.instance = bio;
    final h = await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    expect(find.textContaining('Quedan 4 intentos'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('lock-unlock')));
      await tester.pumpAndSettle();
    }
    expect(bio.prompts, 5);
    expect(h.auth.user, isNull);
    expect(store.uid, isNull);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
  });

  testWidgets('bloqueo del sistema por intentos: pide la cuenta sin revelar detalles', (tester) async {
    store.uid = 'u1';
    BiometricAuth.instance = _ScriptedBiometrics([BiometricResult.lockedOut]);
    final h = await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    expect(h.auth.user, isNull);
    expect(store.uid, isNull);
  });

  testWidgets('si la sesión de Firebase fue revocada, la huella no basta', (tester) async {
    store.uid = 'u1';
    BiometricAuth.instance = _ScriptedBiometrics([BiometricResult.success]);
    final repo = FakeAuthRepository(initialUser: _eva)..revoked = true;
    final h = await pumpTestApp(tester, repo: repo, at: '/profile');
    expect(h.auth.user, isNull);
    expect(store.uid, isNull);
  });

  testWidgets('"Entrar con mi cuenta" cierra la sesión y desactiva el desbloqueo', (tester) async {
    store.uid = 'u1';
    BiometricAuth.instance = _ScriptedBiometrics([BiometricResult.cancelled]);
    final h = await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    await tester.tap(find.byKey(const Key('lock-use-account')));
    await tester.pumpAndSettle();
    expect(h.auth.user, isNull);
    expect(store.uid, isNull);
  });

  testWidgets('el desbloqueo de otra cuenta no se usa', (tester) async {
    store.uid = 'otra-cuenta';
    final bio = _ScriptedBiometrics([BiometricResult.success]);
    BiometricAuth.instance = bio;
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    expect(bio.prompts, 0);
    expect(store.uid, isNull);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
  });

  testWidgets('activar en Seguridad exige huella válida; se guarda solo el UID', (tester) async {
    final bio = _ScriptedBiometrics([BiometricResult.cancelled, BiometricResult.success]);
    BiometricAuth.instance = bio;
    final repo = FakeAuthRepository(initialUser: _eva);
    await pumpTestApp(tester, repo: repo, at: '/settings/security', api: FakeApiServer().client);

    await tester.tap(find.byKey(const Key('biometric-switch')));
    await tester.pumpAndSettle();
    expect(store.uid, isNull);
    expect(find.text('Cancelado: no se activó.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('biometric-switch')));
    await tester.pumpAndSettle();
    expect(store.uid, 'u1');
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('biometric-switch'))).value, isTrue);

    await tester.tap(find.byKey(const Key('biometric-switch')));
    await tester.pumpAndSettle();
    expect(store.uid, isNull);
  });

  testWidgets('en el navegador o sin sensor: se muestra como no compatible', (tester) async {
    BiometricAuth.instance = const UnsupportedBiometricAuth();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings/security', api: FakeApiServer().client);
    final tile = tester.widget<SwitchListTile>(find.byKey(const Key('biometric-switch')));
    expect(tile.onChanged, isNull);
    expect(find.textContaining('No compatible'), findsOneWidget);
  });

  testWidgets('cerrar sesión en todos los dispositivos', (tester) async {
    final server = FakeApiServer();
    final h = await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings/security', api: server.client);
    await tester.ensureVisible(find.byKey(const Key('security-revoke-all')));
    await tester.tap(find.byKey(const Key('security-revoke-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-revoke-all')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST /me/sessions/revoke'));
    expect(h.auth.user, isNull);
  });

  testWidgets('términos pendientes: no se entra a la app sin aceptar ambas casillas', (tester) async {
    final server = FakeApiServer()..consent = {'requiredVersion': '2026-10', 'minAge': 14, 'upToDate': false};
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebooks', api: server.client);
    expect(find.text('Términos de uso'), findsOneWidget);
    expect(find.textContaining('Tengo 14 años o más'), findsOneWidget);

    final accept = find.byKey(const Key('consent-accept'));
    await tester.scrollUntilVisible(accept, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('consent-terms')));
    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('consent-age')));
    await tester.tap(find.byKey(const Key('consent-age')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(server.requestBodies['POST /me/consent'], {'version': '2026-10', 'termsAccepted': true, 'ageConfirmed': true});
    expect(find.text('Términos de uso'), findsNothing);
    expect(server.requests, contains('GET /notebooks')); // vuelve a donde iba
  });

  testWidgets('los términos se pueden leer antes de aceptarlos', (tester) async {
    final server = FakeApiServer()..consent = {'requiredVersion': '2026-10', 'minAge': 14, 'upToDate': false};
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/', api: server.client);
    await tester.ensureVisible(find.byKey(const Key('consent-read-terms')));
    await tester.tap(find.byKey(const Key('consent-read-terms')));
    await tester.pumpAndSettle();
    expect(find.text('Privacidad y condiciones'), findsWidgets);
  });
}
