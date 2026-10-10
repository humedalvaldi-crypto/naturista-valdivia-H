import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

void main() {
  testWidgets('mi álbum: progreso, logros y especies bloqueadas', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/profile', api: server.client);

    await tester.ensureVisible(find.byKey(const Key('my-album')));
    await tester.tap(find.byKey(const Key('my-album')));
    await tester.pumpAndSettle();

    expect(server.requests, contains('GET /users/u1/album'));
    expect(find.text('1 de 2 especies'), findsOneWidget);
    expect(find.text('Primera observación'), findsOneWidget);
    expect(find.text('¡Conseguido!'), findsOneWidget);
    expect(find.text('1 de 5'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget); // el huillín aún no

    await tester.tap(find.byKey(const Key('album-sp-huillin')));
    await tester.pumpAndSettle();
    expect(find.text('Aún no la observas.'), findsOneWidget);
    expect(find.textContaining('EN · En peligro'), findsOneWidget);
  });

  testWidgets('filtrar el álbum por grupo', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/album', api: server.client);
    expect(find.byKey(const Key('album-sp-huillin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-group-aves')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('album-sp-huillin')), findsNothing);
    expect(find.byKey(const Key('album-sp-chucao')), findsOneWidget);
  });
}
