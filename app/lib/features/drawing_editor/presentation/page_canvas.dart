import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../notebooks/domain/notebook_models.dart';
import '../domain/page_editor_controller.dart';
import 'painters.dart';

/// Lienzo de la página a escala [scale] (píxeles por unidad de página).
class PageCanvasView extends StatelessWidget {
  const PageCanvasView({
    super.key,
    required this.controller,
    required this.scale,
    required this.photoBuilder,
    required this.onEditText,
  });

  final PageEditorController controller;
  final double scale;
  final Widget Function(PageElement) photoBuilder;
  final void Function(PageElement) onEditText;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final doc = c.doc!;
    final editable = c.editable;
    final drawing = editable && c.mode == EditorMode.draw;
    final size = Size(PageCanvas.width * scale, PageCanvas.height * scale);

    return SizedBox.fromSize(
      key: const Key('page-canvas'),
      size: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editable ? () => c.select(null) : null,
              child: CustomPaint(painter: PaperPainter(doc.paper, const Color(0xFFD9E3D5))),
            ),
          ),
          for (final e in c.ordered)
            if (e.type == ElementType.drawing)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(child: CustomPaint(painter: StrokesPainter(c.strokes))),
                ),
              )
            else
              _ElementBox(
                key: ValueKey('el-${e.id}'),
                element: e,
                scale: scale,
                controller: c,
                interactive: editable && !drawing,
                selected: c.selectedId == e.id && editable && !drawing,
                photoBuilder: photoBuilder,
                onEditText: onEditText,
              ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: ActiveStrokePainter(c.activeStroke))),
            ),
          ),
          if (drawing)
            Positioned.fill(
              child: Listener(
                key: const Key('draw-surface'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (ev) => c.beginStroke(ev.localPosition / scale, pressure: _pressure(ev)),
                onPointerMove: (ev) => c.extendStroke(ev.localPosition / scale, pressure: _pressure(ev)),
                onPointerUp: (_) => c.endStroke(),
                onPointerCancel: (_) => c.endStroke(),
              ),
            ),
        ],
      ),
    );
  }

  /// Presión solo para lápices con sensibilidad (los ratones y dedos dan 1.0 fijo).
  static double? _pressure(PointerEvent ev) {
    if (ev.kind != PointerDeviceKind.stylus && ev.kind != PointerDeviceKind.invertedStylus) return null;
    if (ev.pressureMax <= ev.pressureMin) return null;
    return ((ev.pressure - ev.pressureMin) / (ev.pressureMax - ev.pressureMin) * 1.4 + 0.2).clamp(0.2, 1.6);
  }
}

class _ElementBox extends StatelessWidget {
  const _ElementBox({
    super.key,
    required this.element,
    required this.scale,
    required this.controller,
    required this.interactive,
    required this.selected,
    required this.photoBuilder,
    required this.onEditText,
  });

  final PageElement element;
  final double scale;
  final PageEditorController controller;
  final bool interactive;
  final bool selected;
  final Widget Function(PageElement) photoBuilder;
  final void Function(PageElement) onEditText;

  static const _minSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final e = element;
    final scheme = Theme.of(context).colorScheme;
    final content = _content(context);

    Widget box = Transform.rotate(
      angle: e.rotation * math.pi / 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (selected) ...[
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: scheme.primary, width: 2)),
              ),
            ),
            // Rotar: asa arriba al centro.
            Align(
              alignment: Alignment.topCenter,
              child: _Handle(
                key: const Key('rotate-handle'),
                icon: Icons.rotate_right,
                onPanUpdate: (d) => _rotate(context, d.globalPosition),
                onPanEnd: (_) => controller.endTransform(),
              ),
            ),
            // Redimensionar: asa abajo a la derecha (coordenadas locales ya rotadas).
            Align(
              alignment: Alignment.bottomRight,
              child: _Handle(
                key: const Key('resize-handle'),
                icon: Icons.open_in_full,
                onPanUpdate: (d) => controller.transform(
                  e.id,
                  (el) => el.copyWith(
                    width: math.max(_minSize, el.width + d.delta.dx / scale),
                    height: math.max(_minSize, el.height + d.delta.dy / scale),
                  ),
                ),
                onPanEnd: (_) => controller.endTransform(),
              ),
            ),
          ],
        ],
      ),
    );

    if (interactive) {
      box = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.select(e.id),
        onDoubleTap: e.type == ElementType.text ? () => onEditText(e) : null,
        onPanStart: (_) => controller.select(e.id),
        onPanUpdate: (d) => controller.transform(e.id, (el) => el.copyWith(x: el.x + d.delta.dx / scale, y: el.y + d.delta.dy / scale)),
        onPanEnd: (_) => controller.endTransform(),
        child: box,
      );
    }

    return Positioned(
      left: e.x * scale,
      top: e.y * scale,
      width: e.width * scale,
      height: e.height * scale,
      child: box,
    );
  }

  void _rotate(BuildContext context, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final v = global - center;
    // El asa está arriba: ángulo 0 cuando el puntero está justo encima del centro.
    var degrees = math.atan2(v.dy, v.dx) * 180 / math.pi + 90;
    // Imán a múltiplos de 15° para alinear fácilmente.
    final snapped = (degrees / 15).roundToDouble() * 15;
    if ((degrees - snapped).abs() < 4) degrees = snapped;
    if (degrees > 180) degrees -= 360;
    controller.transform(element.id, (el) => el.copyWith(rotation: degrees));
  }

  Widget _content(BuildContext context) {
    final e = element;
    switch (e.type) {
      case ElementType.text:
        final size = ((e.data['size'] as num?)?.toDouble() ?? 32) * scale;
        final align = switch (e.data['align']) {
          'center' => (TextAlign.center, Alignment.topCenter),
          'right' => (TextAlign.right, Alignment.topRight),
          _ => (TextAlign.left, Alignment.topLeft),
        };
        return Padding(
          padding: EdgeInsets.all(6 * scale),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: align.$2,
            child: Text(
              e.data['text'] as String? ?? '',
              textAlign: align.$1,
              style: TextStyle(
                fontSize: size,
                height: 1.25,
                color: parseHex(e.data['color'] as String? ?? '#22261F'),
                fontWeight: e.data['bold'] == true ? FontWeight.w700 : FontWeight.w400,
                fontStyle: e.data['italic'] == true ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        );
      case ElementType.sticker:
        final asset = e.data['asset'] as String?;
        return asset == null
            ? const SizedBox.shrink()
            : Image.asset(asset, fit: BoxFit.contain, errorBuilder: (context, _, _) => const Icon(Icons.broken_image_outlined));
      case ElementType.photo:
        return photoBuilder(e);
      case ElementType.species:
      case ElementType.coordinates:
        return Container(
          padding: EdgeInsets.all(8 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFFF2EEDF),
            border: Border.all(color: const Color(0xFF8A7F5B)),
            borderRadius: BorderRadius.circular(8 * scale),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(e.data['label'] as String? ?? ''),
          ),
        );
      case ElementType.drawing:
        return const SizedBox.shrink();
    }
  }
}

class _Handle extends StatelessWidget {
  const _Handle({super.key, required this.icon, required this.onPanUpdate, required this.onPanEnd});

  final IconData icon;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: scheme.onPrimary),
      ),
    );
  }
}
