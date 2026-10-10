import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../notebooks/data/notebooks_api.dart';
import '../../notebooks/domain/notebook_models.dart';

enum EditorMode { select, draw }

enum SaveStatus { saved, dirty, saving, error, conflict }

/// Estado del editor de una página: elementos, selección, dibujo, historial
/// (deshacer/rehacer) y guardado automático con espera de [autosaveDelay].
class PageEditorController extends ChangeNotifier {
  PageEditorController(this._store, {this.autosaveDelay = const Duration(milliseconds: 1500)});

  final PageStore _store;
  final Duration autosaveDelay;

  static const drawingLayerId = 'drawing-layer';
  static const maxHistory = 60;

  PageDocument? _doc;
  List<PageElement> _elements = const [];
  final List<List<PageElement>> _undo = [];
  final List<List<PageElement>> _redo = [];
  String? selectedId;
  EditorMode mode = EditorMode.select;
  SaveStatus status = SaveStatus.saved;
  Object? loadError;
  Object? saveError;
  bool loading = true;

  // Herramientas de dibujo.
  DrawTool tool = DrawTool.pen;
  String color = '#22261F';
  double strokeWidth = 4;
  double opacity = 1;
  Stroke? activeStroke;

  Timer? _timer;
  bool _saving = false;
  bool _pendingWhileSaving = false;

  PageDocument? get doc => _doc;
  List<PageElement> get elements => _elements;
  bool get editable => _doc?.editable ?? false;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  PageElement? get selected => selectedId == null ? null : _byId(selectedId!);

  /// Elementos en orden de dibujo (capa de dibujo primero).
  List<PageElement> get ordered => [..._elements]..sort((a, b) {
      if (a.type == ElementType.drawing && b.type != ElementType.drawing) return -1;
      if (b.type == ElementType.drawing && a.type != ElementType.drawing) return 1;
      return a.z.compareTo(b.z);
    });

  PageElement? _strokesSource;
  List<Stroke> _strokesCache = const [];

  /// Trazos confirmados. La lista se reutiliza mientras la capa no cambie,
  /// así el lienzo no repinta todos los trazos en cada punto nuevo.
  List<Stroke> get strokes {
    final layer = _byId(drawingLayerId);
    if (!identical(layer, _strokesSource)) {
      _strokesSource = layer;
      _strokesCache = layer == null ? const [] : strokesOf(layer);
    }
    return _strokesCache;
  }

  PageElement? _byId(String id) {
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> load(String pageId) async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final doc = await _store.load(pageId);
      _doc = doc;
      _elements = doc.elements;
      _undo.clear();
      _redo.clear();
      selectedId = null;
      status = SaveStatus.saved;
    } catch (e) {
      loadError = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Cambios ─────────────────────────────────────────────────────────────

  /// Aplica un cambio confirmado: lo guarda en el historial y programa el guardado.
  void _commit(List<PageElement> next) {
    _undo.add(_elements);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _elements = next;
    _markDirty();
  }

  void _markDirty() {
    status = SaveStatus.dirty;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(autosaveDelay, save);
  }

  int get _topZ => _elements.fold(0, (m, e) => e.z > m ? e.z : m) + 1;

  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  PageElement add(ElementType type, {required double width, required double height, Map<String, dynamic> data = const {}, String? mediaAssetId, String? mediaUrl}) {
    final e = PageElement(
      id: _newId(type.name),
      type: type,
      x: (PageCanvas.width - width) / 2,
      y: (PageCanvas.height - height) / 3,
      width: width,
      height: height,
      z: _topZ,
      data: data,
      mediaAssetId: mediaAssetId,
      mediaUrl: mediaUrl,
    );
    _commit([..._elements, e]);
    selectedId = e.id;
    mode = EditorMode.select;
    notifyListeners();
    return e;
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  /// Cambio en vivo mientras se arrastra (sin historial). Llamar a [endTransform] al soltar.
  List<PageElement>? _beforeTransform;

  void transform(String id, PageElement Function(PageElement) change) {
    _beforeTransform ??= _elements;
    _elements = [for (final e in _elements) e.id == id ? change(e) : e];
    notifyListeners();
  }

  void endTransform() {
    final before = _beforeTransform;
    _beforeTransform = null;
    if (before == null || identical(before, _elements)) return;
    _undo.add(before);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _markDirty();
  }

  void updateData(String id, Map<String, dynamic> data) {
    _commit([for (final e in _elements) e.id == id ? e.copyWith(data: data) : e]);
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    selectedId = null;
    _commit(_elements.where((e) => e.id != id).toList());
  }

  void bringToFront() {
    final id = selectedId;
    if (id == null) return;
    final z = _topZ;
    _commit([for (final e in _elements) e.id == id ? e.copyWith(z: z) : e]);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_elements);
    _elements = _undo.removeLast();
    if (selectedId != null && _byId(selectedId!) == null) selectedId = null;
    _markDirty();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_elements);
    _elements = _redo.removeLast();
    _markDirty();
  }

  // ── Dibujo ──────────────────────────────────────────────────────────────

  void setMode(EditorMode m) {
    mode = m;
    if (m == EditorMode.draw) selectedId = null;
    notifyListeners();
  }

  void setTool({DrawTool? tool, String? color, double? width, double? opacity}) {
    this.tool = tool ?? this.tool;
    this.color = color ?? this.color;
    strokeWidth = width ?? strokeWidth;
    this.opacity = opacity ?? this.opacity;
    notifyListeners();
  }

  void beginStroke(Offset p, {double? pressure}) {
    activeStroke = Stroke(
      tool: tool,
      color: color,
      width: strokeWidth,
      opacity: opacity,
      points: [p],
      pressures: pressure == null ? null : [pressure],
    );
    notifyListeners();
  }

  void extendStroke(Offset p, {double? pressure}) {
    final s = activeStroke;
    if (s == null) return;
    // Se ignoran puntos casi iguales para no inflar el archivo.
    if ((s.points.last - p).distance < 0.8) return;
    activeStroke = s.withPoint(p, pressure);
    notifyListeners();
  }

  void endStroke() {
    final s = activeStroke;
    activeStroke = null;
    if (s == null) return;
    final layer = _byId(drawingLayerId) ??
        const PageElement(id: drawingLayerId, type: ElementType.drawing, x: 0, y: 0, width: PageCanvas.width, height: PageCanvas.height);
    final updated = layer.copyWith(data: {
      'strokes': [for (final st in strokesOf(layer)) st.toJson(), s.toJson()],
    });
    final exists = _byId(drawingLayerId) != null;
    _commit(exists ? [for (final e in _elements) e.id == drawingLayerId ? updated : e] : [..._elements, updated]);
  }

  // ── Guardado ────────────────────────────────────────────────────────────

  /// Guarda ahora. Si ya hay un guardado en curso, se repite al terminar.
  Future<void> save() async {
    _timer?.cancel();
    final doc = _doc;
    if (doc == null || !doc.editable || status == SaveStatus.saved || status == SaveStatus.conflict) return;
    if (_saving) {
      _pendingWhileSaving = true;
      return;
    }
    _saving = true;
    status = SaveStatus.saving;
    notifyListeners();
    final snapshot = _elements;
    try {
      final result = await _store.save(doc, snapshot);
      switch (result) {
        case Saved(:final version):
          _doc = PageDocument(
            id: doc.id,
            notebookId: doc.notebookId,
            version: version,
            editable: doc.editable,
            title: doc.title,
            pageDate: doc.pageDate,
            locationName: doc.locationName,
            weather: doc.weather,
            paper: doc.paper,
            elements: snapshot,
          );
          saveError = null;
          // Si hubo cambios mientras se guardaba, siguen pendientes.
          status = identical(snapshot, _elements) && !_pendingWhileSaving ? SaveStatus.saved : SaveStatus.dirty;
        case Conflict():
          status = SaveStatus.conflict;
      }
    } catch (e) {
      saveError = e;
      status = SaveStatus.error;
    } finally {
      _saving = false;
      notifyListeners();
    }
    if (_pendingWhileSaving && status == SaveStatus.dirty) {
      _pendingWhileSaving = false;
      await save();
    } else if (status == SaveStatus.dirty) {
      _timer = Timer(autosaveDelay, save);
    }
    _pendingWhileSaving = false;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Al cerrar el editor se intenta guardar lo pendiente (el guardado
  /// continúa aunque la pantalla ya no exista).
  @override
  void dispose() {
    _timer?.cancel();
    if (status == SaveStatus.dirty || status == SaveStatus.error) unawaited(save());
    _disposed = true;
    super.dispose();
  }
}
