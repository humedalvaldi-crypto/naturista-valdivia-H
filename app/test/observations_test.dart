import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/observations/presentation/taxon_ui.dart';
import 'package:naturista_valdivia/shared/location/location_service.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

void main() {
  tearDown(() => LocationService.current = () async => throw const LocationException(LocationProblem.unavailable));

  testWidgets('el mapa muestra las observaciones de la zona y abre su ficha', (tester) async {
    final server = FakeApiServer()..addObservation(speciesId: 'sp-chucao', locationName: 'Angachilla');
    await pumpTestApp(tester, at: '/map', api: server.client);

    expect(find.byType(GroupDot), findsOneWidget);
    expect(find.text('1 observación en esta zona'), findsOneWidget);
    expect(server.requests.any((r) => r.startsWith('GET /observations')), isTrue);

    await tester.tap(find.byType(GroupDot));
    await tester.pumpAndSettle();
    expect(find.text('Observado por Otra Persona'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-observation')));
    await tester.pumpAndSettle();
    expect(find.text('Scelorchilus rubecula'), findsOneWidget);
    expect(find.textContaining('Angachilla'), findsOneWidget);
  });

  testWidgets('filtrar por grupo vuelve a pedir la zona con ese grupo', (tester) async {
    final server = FakeApiServer()
      ..addObservation(speciesId: 'sp-chucao')
      ..addObservation(speciesId: 'sp-huillin', obscured: true);
    await pumpTestApp(tester, at: '/map', api: server.client);
    expect(find.text('2 observaciones en esta zona'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group-aves')));
    await tester.pumpAndSettle();
    expect(find.text('1 observación en esta zona'), findsOneWidget);
  });

  testWidgets('registrar con especie del catálogo y GPS', (tester) async {
    LocationService.current = () async => const GeoFix(latitude: -39.8611, longitude: -73.2344, accuracyM: 8);
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/observations/new', api: server.client);

    await tester.enterText(find.byKey(const Key('species-field')), 'chu');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('species-option-sp-chucao')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-species')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('use-gps')));
    await tester.tap(find.byKey(const Key('use-gps')));
    await tester.pumpAndSettle();
    expect(find.textContaining('precisión ±8 m'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-observation')));
    await tester.tap(find.byKey(const Key('save-observation')));
    await tester.pumpAndSettle();

    final body = server.requestBodies['POST /observations']!;
    expect(body['speciesId'], 'sp-chucao');
    expect(body['latitude'], -39.8611);
    expect(body['locationSource'], 'gps');
    expect(body['geoprivacy'], 'open');
    expect(body['visibility'], 'public');
    // Queda en la ficha nueva.
    expect(find.text('Scelorchilus rubecula'), findsOneWidget);
  });

  testWidgets('una especie amenazada siempre oculta la ubicación exacta', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/observations/new?lat=-39.86&lng=-73.23', api: server.client);

    await tester.enterText(find.byKey(const Key('species-field')), 'huill');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('species-option-sp-huillin')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('hide-location')));
    final hide = tester.widget<SwitchListTile>(find.byKey(const Key('hide-location')));
    expect(hide.value, isTrue);
    expect(hide.onChanged, isNull);
    expect(find.text('Especie amenazada: su ubicación exacta siempre se oculta a otras personas.'), findsOneWidget);
  });

  testWidgets('sin especie ni nombre no se guarda', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/observations/new?lat=-39.86&lng=-73.23', api: server.client);
    await tester.ensureVisible(find.byKey(const Key('save-observation')));
    await tester.tap(find.byKey(const Key('save-observation')));
    await tester.pumpAndSettle();
    expect(find.text('Indica qué observaste.'), findsOneWidget);
    expect(server.requestBodies.containsKey('POST /observations'), isFalse);
  });

  testWidgets('sin permiso de ubicación se explica y se puede elegir en el mapa', (tester) async {
    LocationService.current = () async => throw const LocationException(LocationProblem.denied);
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/observations/new', api: server.client);
    await tester.ensureVisible(find.byKey(const Key('use-gps')));
    await tester.tap(find.byKey(const Key('use-gps')));
    await tester.pumpAndSettle();
    expect(find.text('No diste permiso para usar tu ubicación.'), findsOneWidget);
  });

  testWidgets('la ficha de otra persona con ubicación protegida no muestra el lugar', (tester) async {
    final server = FakeApiServer();
    final o = server.addObservation(speciesId: 'sp-huillin', obscured: true);
    await pumpTestApp(tester, at: '/observations/${o['id']}', api: server.client);
    expect(find.byKey(const Key('obscured-note')), findsOneWidget);
    expect(find.byKey(const Key('edit-observation')), findsNothing);
    expect(find.textContaining('EN · En peligro'), findsOneWidget);
  });

  testWidgets('lista de observaciones y las propias', (tester) async {
    final server = FakeApiServer()
      ..addObservation(taxonName: 'Martín pescador')
      ..addObservation(taxonName: 'Coipo', ownerId: 'u1', ownerName: 'Eva');
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/observations', api: server.client);
    expect(find.text('Martín pescador'), findsOneWidget);
    expect(find.text('Coipo'), findsOneWidget);

    await tester.tap(find.text('Mías'));
    await tester.pumpAndSettle();
    expect(find.text('Coipo'), findsOneWidget);
    expect(find.text('Martín pescador'), findsNothing);
  });
}
