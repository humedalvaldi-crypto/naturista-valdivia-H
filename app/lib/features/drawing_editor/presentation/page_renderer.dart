import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../notebooks/domain/notebook_models.dart';
import 'painters.dart';

/// Carga los bytes de una foto de la API (con sesión). Devuelve null si falla.
typedef PhotoLoader = Future<Uint8List?> Function(String path);

/// Dibuja una página completa en una imagen, sin pasar por la pantalla:
/// papel, trazos, textos con estilo, pegatinas, fotos y fichas de especie.
/// Se usa para exportar a PNG y para cada página del PDF.
class PageRenderer {
  PageRenderer({required this.loadPhoto, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final PhotoLoader loadPhoto;
  final AssetBundle _bundle;

  static const paperLines = Color(0xFFD9E3D5);

  /// PNG de [width] píxeles de ancho (alto en proporción A4).
  Future<Uint8List> png(PageDocument doc, {double width = 1600}) async {
    final image = await render(doc, width: width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<ui.Image> render(PageDocument doc, {double width = 1600}) async {
    final s = width / PageCanvas.width;
    final size = Size(width, PageCanvas.height * s);
    // Primero se descargan y decodifican las imágenes (el lienzo no puede esperar).
    final images = <String, ui.Image>{};
    for (final e in doc.elements) {
      final key = _imageKey(e);
      if (key == null || images.containsKey(key)) continue;
      final bytes = e.type == ElementType.sticker ? await _asset(e.data['asset'] as String) : await loadPhoto(e.mediaUrl!);
      if (bytes == null) continue;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        images[key] = (await codec.getNextFrame()).image;
      } catch (_) {
        // Imagen dañada: se dibuja un recuadro gris en su lugar.
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    PaperPainter(doc.paper, paperLines).paint(canvas, size);

    final ordered = [...doc.elements]..sort((a, b) {
        if (a.type == ElementType.drawing && b.type != ElementType.drawing) return -1;
        if (b.type == ElementType.drawing && a.type != ElementType.drawing) return 1;
        return a.z.compareTo(b.z);
      });
    for (final e in ordered) {
      if (e.type == ElementType.drawing) {
        paintStrokes(canvas, size, strokesOf(e));
        continue;
      }
      final rect = Rect.fromLTWH(e.x * s, e.y * s, e.width * s, e.height * s);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(e.rotation * math.pi / 180);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      switch (e.type) {
        case ElementType.text:
          _text(canvas, rect, e, s);
        case ElementType.sticker:
          _image(canvas, rect, images[_imageKey(e)], BoxFit.contain);
        case ElementType.photo:
          _image(canvas, rect, images[_imageKey(e)], BoxFit.cover);
        case ElementType.species:
        case ElementType.coordinates:
        case ElementType.audio:
          _card(canvas, rect, e, s);
        case ElementType.drawing:
          break;
      }
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    picture.dispose();
    for (final i in images.values) {
      i.dispose();
    }
    return image;
  }

  String? _imageKey(PageElement e) => switch (e.type) {
        ElementType.sticker => e.data['asset'] is String ? 'asset:${e.data['asset']}' : null,
        ElementType.photo => e.mediaUrl == null ? null : 'media:${e.mediaUrl}',
        _ => null,
      };

  Future<Uint8List?> _asset(String path) async {
    try {
      return (await _bundle.load(path)).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _image(Canvas canvas, Rect rect, ui.Image? image, BoxFit fit) {
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0x1F000000));
      return;
    }
    paintImage(canvas: canvas, rect: rect, image: image, fit: fit, filterQuality: FilterQuality.high);
  }

  /// Texto como en el editor: tamaño, color, negrita, cursiva, alineación;
  /// si no cabe en su caja se reduce (igual que FittedBox.scaleDown).
  void _text(Canvas canvas, Rect rect, PageElement e, double s) {
    final pad = 6 * s;
    final align = switch (e.data['align']) { 'center' => TextAlign.center, 'right' => TextAlign.right, _ => TextAlign.left };
    final tp = TextPainter(
      text: TextSpan(
        text: e.data['text'] as String? ?? '',
        style: TextStyle(
          fontSize: ((e.data['size'] as num?)?.toDouble() ?? 32) * s,
          height: 1.25,
          color: parseHex(e.data['color'] as String? ?? '#22261F'),
          fontWeight: e.data['bold'] == true ? FontWeight.w700 : FontWeight.w400,
          fontStyle: e.data['italic'] == true ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    _fitted(canvas, rect.deflate(pad), tp, align);
    tp.dispose();
  }

  void _card(Canvas canvas, Rect rect, PageElement e, double s) {
    final r = RRect.fromRectAndRadius(rect, Radius.circular(8 * s));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFF2EEDF));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF8A7F5B)
        ..strokeWidth = 1.5 * s,
    );
    final label = e.type == ElementType.audio ? '♪ ${e.data['label'] ?? 'Nota de audio'}' : (e.data['label'] as String? ?? '');
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(fontSize: 26 * s, color: const Color(0xFF22261F))),
      textDirection: TextDirection.ltr,
    )..layout();
    _fitted(canvas, rect.deflate(8 * s), tp, TextAlign.left);
    tp.dispose();
  }

  void _fitted(Canvas canvas, Rect box, TextPainter tp, TextAlign align) {
    final k = math.min(1.0, math.min(box.width / math.max(tp.width, 1), box.height / math.max(tp.height, 1)));
    final w = tp.width * k;
    final dx = switch (align) { TextAlign.center => (box.width - w) / 2, TextAlign.right => box.width - w, _ => 0.0 };
    canvas.save();
    canvas.translate(box.left + dx, box.top);
    canvas.scale(k);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }
}
