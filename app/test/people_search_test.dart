import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/social/presentation/post_actions.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('people-search-input')), text);
  await tester.pump(const Duration(milliseconds: 350)); // espera de 300 ms antes de buscar
  await tester.pumpAndSettle();
}

void main() {
  group('buscador de personas', () {
    testWidgets('busca, pagina con "Cargar más" y sigue desde la lista', (tester) async {
      final server = FakeApiServer()
        ..addPerson('u2', 'Beto Pérez', followsMe: true)
        ..addPerson('u3', 'Bea Soto')
        ..addPerson('u4', 'Bernardo Ruiz')
        ..addPerson('u5', 'Carla Díaz');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/search', api: server.client);

      await _type(tester, 'be');
      expect(find.byKey(const Key('person-result-u2')), findsOneWidget);
      expect(find.byKey(const Key('person-result-u3')), findsOneWidget);
      expect(find.byKey(const Key('person-result-u4')), findsNothing);
      expect(find.textContaining('Te sigue'), findsOneWidget);
      expect(find.text('Seguir también'), findsOneWidget);

      expect(
        find.byKey(const Key('people-load-more')),
        findsOneWidget,
        reason: 'peticiones: ${server.requests} · textos: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
      await tester.tap(find.byKey(const Key('people-load-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-result-u4')), findsOneWidget);
      expect(find.byKey(const Key('person-result-u5')), findsNothing);
      expect(find.byKey(const Key('people-load-more')), findsNothing);

      await tester.tap(find.byKey(const Key('follow-u3')));
      await tester.pumpAndSettle();
      expect(server.requests, contains('PUT /users/u3/follow'));
      expect(find.byKey(const Key('unfollow-u3')), findsOneWidget);
    });

    testWidgets('con menos de 2 letras no consulta al servidor', (tester) async {
      final server = FakeApiServer()..addPerson('u2', 'Beto Pérez');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/search', api: server.client);
      final before = server.requests.where((r) => r == 'GET /users').length; // directorio inicial
      await _type(tester, 'b');
      expect(find.text('Escribe al menos 2 letras para buscar.'), findsOneWidget);
      expect(server.requests.where((r) => r == 'GET /users').length, before);
    });

    testWidgets('sin resultados muestra un aviso', (tester) async {
      final server = FakeApiServer()..addPerson('u2', 'Beto Pérez');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/search', api: server.client);
      await _type(tester, 'zz');
      expect(find.text('No encontramos personas con ese nombre.'), findsOneWidget);
    });

    testWidgets('sugerencias reales con personas en común', (tester) async {
      final server = FakeApiServer()..addPerson('u7', 'Dani Mora');
      server.suggestionMutuals['u7'] = 2;
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/search', api: server.client);
      expect(find.text('Sugerencias para ti'), findsOneWidget);
      expect(find.textContaining('2 en común'), findsOneWidget);
    });
  });

  group('perfil: relación en ambos sentidos', () {
    testWidgets('me sigue y no la sigo: "Te sigue" y "Seguir también"', (tester) async {
      final server = FakeApiServer()..addPerson('u2', 'Beto Pérez', followsMe: true);
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u2', api: server.client);
      expect(find.byKey(const Key('follows-you')), findsOneWidget);
      expect(find.text('Seguir también'), findsOneWidget);
    });

    testWidgets('no me sigue: sin chip y botón "Seguir"', (tester) async {
      final server = FakeApiServer()..addPerson('u2', 'Beto Pérez');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u2', api: server.client);
      expect(find.byKey(const Key('follows-you')), findsNothing);
      expect(find.text('Seguir'), findsOneWidget);
    });

    testWidgets('dejar de seguir pide confirmación y respeta "Cancelar"', (tester) async {
      final server = FakeApiServer()..addPerson('u2', 'Beto Pérez', followers: 3, followsMe: true);
      server.people['u2']!['followedByMe'] = true;
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u2', api: server.client);
      expect(find.byKey(const Key('follows-you')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unfollow')));
      await tester.pumpAndSettle();
      expect(find.text('¿Dejar de seguir a Beto Pérez?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.startsWith('DELETE')), isEmpty);

      await tester.tap(find.byKey(const Key('unfollow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unfollow-confirm')));
      await tester.pumpAndSettle();
      expect(server.requests, contains('DELETE /users/u2/follow'));
      expect(find.text('2 seguidores'), findsOneWidget); // contador leído del servidor
      expect(find.text('Seguir también'), findsOneWidget);
    });
  });

  group('publicaciones: editar y compartir', () {
    tearDown(() => LinkSharer.share = (link, subject) async => false);

    testWidgets('edita una publicación propia y muestra "editado"', (tester) async {
      final server = FakeApiServer();
      final p = server.addPost('Garza en el humedal', authorId: 'u1', authorName: 'Eva');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/posts', api: server.client);

      await tester.tap(find.byKey(Key('post-menu-${p['id']}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('post-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit-post-body')), 'Garza cuca en el humedal');
      await tester.tap(find.byKey(const Key('edit-post-save')));
      await tester.pumpAndSettle();

      final sent = server.requestBodies['PATCH /posts/${p['id']}']!;
      expect(sent, {'body': 'Garza cuca en el humedal'}); // solo lo que cambió
      expect(find.text('Garza cuca en el humedal'), findsOneWidget);
      expect(find.textContaining('editado'), findsOneWidget);
    });

    testWidgets('en publicaciones ajenas no se puede editar, pero sí compartir el enlace', (tester) async {
      Uri? shared;
      LinkSharer.share = (link, subject) async {
        shared = link;
        return true;
      };
      final server = FakeApiServer();
      final p = server.addPost('Huillín en el río');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/posts', api: server.client);

      await tester.tap(find.byKey(Key('post-menu-${p['id']}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('post-edit')), findsNothing);
      expect(find.byKey(const Key('post-delete')), findsNothing);
      await tester.tap(find.byKey(const Key('post-share')));
      await tester.pumpAndSettle();
      expect(shared.toString(), endsWith('#/posts/${p['id']}'));
      expect(find.text('Enlace copiado.'), findsOneWidget);
    });
  });
}
