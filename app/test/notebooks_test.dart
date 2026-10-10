import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';
import 'package:naturista_valdivia/features/drawing_editor/domain/page_editor_controller.dart';
import 'package:naturista_valdivia/features/notebooks/data/notebooks_api.dart';
import 'package:naturista_valdivia/features/notebooks/domain/notebook_models.dart';
import 'package:naturista_valdivia/shared/media/audio_capture.dart';

import 'support/fake_api_server.dart';
import 'support/fake_auth_repository.dart';
import 'support/test_app.dart';

const _eva = AuthUser(uid: 'u1', email: 'eva@example.test', displayName: 'Eva', providers: ['google.com'], emailVerified: true);

/// Almacén en memoria para probar el controlador sin red.
class _MemoryStore implements PageStore {
  _MemoryStore({this.editable = true});

  final bool editable;
  int version = 1;
  List<PageElement> saved = const [];
  int saves = 0;
  bool conflict = false;
  bool fail = false;

  @override
  Future<PageDocument> load(String pageId) async =>
      PageDocument(id: pageId, notebookId: 'nb', version: version, editable: editable, elements: saved);

  @override
  Future<SaveResult> save(PageDocument doc, List<PageElement> elements) async {
    saves++;
    if (fail) throw Exception('sin red');
    if (conflict || doc.version != version) return const Conflict();
    saved = elements;
    return Saved(++version);
  }
}

Future<void> _wait([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('controlador del editor', () {
    late _MemoryStore store;
    late PageEditorController c;

    setUp(() async {
      store = _MemoryStore();
      c = PageEditorController(store, autosaveDelay: const Duration(milliseconds: 10));
      await c.load('pg');
    });
    tearDown(() => c.dispose());

    test('agregar, deshacer y rehacer', () {
      c.add(ElementType.text, width: 300, height: 80, data: {'text': 'Chucao'});
      expect(c.elements, hasLength(1));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.elements, isEmpty);
      expect(c.selectedId, isNull);
      c.redo();
      expect(c.elements.single.data['text'], 'Chucao');
    });

    test('mover con arrastre crea un solo paso de historial', () {
      final e = c.add(ElementType.sticker, width: 100, height: 100);
      for (var i = 0; i < 5; i++) {
        c.transform(e.id, (el) => el.copyWith(x: el.x + 10));
      }
      c.endTransform();
      expect(c.elements.single.x, e.x + 50);
      c.undo();
      expect(c.elements.single.x, e.x);
    });

    test('un trazo se guarda en la capa de dibujo como puntos planos', () async {
      c.setMode(EditorMode.draw);
      c.beginStroke(const Offset(10, 10));
      c.extendStroke(const Offset(10.2, 10.2)); // casi igual: se ignora
      c.extendStroke(const Offset(40, 50));
      c.endStroke();
      expect(c.strokes.single.points, [const Offset(10, 10), const Offset(40, 50)]);

      await _wait();
      expect(store.saves, 1);
      final layer = store.saved.single;
      expect(layer.id, PageEditorController.drawingLayerId);
      expect((layer.toJson()['data'] as Map)['strokes'][0]['points'], [10.0, 10.0, 40.0, 50.0]);
      expect(c.status, SaveStatus.saved);
    });

    test('varios cambios seguidos se guardan una sola vez', () async {
      for (var i = 0; i < 4; i++) {
        c.add(ElementType.text, width: 100, height: 40, data: {'text': '$i'});
      }
      expect(c.status, SaveStatus.dirty);
      await _wait();
      expect(store.saves, 1);
      expect(store.saved, hasLength(4));
    });

    test('un conflicto de versión detiene el guardado automático', () async {
      store.conflict = true;
      c.add(ElementType.text, width: 100, height: 40);
      await _wait();
      expect(c.status, SaveStatus.conflict);
      c.add(ElementType.text, width: 100, height: 40);
      await _wait();
      expect(store.saves, 1, reason: 'no debe sobrescribir la versión del otro dispositivo');

      store.conflict = false;
      await c.load('pg');
      expect(c.status, SaveStatus.saved);
      expect(c.elements, isEmpty);
    });

    test('un error de red queda visible y se puede reintentar', () async {
      store.fail = true;
      c.add(ElementType.text, width: 100, height: 40);
      await _wait();
      expect(c.status, SaveStatus.error);
      store.fail = false;
      await c.save();
      expect(c.status, SaveStatus.saved);
      expect(store.saved, hasLength(1));
    });

    test('una página ajena es de solo lectura y no se guarda', () async {
      final readOnly = _MemoryStore(editable: false);
      final rc = PageEditorController(readOnly, autosaveDelay: const Duration(milliseconds: 10));
      await rc.load('pg');
      expect(rc.editable, isFalse);
      await rc.save();
      expect(readOnly.saves, 0);
      rc.dispose();
    });
  });

  group('pantallas', () {
    testWidgets('crear un cuaderno lo abre con su primera página', (tester) async {
      final server = FakeApiServer();
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebooks', api: server.client);
      expect(find.text('Aún no tienes cuadernos. Crea el primero para tus salidas a terreno.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-notebook')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('notebook-title')), 'Salida a Angachilla');
      await tester.tap(find.byKey(const Key('notebook-create')));
      await tester.pumpAndSettle();

      expect(server.requestBodies['POST /notebooks']!['title'], 'Salida a Angachilla');
      expect(find.text('Salida a Angachilla'), findsWidgets);
      expect(find.text('Página 1'), findsOneWidget);
    });

    testWidgets('agregar y eliminar páginas (con confirmación)', (tester) async {
      final server = FakeApiServer();
      final nb = server.addNotebook('Aves del humedal');
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebooks/${nb['id']}', api: server.client);
      expect(find.text('Página 1'), findsOneWidget);
      final first = server.pagesOf(nb['id'] as String).single['id'];

      // Duplicar desde el menú de la página.
      await tester.tap(find.byKey(Key('page-menu-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicar').last);
      await tester.pumpAndSettle();
      expect(find.text('Página 2'), findsOneWidget);

      final copy = server.pagesOf(nb['id'] as String)[1]['id'];
      await tester.tap(find.byKey(Key('page-menu-$copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar página').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Página 2'), findsNothing);
      expect(server.pagesOf(nb['id'] as String), hasLength(1));
    });

    testWidgets('dibujar un trazo y agregar texto se guardan en la página', (tester) async {
      final server = FakeApiServer();
      final nb = server.addNotebook('Bitácora');
      final pageId = server.pagesOf(nb['id'] as String).single['id'];
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebook-pages/$pageId', api: server.client);
      expect(find.byKey(const Key('page-canvas')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mode-draw')));
      await tester.pumpAndSettle();
      final start = tester.getTopLeft(find.byKey(const Key('draw-surface'))) + const Offset(40, 40);
      await tester.dragFrom(start, const Offset(80, 60));
      await tester.pump();

      await tester.tap(find.byKey(const Key('add-text')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('element-text')), 'Canto de chucao 8:10');
      await tester.tap(find.byKey(const Key('element-text-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Canto de chucao 8:10'), findsOneWidget);

      // Guardado automático tras la pausa.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final elements = (server.requestBodies['PUT /pages/$pageId']!['elements'] as List).cast<Map<String, dynamic>>();
      final drawing = elements.firstWhere((e) => e['type'] == 'drawing');
      expect((drawing['data']['strokes'] as List), hasLength(1));
      expect(elements.firstWhere((e) => e['type'] == 'text')['data']['text'], 'Canto de chucao 8:10');
      expect(server.pages[pageId]!['version'], greaterThan(1));
      expect(find.byTooltip('Guardado'), findsOneWidget);

      // Deshacer quita el texto.
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(find.text('Canto de chucao 8:10'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('elegir papel cuadriculado se guarda con la página', (tester) async {
      final server = FakeApiServer();
      final nb = server.addNotebook('Bitácora');
      final pageId = server.pagesOf(nb['id'] as String).single['id'];
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebook-pages/$pageId', api: server.client);

      await tester.ensureVisible(find.byKey(const Key('choose-paper')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-paper')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paper-grid')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(server.requestBodies['PUT /pages/$pageId']!['paper'], 'grid');
    });

    testWidgets('grabar una nota de audio la sube y la agrega a la página', (tester) async {
      AudioCapture.create = _FakeCapture.new;
      addTearDown(() => AudioCapture.create = _FakeCapture.new);
      final server = FakeApiServer();
      final nb = server.addNotebook('Bitácora');
      final pageId = server.pagesOf(nb['id'] as String).single['id'];
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebook-pages/$pageId', api: server.client);

      await tester.ensureVisible(find.byKey(const Key('add-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-start')));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('record-stop')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('audio-label')), 'Canto del chucao');
      await tester.tap(find.byKey(const Key('record-save')));
      await tester.pumpAndSettle();

      expect(server.requests, contains('POST /media'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final elements = (server.requestBodies['PUT /pages/$pageId']!['elements'] as List).cast<Map<String, dynamic>>();
      final audio = elements.singleWhere((e) => e['type'] == 'audio');
      expect(audio['mediaAssetId'], startsWith('m-'));
      expect(audio['data']['label'], 'Canto del chucao');
      expect(find.text('Canto del chucao'), findsOneWidget);
    });

    testWidgets('sin permiso de micrófono se explica', (tester) async {
      AudioCapture.create = () => _FakeCapture(denied: true);
      addTearDown(() => AudioCapture.create = _FakeCapture.new);
      final server = FakeApiServer();
      final nb = server.addNotebook('Bitácora');
      final pageId = server.pagesOf(nb['id'] as String).single['id'];
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebook-pages/$pageId', api: server.client);
      await tester.ensureVisible(find.byKey(const Key('add-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-start')));
      await tester.pumpAndSettle();
      expect(find.text('No hay permiso para usar el micrófono.'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('si otro dispositivo guardó antes, se avisa y no se sobrescribe', (tester) async {
      final server = FakeApiServer();
      final nb = server.addNotebook('Bitácora');
      final pageId = server.pagesOf(nb['id'] as String).single['id'] as String;
      await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebook-pages/$pageId', api: server.client);

      server.conflictNext = true;
      await tester.tap(find.byKey(const Key('add-sticker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sticker-assets/stickers/1.png')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cambió en otro dispositivo · Recargar'), findsOneWidget);
      expect(server.pages[pageId]!['elements'], isEmpty);
    });
  });

  testWidgets('me gusta en un cuaderno público de otra persona', (tester) async {
    final server = FakeApiServer();
    final nb = server.addNotebook('Aves del humedal', ownerId: 'u2');
    nb['visibility'] = 'public';
    nb['likeCount'] = 2;
    await pumpTestApp(tester, repo: FakeAuthRepository(initialUser: _eva), at: '/notebooks/${nb['id']}', api: server.client);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notebook-like')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('PUT /notebooks/${nb['id']}/like'));
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.byKey(const Key('notebook-like')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('DELETE /notebooks/${nb['id']}/like'));
    expect(find.text('2'), findsOneWidget);
  });
}

/// Micrófono simulado: devuelve un WebM mínimo válido.
class _FakeCapture implements AudioCapture {
  _FakeCapture({this.denied = false});

  final bool denied;

  @override
  Future<void> start() async {
    if (denied) throw const MicrophoneDeniedException();
  }

  @override
  Future<RecordedAudio?> stop() async => RecordedAudio(
        bytes: Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3, 0x9f, 0x42, 0x86, 0x81, 0x01, 0x42, 0xf7, 0x81, 0x01]),
        contentType: 'audio/webm',
        duration: const Duration(seconds: 2),
      );

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}
