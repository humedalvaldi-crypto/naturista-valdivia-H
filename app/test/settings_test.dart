import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/observations/domain/observation_models.dart';
import 'package:naturista_valdivia/features/settings/data/account_api.dart';
import 'package:naturista_valdivia/features/settings/data/settings_repository.dart';
import 'package:naturista_valdivia/shared/files/file_export.dart';
import 'package:naturista_valdivia/shared/media/photo_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['password'], emailVerified: true);
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  final saved = <(String, String, Uint8List)>[];
  setUp(() {
    saved.clear();
    FileExport.save = (bytes, name, mime) async => saved.add((name, mime, bytes));
  });
  tearDown(() => PhotoPicker.pick = () async => null);

  testWidgets('sin sesión: invita a entrar y las preferencias del dispositivo funcionan', (tester) async {
    await pumpTestApp(tester, at: '/settings');
    expect(find.byKey(const Key('settings-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('settings-delete-account')), findsNothing);

    await tester.tap(find.byKey(const Key('map-base-topo')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('settings-high-contrast')));
    await tester.tap(find.byKey(const Key('settings-high-contrast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-reduce-motion')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('text-size')));
    await tester.tap(find.byTooltip('Grande'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalSettingsRepository.mapBaseKey), 'topo');
    expect(prefs.getBool(LocalSettingsRepository.highContrastKey), isTrue);
    expect(prefs.getBool(LocalSettingsRepository.reduceMotionKey), isTrue);
    expect(prefs.getDouble(LocalSettingsRepository.textScaleKey), 1.15);

    // El tamaño de texto se aplica a toda la app.
    final media = MediaQuery.of(tester.element(find.byKey(const Key('text-size'))));
    expect(media.textScaler.scale(10), closeTo(11.5, 0.01));
    expect(media.disableAnimations, isTrue);
  });

  testWidgets('editar el perfil: nombre, usuario y foto', (tester) async {
    final server = FakeApiServer();
    PhotoPicker.pick = () async => PickedPhoto(bytes: _png, contentType: 'image/png', name: 'yo.png');
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings', api: server.client);

    await tester.tap(find.byKey(const Key('settings-edit-profile')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'eva'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-name')), 'Eva Pérez');
    await tester.enterText(find.byKey(const Key('profile-username')), 'mal nombre');
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(server.requests, isNot(contains('PATCH /me/profile')));
    expect(find.textContaining('signos seguidos'), findsWidgets);

    await tester.enterText(find.byKey(const Key('profile-username')), 'eva.perez');
    await tester.ensureVisible(find.byKey(const Key('pick-photo')));
    await tester.tap(find.byKey(const Key('pick-photo')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(server.requests, contains('POST /media'));
    final body = server.requestBodies['PATCH /me/profile']!;
    expect(body['fullName'], 'Eva Pérez');
    expect(body['username'], 'eva.perez');
    expect(body['photoAssetId'], startsWith('m-'));
    expect(body.containsKey('bannerAssetId'), isFalse);
    expect(find.text('Perfil guardado'), findsOneWidget);
  });

  testWidgets('usuario ocupado: lo dice junto al campo', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings/profile', api: server.client);
    await tester.enterText(find.byKey(const Key('profile-username')), 'tomado');
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('PATCH /me/profile'));
    expect(find.text('Perfil guardado'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('profile-username')));
    await tester.pumpAndSettle();
    expect(find.text('Ese nombre de usuario ya está en uso.'), findsOneWidget);
  });

  testWidgets('visibilidad del perfil se guarda en el servidor', (tester) async {
    final server = FakeApiServer();
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings', api: server.client);
    await _scrollTo(tester, find.byKey(const Key('profile-visibility')));
    await tester.tap(find.text('Seguidores'));
    await tester.pumpAndSettle();
    expect(server.requestBodies['PATCH /me/profile'], {'visibility': 'followers'});
  });

  testWidgets('papelera: restaurar un cuaderno eliminado', (tester) async {
    final server = FakeApiServer();
    final nb = server.addNotebook('Salida al humedal');
    server.notebooks.remove(nb);
    server.trashed.add({...nb, 'deletedAt': DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String()});
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings/trash', api: server.client);

    expect(find.text('Salida al humedal'), findsOneWidget);
    expect(find.text('Quedan 28 días'), findsOneWidget);
    await tester.tap(find.byKey(Key('restore-${nb['id']}')));
    await tester.pumpAndSettle();
    expect(server.notebooks.map((n) => n['id']), contains(nb['id']));
    expect(find.text('La papelera está vacía.'), findsOneWidget);
  });

  testWidgets('descargar mis datos y exportar observaciones en CSV', (tester) async {
    final server = FakeApiServer();
    server.addObservation(speciesId: 'sp-chucao', ownerId: 'u1', ownerName: 'Eva', locationName: 'Isla Teja');
    server.addObservation(speciesId: 'sp-huillin'); // de otra persona: no va
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings', api: server.client);

    await _scrollTo(tester, find.byKey(const Key('settings-export-all')));
    await tester.tap(find.byKey(const Key('settings-export-all')));
    await tester.pumpAndSettle();
    expect(saved.single.$1, 'naturista-valdivia-mis-datos.json');
    expect(jsonDecode(utf8.decode(saved.single.$3))['format'], 'naturista-valdivia/export/v1');

    await tester.tap(find.byKey(const Key('settings-export-csv')));
    await tester.pumpAndSettle();
    final csv = utf8.decode(saved.last.$3.sublist(3));
    expect(saved.last.$2, 'text/csv');
    final lines = csv.trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines[1], contains('"Scelorchilus rubecula"'));
    expect(lines[1], contains('"Isla Teja"'));
  });

  testWidgets('eliminar la cuenta exige escribir ELIMINAR y cierra la sesión', (tester) async {
    final server = FakeApiServer();
    final h = await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/settings', api: server.client);
    await _scrollTo(tester, find.byKey(const Key('settings-delete-account')));
    await tester.tap(find.byKey(const Key('settings-delete-account')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('delete-account-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('delete-account-confirm-text')), 'eliminar');
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(server.accountDeleted, isTrue);
    expect(h.auth.user, isNull);
  });

  testWidgets('ayuda: las preguntas se despliegan', (tester) async {
    await pumpTestApp(tester, at: '/settings/help');
    await tester.tap(find.text('Borré un cuaderno, ¿lo puedo recuperar?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Configuración → Papelera'), findsOneWidget);
  });

  test('CSV: comillas, acentos y sin fórmulas', () {
    final o = Observation.fromJson({
      'id': 'o1',
      'owner': FakeApiServer.person('u1', 'Eva'),
      'species': null,
      'taxonName': '=HYPERLINK("x")',
      'observedAt': '2026-10-01T11:00:00Z',
      'latitude': -39.8,
      'longitude': -73.2,
      'notes': 'Dijo "hola", ñandú',
      'visibility': 'private',
      'isMine': true,
    });
    final bytes = encodeObservationsCsv([o]);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes.sublist(3));
    expect(text, contains('"\'=HYPERLINK(""x"")"'));
    expect(text, contains('"Dijo ""hola"", ñandú"'));
  });
}
