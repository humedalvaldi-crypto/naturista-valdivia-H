import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/drawing_editor/presentation/page_renderer.dart';
import 'package:naturista_valdivia/features/notebooks/domain/notebook_models.dart';
import 'package:naturista_valdivia/shared/files/file_export.dart';

/// PNG de 1×1 válido.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nombres de archivo seguros', () {
    expect(safeFileName('Salida: Angachilla / 2025?', 'pdf'), 'Salida Angachilla 2025.pdf');
    expect(safeFileName('   ', 'png'), 'naturista-valdivia.png');
  });

  testWidgets('dibuja una página completa en PNG del tamaño pedido', (tester) async {
    final requested = <String>[];
    final renderer = PageRenderer(loadPhoto: (path) async {
      requested.add(path);
      return Uint8List.fromList(_png);
    });
    const doc = PageDocument(
      id: 'p',
      notebookId: 'n',
      version: 1,
      editable: true,
      paper: 'grid',
      elements: [
        PageElement(id: 'd', type: ElementType.drawing, x: 0, y: 0, width: 1000, height: 1414, data: {
          'strokes': [
            {'tool': 'pen', 'color': '#2E5B2A', 'width': 6, 'opacity': 1, 'points': [10, 10, 300, 400, 600, 200]},
          ],
        }),
        PageElement(id: 't', type: ElementType.text, x: 60, y: 60, width: 500, height: 120, rotation: -4, z: 2, data: {
          'text': 'Chucao en el sendero', 'size': 40, 'bold': true, 'italic': true, 'align': 'center',
        }),
        PageElement(id: 'f', type: ElementType.photo, x: 100, y: 400, width: 400, height: 300, z: 3, mediaUrl: '/api/v1/media/abc'),
        PageElement(id: 'e', type: ElementType.species, x: 60, y: 800, width: 600, height: 90, z: 4, data: {'label': 'Chucao (Scelorchilus rubecula)'}),
        PageElement(id: 'a', type: ElementType.audio, x: 60, y: 950, width: 460, height: 96, z: 5, data: {'label': 'Canto'}),
        PageElement(id: 's', type: ElementType.sticker, x: 700, y: 60, width: 200, height: 200, z: 6, data: {'asset': 'assets/stickers/1.png'}),
      ],
    );
    final bytes = await tester.runAsync(() => renderer.png(doc, width: 500));
    expect(bytes, isNotNull);
    // Firma PNG y dimensiones del encabezado IHDR (ancho 500, alto 707 = 1414/2).
    expect(bytes!.sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    final header = ByteData.sublistView(bytes, 16, 24);
    expect(header.getUint32(0), 500);
    expect(header.getUint32(4), 707);
    expect(requested, ['/api/v1/media/abc']);
  });
}
