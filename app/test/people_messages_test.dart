import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/shared/media/photo_picker.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 0xff, 0xd9]);

void main() {
  tearDown(() => PhotoPicker.pick = () async => null);

  test('detecta el tipo real de la imagen', () {
    expect(sniffImageType(_jpeg), 'image/jpeg');
    expect(sniffImageType(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'image/png');
    expect(sniffImageType(Uint8List.fromList('<html></html>'.codeUnits)), isNull);
  });

  testWidgets('publicar con foto: sube la imagen y la adjunta a la publicación', (tester) async {
    PhotoPicker.pick = () async => PickedPhoto(bytes: _jpeg, contentType: 'image/jpeg', name: 'garza.jpg');
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client);

    await tester.tap(find.byKey(const Key('new-post')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('compose-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    await tester.enterText(find.byKey(const Key('compose-body')), 'Garza en el humedal');
    await tester.tap(find.byKey(const Key('compose-submit')));
    await tester.pumpAndSettle();

    final media = server.requests.indexOf('POST /media');
    final post = server.requests.indexOf('POST /posts');
    expect(media, greaterThanOrEqualTo(0));
    expect(post, greaterThan(media));
    expect(server.requestBodies['POST /posts']!['mediaAssetId'], startsWith('m-'));
  });

  testWidgets('perfil de otra persona: seguir actualiza el botón y el contador', (tester) async {
    final server = FakeApiServer()..addPerson('u2', 'Beto Pérez', followers: 4);
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u2', api: server.client);
    expect(find.text('Beto Pérez'), findsWidgets);
    expect(find.text('4 seguidores'), findsOneWidget);

    await tester.tap(find.byKey(const Key('follow')));
    await tester.pumpAndSettle();
    expect(find.text('5 seguidores'), findsOneWidget);
    expect(find.byKey(const Key('unfollow')), findsOneWidget);
  });

  testWidgets('sin sesión, seguir lleva al inicio de sesión', (tester) async {
    final server = FakeApiServer()..addPerson('u2', 'Beto Pérez');
    await pumpTestApp(tester, at: '/people/u2', api: server.client);
    await tester.tap(find.byKey(const Key('follow')));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido de vuelta, naturalista.'), findsOneWidget);
    expect(server.requests.where((r) => r.contains('/follow')), isEmpty);
  });

  testWidgets('escribir un mensaje desde el perfil', (tester) async {
    final server = FakeApiServer()..addPerson('u2', 'Beto Pérez');
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u2', api: server.client);

    await tester.tap(find.byKey(const Key('message-person')));
    await tester.pumpAndSettle();
    expect(find.text('Escribe el primer mensaje.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat-input')), '¿Vamos a Angachilla el sábado?');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('¿Vamos a Angachilla el sábado?'), findsOneWidget);
    expect(server.requests.where((r) => r.startsWith('POST /conversations/')).length, greaterThanOrEqualTo(1));
  });

  testWidgets('lista de conversaciones con no leídos', (tester) async {
    final server = FakeApiServer()
      ..conversations.add({
        'id': 'conv-x',
        'with': FakeApiServer.person('u3', 'Caro'),
        'lastMessage': 'Mira este hongo',
        'lastMessageAt': DateTime.utc(2026, 10, 9).toIso8601String(),
        'unread': 2,
      });
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/messages', api: server.client);
    expect(find.text('Caro'), findsOneWidget);
    expect(find.text('Mira este hongo'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
