import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naturista_valdivia/core/network/api_client.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';

FakeAuthRepository _signedIn() => FakeAuthRepository(initialUser: const AuthUser(uid: 'u1'));

void main() {
  test('adjunta el token de Firebase', () async {
    String? seen;
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      auth: _signedIn(),
      client: MockClient((req) async {
        seen = req.headers['Authorization'];
        expect(req.url.toString(), 'https://api.example.test/api/v1/me');
        return http.Response(jsonEncode({'data': {'ok': true}}), 200);
      }),
    );
    final body = await client.get('/me');
    expect(seen, 'Bearer token-cached');
    expect(body['data'], {'ok': true});
  });

  test('ante 401 renueva el token y reintenta una vez', () async {
    final repo = _signedIn();
    final tokens = <String?>[];
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      auth: repo,
      client: MockClient((req) async {
        tokens.add(req.headers['Authorization']);
        return tokens.length == 1
            ? http.Response(jsonEncode({'error': {'code': 'unauthorized', 'message': 'x'}}), 401)
            : http.Response('{}', 200);
      }),
    );
    await client.get('/me');
    expect(tokens, ['Bearer token-cached', 'Bearer token-fresh']);
    expect(repo.forcedRefreshes, 1);
  });

  test('si sigue en 401 tras renovar, informa el error sin bucles', () async {
    var calls = 0;
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      auth: _signedIn(),
      client: MockClient((req) async {
        calls++;
        return http.Response(jsonEncode({'error': {'code': 'unauthorized', 'message': 'Token inválido.'}}), 401);
      }),
    );
    await expectLater(client.get('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unauthorized')));
    expect(calls, 2);
  });

  test('sin sesión no llama a la API', () async {
    var calls = 0;
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      auth: FakeAuthRepository(),
      client: MockClient((req) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(client.get('/me'), throwsA(isA<ApiException>()));
    expect(calls, 0);
  });

  test('sin URL configurada lo indica', () async {
    final client = ApiClient(baseUrl: '', auth: _signedIn());
    await expectLater(client.get('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_configured')));
  });

  test('errores de red se traducen', () async {
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      auth: _signedIn(),
      client: MockClient((req) async => throw http.ClientException('offline')),
    );
    await expectLater(client.get('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network_error')));
  });
}
