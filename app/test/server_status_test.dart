import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naturista_valdivia/core/network/api_client.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

void main() {
  testWidgets('sin API configurada lo indica en el perfil', (tester) async {
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile');
    expect(find.textContaining('todavía no se sincroniza'), findsOneWidget);
  });

  testWidgets('con API, registra la cuenta con el token y lo confirma', (tester) async {
    String? auth;
    await pumpTestApp(
      tester,
      repo: FakeAuthRepository(initialUser: _eva),
      at: '/profile',
      api: (repo) => ApiClient(
        baseUrl: 'https://api.example.test',
        auth: repo,
        client: MockClient((req) async {
          auth = req.headers['Authorization'];
          return http.Response(jsonEncode({'data': {'user': {'id': 'u1'}}}), 200);
        }),
      ),
    );
    expect(auth, 'Bearer token-cached');
    expect(find.text('Cuenta sincronizada con el servidor de Naturista Valdivia.'), findsOneWidget);
  });

  testWidgets('si el servidor falla, lo dice y permite reintentar', (tester) async {
    var calls = 0;
    await pumpTestApp(
      tester,
      repo: FakeAuthRepository(initialUser: _eva),
      at: '/profile',
      api: (repo) => ApiClient(
        baseUrl: 'https://api.example.test',
        auth: repo,
        client: MockClient((req) async {
          calls++;
          return calls == 1
              ? http.Response(jsonEncode({'error': {'code': 'internal_error', 'message': 'Error interno del servidor.'}}), 500)
              : http.Response('{}', 200);
        }),
      ),
    );
    expect(find.textContaining('No se pudo sincronizar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Cuenta sincronizada con el servidor de Naturista Valdivia.'), findsOneWidget);
  });
}
