import 'package:flutter/material.dart';

import '../../notebooks/domain/notebook_models.dart';

Color parseHex(String hex, [Color fallback = const Color(0xFF22261F)]) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Fondo de papel: liso, rayado, cuadriculado o punteado.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.paper, this.color);

  final String paper;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFDF7));
    final s = size.width / PageCanvas.width;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 48.0;
    switch (paper) {
      case 'lined':
        for (var y = 120.0; y < PageCanvas.height; y += step) {
          canvas.drawLine(Offset(0, y * s), Offset(size.width, y * s), line);
        }
      case 'grid':
        for (var y = step; y < PageCanvas.height; y += step) {
          canvas.drawLine(Offset(0, y * s), Offset(size.width, y * s), line);
        }
        for (var x = step; x < PageCanvas.width; x += step) {
          canvas.drawLine(Offset(x * s, 0), Offset(x * s, size.height), line);
        }
      case 'dots':
        final dot = Paint()..color = color.withValues(alpha: 1);
        for (var y = step; y < PageCanvas.height; y += step) {
          for (var x = step; x < PageCanvas.width; x += step) {
            canvas.drawCircle(Offset(x * s, y * s), 1.6, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.paper != paper || old.color != color;
}

/// Pinta trazos en unidades de página escaladas a [size].
void paintStrokes(Canvas canvas, Size size, Iterable<Stroke> strokes) {
  final s = size.width / PageCanvas.width;
  // Capa propia para que el borrador (BlendMode.clear) solo borre trazos, no el papel.
  canvas.saveLayer(Offset.zero & size, Paint());
  for (final stroke in strokes) {
    _paintStroke(canvas, s, stroke);
  }
  canvas.restore();
}

void _paintStroke(Canvas canvas, double s, Stroke stroke) {
  if (stroke.points.isEmpty) return;
  final base = stroke.width * s;
  final (widthFactor, alpha, cap) = switch (stroke.tool) {
    DrawTool.pen => (1.0, stroke.opacity, StrokeCap.round),
    DrawTool.brush => (1.8, stroke.opacity * 0.85, StrokeCap.round),
    DrawTool.marker => (3.2, stroke.opacity * 0.35, StrokeCap.square),
    DrawTool.eraser => (3.0, 1.0, StrokeCap.round),
  };
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = cap
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = parseHex(stroke.color).withValues(alpha: alpha.clamp(0.05, 1.0))
    ..strokeWidth = base * widthFactor;
  if (stroke.tool == DrawTool.eraser) paint.blendMode = BlendMode.clear;

  final pts = [for (final p in stroke.points) Offset(p.dx * s, p.dy * s)];
  if (pts.length == 1) {
    canvas.drawCircle(pts.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
    return;
  }
  final pressures = stroke.pressures;
  if (pressures == null || pressures.length != pts.length) {
    // Curva suavizada con puntos medios.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  } else {
    // Con presión: segmentos con grosor variable.
    for (var i = 1; i < pts.length; i++) {
      final p = ((pressures[i - 1] + pressures[i]) / 2).clamp(0.2, 1.5);
      canvas.drawLine(pts[i - 1], pts[i], paint..strokeWidth = base * widthFactor * p);
    }
  }
}

/// Trazos ya confirmados. Solo se repinta cuando cambia la lista.
class StrokesPainter extends CustomPainter {
  const StrokesPainter(this.strokes);

  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(StrokesPainter old) => !identical(old.strokes, strokes);
}

/// El trazo que se está dibujando ahora (capa separada, se repinta en cada punto).
class ActiveStrokePainter extends CustomPainter {
  const ActiveStrokePainter(this.stroke);

  final Stroke? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = stroke;
    if (s == null) return;
    if (s.tool == DrawTool.eraser) {
      // Vista previa del borrador: trazo gris translúcido.
      paintStrokes(canvas, size, [
        Stroke(tool: DrawTool.marker, color: '#9E9E9E', width: s.width, opacity: 1, points: s.points, pressures: s.pressures),
      ]);
    } else {
      paintStrokes(canvas, size, [s]);
    }
  }

  @override
  bool shouldRepaint(ActiveStrokePainter old) => !identical(old.stroke, stroke);
}
