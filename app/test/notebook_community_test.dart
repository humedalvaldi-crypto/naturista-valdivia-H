import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/social/presentation/post_actions.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);
const _tall = Size(500, 2600);

/// Comunidad de prueba: cuadernos públicos de otras personas (como los de la
/// app antigua), uno privado y uno propio.
FakeApiServer _community() {
  final s = FakeApiServer()
    ..addPerson('u2', 'Marcela Prueba', followers: 3)
    ..addPerson('u3', 'Beto Prueba');
  Map<String, dynamic> pub(String title, String owner, {int likes = 0, String? category = 'Biodiversidad'}) {
    final nb = s.addNotebook(title, ownerId: owner);
    nb['visibility'] = 'public';
    nb['likeCount'] = likes;
    nb['category'] = category;
    nb['pageCount'] = 1;
    return nb;
  }

  pub('Rocura', 'u2');
  pub('Puente Pedro de Valdivia', 'u2', likes: 2);
  pub('Humedal Angachilla', 'u3', category: null);
  s.addNotebook('Notas privadas de Beto', ownerId: 'u3'); // privado: no debe aparecer
  return s;
}

void main() {
  tearDown(() => LinkSharer.share = (link, subject) async => false);

  group('Explorar', () {
    testWidgets('muestra los cuadernos públicos reales con autora, categoría, páginas y «me gusta»; pagina', (tester) async {
      final server = _community();
      await pumpTestApp(tester, at: '/community', api: server.client, size: _tall);

      expect(find.text('Humedal Angachilla'), findsOneWidget);
      expect(find.text('Puente Pedro de Valdivia'), findsOneWidget);
      expect(find.text('Rocura'), findsNothing); // tercera: en la página siguiente
      expect(find.text('Notas privadas de Beto'), findsNothing);
      expect(find.text('Marcela Prueba'), findsOneWidget);
      expect(find.text('BIODIVERSIDAD'), findsOneWidget);
      expect(find.text('2 me gusta'), findsOneWidget);

      await tester.tap(find.byKey(const Key('explore-load-more')));
      await tester.pumpAndSettle();
      expect(find.text('Rocura'), findsOneWidget);
      expect(find.byKey(const Key('explore-load-more')), findsNothing);
      expect(find.text('Notas privadas de Beto'), findsNothing);
    });

    testWidgets('«me gusta» persistente con sesión; sin sesión pide entrar y no llama', (tester) async {
      final server = _community();
      final nb = server.notebooks.firstWhere((n) => n['title'] == 'Puente Pedro de Valdivia');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(Key('nb-like-${nb['id']}')));
      await tester.pumpAndSettle();
      expect(server.requests, contains('PUT /notebooks/${nb['id']}/like'));
      expect(find.text('3 me gusta'), findsOneWidget);
      await tester.tap(find.byKey(Key('nb-like-${nb['id']}')));
      await tester.pumpAndSettle();
      expect(server.requests, contains('DELETE /notebooks/${nb['id']}/like'));
      expect(find.text('2 me gusta'), findsOneWidget);
    });

    testWidgets('sin sesión, «me gusta» lleva a iniciar sesión', (tester) async {
      final server = _community();
      final nb = server.notebooks.firstWhere((n) => n['title'] == 'Puente Pedro de Valdivia');
      await pumpTestApp(tester, at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(Key('nb-like-${nb['id']}')));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenido de vuelta, naturalista.'), findsOneWidget);
      expect(server.requests.where((r) => r.endsWith('/like')), isEmpty);
    });

    testWidgets('compartir genera el enlace al cuaderno correcto', (tester) async {
      Uri? shared;
      LinkSharer.share = (link, subject) async {
        shared = link;
        return true;
      };
      final server = _community();
      final nb = server.notebooks.firstWhere((n) => n['title'] == 'Humedal Angachilla');
      await pumpTestApp(tester, at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(Key('nb-share-${nb['id']}')));
      await tester.pumpAndSettle();
      expect(shared.toString(), endsWith('#/explore/notebooks/${nb['id']}'));
      expect(find.text('Enlace copiado.'), findsOneWidget);
    });

    testWidgets('abrir un cuaderno ajeno muestra autora y páginas, y abre la página en solo lectura', (tester) async {
      final server = _community();
      final nb = server.notebooks.firstWhere((n) => n['title'] == 'Humedal Angachilla');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client, size: _tall);
      await tester.tap(find.text('Humedal Angachilla'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notebook-owner')), findsOneWidget);
      expect(find.text('Beto Prueba'), findsOneWidget);
      expect(find.byKey(const Key('add-page')), findsNothing); // no es la dueña
      final page = server.pagesOf(nb['id'] as String).first;
      await tester.tap(find.text('Página 1'));
      await tester.pumpAndSettle();
      expect(server.requests, contains('GET /pages/${page['id']}'));
    });

    testWidgets('«Siguiendo» muestra solo cuadernos de quienes sigo', (tester) async {
      final server = _community()..followingIds.add('u3');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(const Key('explore-following')));
      await tester.pumpAndSettle();
      expect(find.text('Humedal Angachilla'), findsOneWidget);
      expect(find.text('Puente Pedro de Valdivia'), findsNothing);
    });
  });

  group('Mis cuadernos', () {
    testWidgets('muestra los propios (también privados) y la dueña puede retirar uno de la comunidad', (tester) async {
      final server = _community();
      final mine = server.addNotebook('Mi bitácora');
      mine['visibility'] = 'public';
      final secret = server.addNotebook('Borrador');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(const Key('tab-mine')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('nb-card-${mine['id']}')), findsOneWidget);
      expect(find.byKey(Key('nb-card-${secret['id']}')), findsOneWidget);
      expect(find.text('Rocura'), findsNothing); // los ajenos no están en «Mis cuadernos»

      await tester.tap(find.text('Mi bitácora'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-visibility')));
      await tester.pumpAndSettle();
      expect(server.requestBodies['PATCH /notebooks/${mine['id']}'], {'visibility': 'private'});
      expect(find.text('El cuaderno ya no es público. No se borró nada.'), findsOneWidget);
      expect(server.notebooks.any((n) => n['id'] == mine['id']), isTrue); // no se borró
    });

    testWidgets('la dueña edita título, descripción y categoría', (tester) async {
      final server = FakeApiServer();
      final mine = server.addNotebook('Salida');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebooks/${mine['id']}', api: server.client, size: _tall);
      await tester.tap(find.byKey(const Key('notebook-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit-notebook-category')), 'Aves');
      await tester.tap(find.byKey(const Key('edit-notebook-save')));
      await tester.pumpAndSettle();
      expect(server.requestBodies['PATCH /notebooks/${mine['id']}'], {'category': 'Aves'});
      expect(find.text('Aves'), findsOneWidget);
    });
  });

  group('Personas y perfiles', () {
    testWidgets('directorio con el número real de seguidores', (tester) async {
      final server = _community();
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/community', api: server.client, size: _tall);
      await tester.tap(find.byKey(const Key('tab-people')));
      await tester.pumpAndSettle();
      expect(find.text('Todas las personas'), findsOneWidget);
      expect(find.textContaining('3 seguidores'), findsOneWidget);
    });

    testWidgets('perfil: cuadernos públicos (no privados) y seguidores visibles', (tester) async {
      final server = _community()..addPerson('u4', 'Cami Seguidora');
      server.followersOf['u3'] = ['u4'];
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/people/u3', api: server.client, size: _tall);
      expect(find.text('Humedal Angachilla'), findsOneWidget);
      expect(find.text('Notas privadas de Beto'), findsNothing);
      await tester.tap(find.byKey(const Key('person-tab-followers')));
      await tester.pumpAndSettle();
      expect(find.text('Cami Seguidora'), findsOneWidget);
    });
  });
}
