import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

void main() {
  testWidgets('sin servidor, la comunidad lo dice y no inventa publicaciones', (tester) async {
    await pumpTestApp(tester, at: '/community');
    expect(find.text('La comunidad aún no está conectada'), findsOneWidget);
    expect(find.byKey(const Key('new-post')), findsNothing);
  });

  testWidgets('muestra las publicaciones del servidor', (tester) async {
    final server = FakeApiServer()
      ..addPost('Vi un huillín en el Calle-Calle')
      ..addPost('Copihues en flor');
    await pumpTestApp(tester, at: '/posts', api: server.client);
    expect(find.text('Copihues en flor'), findsOneWidget);
    expect(find.text('Vi un huillín en el Calle-Calle'), findsOneWidget);
  });

  testWidgets('sin sesión, "me gusta" pide iniciar sesión y no llama al servidor', (tester) async {
    final server = FakeApiServer();
    final p = server.addPost('Garza grande');
    await pumpTestApp(tester, at: '/posts', api: server.client);
    await tester.tap(find.byKey(Key('like-${p['id']}')));
    await tester.pump();
    expect(find.text('Inicia sesión para publicar, comentar y dar me gusta.'), findsOneWidget);
    expect(server.requests.where((r) => r.contains('/like')), isEmpty);
  });

  testWidgets('con sesión, "me gusta" actualiza el contador', (tester) async {
    final server = FakeApiServer();
    final p = server.addPost('Cisnes de cuello negro', likes: 2);
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/posts', api: server.client);
    expect(find.text('2 me gusta'), findsOneWidget);
    await tester.tap(find.byKey(Key('like-${p['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('3 me gusta'), findsOneWidget);
    expect(server.requests, contains('PUT /posts/${p['id']}/like'));
  });

  testWidgets('publicar agrega la publicación arriba del feed', (tester) async {
    final server = FakeApiServer()..addPost('Anterior');
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/posts', api: server.client);
    await tester.tap(find.byKey(const Key('new-post')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compose-body')), 'Primer chucao del día');
    await tester.tap(find.byKey(const Key('compose-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Primer chucao del día'), findsOneWidget);
    expect(server.requests, contains('POST /posts'));
  });

  testWidgets('comentar desde el detalle', (tester) async {
    final server = FakeApiServer();
    final p = server.addPost('¿Qué hongo es este?');
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/posts/${p['id']}', api: server.client);
    expect(find.text('Todavía no hay comentarios.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-input')), 'Parece una oreja de palo');
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('Parece una oreja de palo'), findsOneWidget);
    expect(find.text('1 comentario'), findsOneWidget);
  });

  testWidgets('si el servidor falla, muestra el error y permite reintentar', (tester) async {
    final server = FakeApiServer()
      ..addPost('Ranita de Darwin')
      ..failNext = true;
    await pumpTestApp(tester, at: '/posts', api: server.client);
    expect(find.text('Error interno del servidor.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Ranita de Darwin'), findsOneWidget);
  });

  testWidgets('unirse a una comunidad', (tester) async {
    final server = FakeApiServer()
      ..communities.add({'id': 'c1', 'slug': 'aves', 'name': 'Aves de Angachilla', 'memberCount': 3, 'myRole': null});
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/communities', api: server.client);
    expect(find.text('3 miembros'), findsOneWidget);
    await tester.tap(find.text('Unirme'));
    await tester.pumpAndSettle();
    expect(find.text('4 miembros'), findsOneWidget);
    expect(find.text('Salir'), findsOneWidget);
  });

  testWidgets('notificaciones: lista y marcar todo como leído', (tester) async {
    final server = FakeApiServer()
      ..notifications.add({
        'id': 'n1',
        'type': 'follow',
        'actor': FakeApiServer.person('u2', 'Beto'),
        'postId': null,
        'conversationId': null,
        'createdAt': DateTime.utc(2026, 10, 9).toIso8601String(),
        'read': false,
      });
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notifications', api: server.client);
    expect(find.text('Beto comenzó a seguirte'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mark-all-read')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST /me/notifications/read'));
  });

  testWidgets('avisos de la app anterior muestran su texto y abren el cuaderno', (tester) async {
    final server = FakeApiServer();
    final nb = server.addNotebook('Bitácora de Beto', ownerId: 'u2');
    nb['visibility'] = 'public';
    server.notifications.add({
      'id': 'n-legacy',
      'type': 'system',
      'actor': null,
      'postId': null,
      'conversationId': null,
      'notebookId': nb['id'],
      'body': 'A Beto le gustó tu cuaderno',
      'createdAt': DateTime.utc(2025, 6, 1).toIso8601String(),
      'read': true,
    });
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notifications', api: server.client);
    expect(find.text('A Beto le gustó tu cuaderno'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-n-legacy')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET /notebooks/${nb['id']}'));
  });
}
