import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/branding/brand.dart';
import '../../../shared/media/api_image.dart';
import '../../../shared/media/photo_picker.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../notebooks/data/notebooks_api.dart';
import '../../notebooks/domain/notebook_models.dart';
import '../domain/page_editor_controller.dart';
import 'page_canvas.dart';
import 'painters.dart';

/// Ilustraciones del proyecto disponibles como pegatinas.
const stickerAssets = [
    'assets/illustrations/aves/chucao.jpg',
    'assets/illustrations/aves/chuncho.jpg',
    'assets/illustrations/aves/cisnes.jpg',
    'assets/illustrations/aves/diucon.jpg',
    'assets/illustrations/aves/garzagrande.jpg',
    'assets/illustrations/aves/pato_real.jpg',
    'assets/illustrations/aves/runrun.jpg',
    'assets/illustrations/aves/sietecolores_1.jpg',
    'assets/illustrations/desafios/dae.jpg',
    'assets/illustrations/ecosistemas/filtracion.jpg',
    'assets/illustrations/flora/arce.jpg',
    'assets/illustrations/flora/batro.jpg',
    'assets/illustrations/flora/copihue.jpg',
    'assets/illustrations/flora/copihue2.jpg',
    'assets/illustrations/flora/encino.jpg',
    'assets/illustrations/flora/flordeloto.jpg',
    'assets/illustrations/flora/nipa.jpg',
    'assets/illustrations/funga/amanita.jpg',
    'assets/illustrations/funga/oreja_de_palo.jpg',
    'assets/illustrations/insectos/bombus.webp',
    'assets/illustrations/mamiferos/huillin.jpg',
];

const editorPalette = ['#22261F', '#2E5B2A', '#6B8F3A', '#2F6F7E', '#4A90C2', '#8A5A2B', '#C9A646', '#B3261E', '#7A3E65', '#FFFFFF'];

/// Editor de una página de cuaderno (lámina, pantallas 73–80):
/// mover, rotar y escalar elementos, dibujar con lápiz/pincel/marcador/borrador,
/// texto, pegatinas y fotos; deshacer/rehacer y guardado automático.
class DrawingEditorPage extends StatefulWidget {
  const DrawingEditorPage({super.key, required this.pageId, this.store});

  final String pageId;

  /// Para pruebas; por defecto la API.
  final PageStore? store;

  @override
  State<DrawingEditorPage> createState() => _DrawingEditorPageState();
}

class _DrawingEditorPageState extends State<DrawingEditorPage> {
  PageEditorController? _controller;
  late ApiClient _client;
  late NotebooksApi _api;
  double _zoom = 1;
  bool _uploading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _client = ApiScope.of(context);
    _api = NotebooksApi(_client);
    if (_controller == null && (_api.isConfigured || widget.store != null)) {
      _controller = PageEditorController(widget.store ?? _api)..load(widget.pageId);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<String?> _askText(String initial) =>
      showDialog<String>(context: context, builder: (context) => _TextDialog(initial: initial));

  Future<void> _addText() async {
    final value = await _askText('');
    if (value == null || value.trim().isEmpty) return;
    _controller!.add(ElementType.text, width: 560, height: 160, data: {'text': value.trim(), 'size': 36, 'color': _controller!.color});
  }

  Future<void> _editText(PageElement e) async {
    final value = await _askText(e.data['text'] as String? ?? '');
    if (value == null) return;
    _controller!.updateData(e.id, {...e.data, 'text': value});
  }

  Future<void> _addSticker() async {
    final l10n = context.l10n;
    final asset = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l10n.stickersTitle, style: Theme.of(context).textTheme.titleMedium),
              ),
              Expanded(
                child: GridView.extent(
                  padding: const EdgeInsets.all(12),
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final a in [for (final f in FrogSticker.values) f.asset, ...stickerAssets])
                      InkWell(
                        key: Key('sticker-$a'),
                        onTap: () => Navigator.pop(context, a),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(a, fit: BoxFit.contain, errorBuilder: (context, _, _) => const Icon(Icons.image_outlined)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (asset == null) return;
    _controller!.add(ElementType.sticker, width: 260, height: 260, data: {'asset': asset});
  }

  Future<void> _addPhoto() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final photo = await PhotoPicker.pick();
      if (photo == null || !mounted) return;
      setState(() => _uploading = true);
      final id = await _api.uploadPhoto(photo.bytes, photo.contentType);
      _controller!.add(ElementType.photo, width: 520, height: 390, mediaAssetId: id, mediaUrl: '/api/v1/media/$id');
    } on UnsupportedPhotoException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoUnsupported)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _reload() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.reloadPageConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.reload)),
        ],
      ),
    );
    if (ok == true) await _controller!.load(widget.pageId);
  }

  Widget _photo(PageElement e) {
    final path = e.mediaUrl;
    if (path == null) return const ColoredBox(color: Colors.black12);
    return ApiImage(api: _client, path: path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = _controller;
    if (c == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.notebooksTitle)), body: const ServerNotConnectedView());
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final doc = c.doc;
        Widget body;
        if (c.loading && doc == null) {
          body = const LoadingView();
        } else if (c.loadError != null || doc == null) {
          body = ErrorView(message: apiErrorText(context, c.loadError), onRetry: () => c.load(widget.pageId));
        } else {
          body = Column(
            children: [
              if (_uploading) const LinearProgressIndicator(),
              Expanded(child: _canvasArea(c)),
              if (c.editable) _Toolbar(controller: c, onText: _addText, onSticker: _addSticker, onPhoto: _uploading ? null : _addPhoto),
            ],
          );
        }
        final selected = c.selected;
        return Scaffold(
            appBar: AppBar(
              title: Text(doc?.title?.isNotEmpty ?? false ? doc!.title! : l10n.notebooksTitle, overflow: TextOverflow.ellipsis),
              actions: [
                if (doc != null && !c.editable)
                  Padding(padding: const EdgeInsets.only(right: 12), child: Chip(label: Text(l10n.readOnly)))
                else if (doc != null) ...[
                  _SaveChip(controller: c, onConflict: _reload),
                  if (selected != null) ...[
                    if (selected.type == ElementType.text)
                      IconButton(tooltip: l10n.editText, icon: const Icon(Icons.edit_outlined), onPressed: () => _editText(selected)),
                    IconButton(tooltip: l10n.bringToFront, icon: const Icon(Icons.flip_to_front), onPressed: c.bringToFront),
                    IconButton(key: const Key('delete-element'), tooltip: l10n.deleteElement, icon: const Icon(Icons.delete_outline), onPressed: c.deleteSelected),
                  ],
                  IconButton(key: const Key('undo'), tooltip: l10n.undo, icon: const Icon(Icons.undo), onPressed: c.canUndo ? c.undo : null),
                  IconButton(key: const Key('redo'), tooltip: l10n.redo, icon: const Icon(Icons.redo), onPressed: c.canRedo ? c.redo : null),
                ],
                if (doc != null) ...[
                  IconButton(tooltip: l10n.zoomOut, icon: const Icon(Icons.zoom_out), onPressed: _zoom > 0.5 ? () => setState(() => _zoom = math.max(0.5, _zoom - 0.25)) : null),
                  IconButton(tooltip: l10n.zoomIn, icon: const Icon(Icons.zoom_in), onPressed: _zoom < 3 ? () => setState(() => _zoom = math.min(3, _zoom + 0.25)) : null),
                ],
              ],
            ),
            body: body,
        );
      },
    );
  }

  Widget _canvasArea(PageEditorController c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Escala para que la página quepa a lo ancho, luego el zoom del usuario.
        final fit = math.max(0.1, (constraints.maxWidth - 32) / PageCanvas.width);
        final scale = fit * _zoom;
        // Al dibujar, el dedo dibuja: el desplazamiento se desactiva.
        final physics = c.mode == EditorMode.draw && c.editable ? const NeverScrollableScrollPhysics() : null;
        return ColoredBox(
          color: const Color(0xFFE8E4D8),
          child: SingleChildScrollView(
            physics: physics,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: physics,
              child: SizedBox(
                width: math.max(constraints.maxWidth - 32, PageCanvas.width * scale),
                child: Center(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))]),
                    child: PageCanvasView(
                      controller: c,
                      scale: scale,
                      photoBuilder: _photo,
                      onEditText: _editText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.controller, required this.onConflict});

  final PageEditorController controller;
  final VoidCallback onConflict;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final status = controller.status;
    final (label, icon, color) = switch (status) {
      SaveStatus.saved => (l10n.saveSaved, Icons.cloud_done_outlined, scheme.primary),
      SaveStatus.saving => (l10n.saveSaving, Icons.cloud_upload_outlined, scheme.onSurfaceVariant),
      SaveStatus.dirty => (l10n.saveDirty, Icons.cloud_queue, scheme.onSurfaceVariant),
      SaveStatus.error => (l10n.saveError, Icons.cloud_off, scheme.error),
      SaveStatus.conflict => (l10n.saveConflict, Icons.sync_problem, scheme.error),
    };
    final VoidCallback? action = switch (status) {
      SaveStatus.saved || SaveStatus.saving => null,
      SaveStatus.dirty || SaveStatus.error => () => controller.save(),
      SaveStatus.conflict => onConflict,
    };
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Semantics(
      liveRegion: true,
      label: label,
      child: compact
          ? IconButton(key: const Key('save-status'), tooltip: label, icon: Icon(icon, color: color), onPressed: action)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                key: const Key('save-status'),
                avatar: Icon(icon, size: 18, color: color),
                label: Text(label),
                onPressed: action,
              ),
            ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onText, required this.onSticker, required this.onPhoto});

  final PageEditorController controller;
  final VoidCallback onText;
  final VoidCallback onSticker;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = controller;
    final drawing = c.mode == EditorMode.draw;
    return Material(
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (drawing) _DrawOptions(controller: c),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  _ToolButton(
                    key: const Key('mode-select'),
                    icon: Icons.pan_tool_alt_outlined,
                    label: l10n.modeSelect,
                    selected: !drawing,
                    onTap: () => c.setMode(EditorMode.select),
                  ),
                  _ToolButton(
                    key: const Key('mode-draw'),
                    icon: Icons.draw_outlined,
                    label: l10n.modeDraw,
                    selected: drawing,
                    onTap: () => c.setMode(EditorMode.draw),
                  ),
                  const SizedBox(height: 40, child: VerticalDivider()),
                  _ToolButton(key: const Key('add-text'), icon: Icons.text_fields, label: l10n.addTextShort, onTap: onText),
                  _ToolButton(key: const Key('add-sticker'), icon: Icons.emoji_nature_outlined, label: l10n.addStickerShort, onTap: onSticker),
                  _ToolButton(key: const Key('add-photo'), icon: Icons.add_photo_alternate_outlined, label: l10n.addPhotoShort, onTap: onPhoto),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: onTap == null ? scheme.outline : null),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawOptions extends StatelessWidget {
  const _DrawOptions({required this.controller});

  final PageEditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = controller;
    final tools = {
      DrawTool.pen: (Icons.edit, l10n.toolPen),
      DrawTool.brush: (Icons.brush, l10n.toolBrush),
      DrawTool.marker: (Icons.highlight, l10n.toolMarker),
      DrawTool.eraser: (Icons.auto_fix_normal, l10n.toolEraser),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final MapEntry(key: tool, value: (icon, label)) in tools.entries)
                ChoiceChip(
                  key: Key('tool-${tool.name}'),
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: c.tool == tool,
                  onSelected: (_) => c.setTool(tool: tool),
                ),
            ],
          ),
          if (c.tool != DrawTool.eraser) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final hex in editorPalette)
                  Semantics(
                    label: hex,
                    selected: c.color == hex,
                    button: true,
                    child: InkWell(
                      key: Key('color-$hex'),
                      customBorder: const CircleBorder(),
                      onTap: () => c.setTool(color: hex),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: parseHex(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.color == hex ? Theme.of(context).colorScheme.primary : Colors.black26,
                            width: c.color == hex ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          Row(
            children: [
              SizedBox(width: 80, child: Text(l10n.widthLabel)),
              Expanded(
                child: Slider(
                  value: c.strokeWidth,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: c.strokeWidth.round().toString(),
                  onChanged: (v) => c.setTool(width: v),
                ),
              ),
            ],
          ),
          if (c.tool != DrawTool.eraser)
            Row(
              children: [
                SizedBox(width: 80, child: Text(l10n.opacityLabel)),
                Expanded(
                  child: Slider(
                    value: c.opacity,
                    min: 0.1,
                    max: 1,
                    divisions: 9,
                    label: '${(c.opacity * 100).round()} %',
                    onChanged: (v) => c.setTool(opacity: v),
                  ),
                ),
              ],
            ),
          Text(l10n.pressureNote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Diálogo de texto; libera su controlador al terminar de cerrarse.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial});

  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.editText),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('element-text'),
          controller: _text,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          decoration: InputDecoration(hintText: l10n.textHint),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(key: const Key('element-text-ok'), onPressed: () => Navigator.pop(context, _text.text), child: Text(l10n.ok)),
      ],
    );
  }
}
