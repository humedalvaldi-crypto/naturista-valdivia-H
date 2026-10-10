// Modelos de cuadernos de campo, tal como los devuelve la API `/api/v1`.
import 'dart:ui' show Offset;

DateTime _date(Object? v) => DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
double _num(Object? v, [double fallback = 0]) => (v as num?)?.toDouble() ?? fallback;

/// Lienzo lógico de una página (proporción A4), igual que en el servidor.
abstract final class PageCanvas {
  static const double width = 1000;
  static const double height = 1414;
}

class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.color,
    required this.visibility,
    required this.pageCount,
    required this.updatedAt,
    this.description,
    this.ownerId,
    this.deletedAt,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        color: j['color'] as String? ?? '#2E5B2A',
        visibility: j['visibility'] as String? ?? 'private',
        pageCount: (j['pageCount'] as num?)?.toInt() ?? 0,
        updatedAt: _date(j['updatedAt']),
        ownerId: j['ownerId'] as String?,
        deletedAt: j['deletedAt'] == null ? null : _date(j['deletedAt']),
        likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: j['likedByMe'] as bool? ?? false,
      );

  Notebook withLikes(int count, bool mine) => Notebook(
        id: id,
        title: title,
        color: color,
        visibility: visibility,
        pageCount: pageCount,
        updatedAt: updatedAt,
        description: description,
        ownerId: ownerId,
        deletedAt: deletedAt,
        likeCount: count,
        likedByMe: mine,
      );

  final String id;
  final String? ownerId;

  /// Solo en la papelera: cuándo se eliminó.
  final DateTime? deletedAt;

  /// "Me gusta" (solo al pedir un cuaderno concreto).
  final int likeCount;
  final bool likedByMe;
  final String title;
  final String? description;
  final String color;
  final String visibility;
  final int pageCount;
  final DateTime updatedAt;
}

class PageInfo {
  const PageInfo({required this.id, required this.position, required this.version, this.title, this.pageDate, this.elementCount = 0});

  factory PageInfo.fromJson(Map<String, dynamic> j) => PageInfo(
        id: j['id'] as String,
        position: (j['position'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 1,
        title: j['title'] as String?,
        pageDate: j['pageDate'] as String?,
        elementCount: (j['elementCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final int position;
  final int version;
  final String? title;
  final String? pageDate;
  final int elementCount;
}

enum ElementType { text, photo, drawing, sticker, species, coordinates, audio }

/// Un elemento colocado en la página. Inmutable: los cambios crean copias,
/// lo que permite deshacer/rehacer guardando instantáneas.
class PageElement {
  const PageElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.z = 0,
    this.data = const {},
    this.mediaAssetId,
    this.mediaUrl,
  });

  factory PageElement.fromJson(Map<String, dynamic> j) => PageElement(
        id: j['id'] as String,
        type: ElementType.values.firstWhere((t) => t.name == j['type'], orElse: () => ElementType.text),
        x: _num(j['x']),
        y: _num(j['y']),
        width: _num(j['width'], 100),
        height: _num(j['height'], 100),
        rotation: _num(j['rotation']),
        z: (j['z'] as num?)?.toInt() ?? 0,
        data: (j['data'] as Map<String, dynamic>?) ?? const {},
        mediaAssetId: j['mediaAssetId'] as String?,
        mediaUrl: j['mediaUrl'] as String?,
      );

  final String id;
  final ElementType type;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Grados.
  final double rotation;
  final int z;
  final Map<String, dynamic> data;
  final String? mediaAssetId;
  final String? mediaUrl;

  PageElement copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? z,
    Map<String, dynamic>? data,
  }) =>
      PageElement(
        id: id,
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        data: data ?? this.data,
        mediaAssetId: mediaAssetId,
        mediaUrl: mediaUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': _round(x),
        'y': _round(y),
        'width': _round(width),
        'height': _round(height),
        'rotation': _round(rotation),
        'z': z,
        'data': data,
        'mediaAssetId': mediaAssetId,
      };
}

double _round(double v) => (v * 10).roundToDouble() / 10;

/// Página completa abierta en el editor.
class PageDocument {
  const PageDocument({
    required this.id,
    required this.notebookId,
    required this.version,
    required this.editable,
    required this.elements,
    this.title,
    this.pageDate,
    this.locationName,
    this.weather,
    this.paper = 'plain',
  });

  factory PageDocument.fromJson(Map<String, dynamic> j) => PageDocument(
        id: j['id'] as String,
        notebookId: j['notebookId'] as String,
        version: (j['version'] as num).toInt(),
        editable: j['editable'] as bool? ?? false,
        title: j['title'] as String?,
        pageDate: j['pageDate'] as String?,
        locationName: j['locationName'] as String?,
        weather: j['weather'] as String?,
        paper: j['paper'] as String? ?? 'plain',
        elements: ((j['elements'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PageElement.fromJson)
            .toList(),
      );

  final String id;
  final String notebookId;
  final int version;
  final bool editable;
  final String? title;
  final String? pageDate;
  final String? locationName;
  final String? weather;
  final String paper;
  final List<PageElement> elements;

  PageDocument copyWith({int? version, String? paper, List<PageElement>? elements}) => PageDocument(
        id: id,
        notebookId: notebookId,
        version: version ?? this.version,
        editable: editable,
        title: title,
        pageDate: pageDate,
        locationName: locationName,
        weather: weather,
        paper: paper ?? this.paper,
        elements: elements ?? this.elements,
      );
}

/// Tipos de papel (mismos códigos que la API).
const paperKinds = ['plain', 'lined', 'grid', 'dots'];

// ── Dibujo ────────────────────────────────────────────────────────────────

enum DrawTool { pen, brush, marker, eraser }

/// Un trazo: herramienta, color, grosor, opacidad y puntos en unidades de
/// página. `pressures` es opcional (lápices con sensibilidad a la presión).
class Stroke {
  const Stroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.opacity,
    required this.points,
    this.pressures,
  });

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final flat = ((j['points'] as List<dynamic>?) ?? const []).map((v) => (v as num).toDouble()).toList();
    return Stroke(
      tool: DrawTool.values.firstWhere((t) => t.name == j['tool'], orElse: () => DrawTool.pen),
      color: (j['color'] as String?) ?? '#22261F',
      width: _num(j['width'], 4),
      opacity: _num(j['opacity'], 1),
      points: [for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i], flat[i + 1])],
      pressures: (j['p'] as List<dynamic>?)?.map((v) => (v as num).toDouble()).toList(),
    );
  }

  final DrawTool tool;
  final String color;
  final double width;
  final double opacity;
  final List<Offset> points;
  final List<double>? pressures;

  Stroke withPoint(Offset p, double? pressure) => Stroke(
        tool: tool,
        color: color,
        width: width,
        opacity: opacity,
        points: [...points, p],
        pressures: pressures == null && pressure == null ? null : [...?pressures, pressure ?? 1],
      );

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'color': color,
        'width': width,
        'opacity': opacity,
        'points': [for (final p in points) ...[_round(p.dx), _round(p.dy)]],
        if (pressures != null) 'p': [for (final v in pressures!) (v * 100).roundToDouble() / 100],
      };
}

List<Stroke> strokesOf(PageElement drawing) =>
    ((drawing.data['strokes'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(Stroke.fromJson).toList();
