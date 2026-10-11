import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/files/file_export.dart';
import '../../auth/application/auth_controller.dart';
import '../../drawing_editor/presentation/page_renderer.dart';
import '../../social/domain/models.dart' show Person;
import '../../social/presentation/person_avatar.dart';
import '../../social/presentation/post_actions.dart';
import '../data/notebooks_api.dart';
import '../domain/notebook_models.dart';

/// Un cuaderno y sus páginas (lámina, pantalla 72 "Cuaderno"):
/// abrir, agregar, reordenar arrastrando, duplicar y eliminar.
class NotebookDetailPage extends StatefulWidget {
  const NotebookDetailPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  State<NotebookDetailPage> createState() => _NotebookDetailPageState();
}

class _NotebookDetailPageState extends State<NotebookDetailPage> {
  late NotebooksApi _api;
  Notebook? _notebook;
  List<PageInfo> _pages = [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _api.isConfigured) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = NotebooksApi(ApiScope.of(context));
  }

  bool _isOwner = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nb = await _api.get(widget.notebookId);
      final pages = await _api.pages(widget.notebookId);
      if (!mounted) return;
      final me = AuthScope.read(context).user?.uid;
      setState(() {
        _notebook = nb;
        _pages = pages;
        // Un cuaderno privado solo se puede leer siendo su dueño.
        _isOwner = me != null && (nb.ownerId == me || (nb.ownerId == null && nb.visibility == 'private'));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String text, String action) async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(text),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _addPage() => _run(() async {
        final page = await _api.addPage(widget.notebookId);
        if (!mounted) return;
        setState(() => _pages = [..._pages, page]);
        await context.push('/notebook-pages/${page.id}');
        if (mounted) await _load();
      });

  /// `to` ya viene ajustado por haber quitado el elemento en `from`.
  Future<void> _reorder(int from, int to) async {
    final list = [..._pages];
    final item = list.removeAt(from);
    list.insert(to, item);
    setState(() => _pages = list);
    await _run(() async {
      final pages = await _api.reorder(widget.notebookId, [for (final p in list) p.id]);
      if (mounted) setState(() => _pages = pages);
    });
  }

  Future<void> _pageAction(PageInfo page, String action) async {
    final l10n = context.l10n;
    switch (action) {
      case 'duplicate':
        await _run(() async {
          await _api.duplicatePage(page.id);
          await _load();
        });
      case 'delete':
        if (!await _confirm(l10n.deletePageConfirm, l10n.delete) || !mounted) return;
        await _run(() async {
          await _api.deletePage(page.id);
          await _load();
        });
    }
  }

  /// PDF con todas las páginas (una imagen de alta resolución por página A4).
  Future<void> _exportPdf() async {
    final nb = _notebook;
    if (nb == null || _pages.isEmpty) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<int>(0);
    final total = _pages.length;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.exportPreparing),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(height: 8),
              Text(l10n.exportProgress(done, total)),
            ],
          ),
        ),
      ),
    );
    try {
      final renderer = PageRenderer(loadPhoto: _api.client.getBytes);
      final doc = pw.Document(title: nb.title, creator: 'Naturista Valdivia');
      for (final p in _pages) {
        final page = await _api.load(p.id);
        final png = await renderer.png(page, width: 1400);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
          ),
        );
        progress.value++;
      }
      final bytes = await doc.save();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await FileExport.save(bytes, safeFileName(nb.title, 'pdf'), 'application/pdf');
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportReady)));
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportError)));
    } finally {
      progress.dispose();
    }
  }

  Future<void> _notebookAction(String action) async {
    final nb = _notebook;
    if (nb == null) return;
    final l10n = context.l10n;
    switch (action) {
      case 'edit':
        final updated = await showDialog<Notebook>(context: context, builder: (_) => _EditNotebookDialog(api: _api, notebook: nb));
        if (updated != null && mounted) setState(() => _notebook = nb.mergeServer(updated));
      case 'share':
        await shareLink(context, notebookLink(nb.id), nb.title);
      case 'pdf':
        await _exportPdf();
      case 'visibility':
        await _run(() async {
          final updated = await _api.update(nb.id, {'visibility': nb.visibility == 'public' ? 'private' : 'public'});
          if (mounted) {
            setState(() => _notebook = nb.mergeServer(updated));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(updated.visibility == 'public' ? l10n.notebookPublished : l10n.notebookUnpublished)),
            );
          }
        });
      case 'duplicate':
        await _run(() async {
          final copy = await _api.duplicate(nb.id);
          if (mounted) context.pushReplacement('/notebooks/${copy.id}');
        });
      case 'delete':
        if (!await _confirm(l10n.deleteNotebookConfirm(nb.title), l10n.delete) || !mounted) return;
        await _run(() async {
          await _api.delete(nb.id);
          if (mounted) context.pop();
        });
    }
  }

  bool _liking = false;

  Future<void> _toggleLike(Notebook nb) async {
    if (AuthScope.read(context).user == null) {
      context.go('/login?from=${Uri.encodeComponent('/explore/notebooks/${nb.id}')}');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final want = !nb.likedByMe;
    setState(() {
      _liking = true;
      _notebook = nb.withLikes(nb.likeCount + (want ? 1 : -1), want);
    });
    try {
      final (count, mine) = await _api.setLiked(nb.id, want);
      if (mounted) setState(() => _notebook = _notebook?.withLikes(count, mine));
    } catch (e) {
      if (mounted) {
        setState(() => _notebook = nb);
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Widget _likeButton(Notebook nb) {
    final l10n = context.l10n;
    final color = nb.likedByMe ? Theme.of(context).colorScheme.error : null;
    return TextButton.icon(
      key: const Key('notebook-like'),
      onPressed: _liking ? null : () => _toggleLike(nb),
      icon: Icon(nb.likedByMe ? Icons.favorite : Icons.favorite_border, color: color),
      label: Text('${nb.likeCount}', semanticsLabel: l10n.notebookLikes(nb.likeCount)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final nb = _notebook;
    final owner = nb != null && _isOwner;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null || nb == null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      Widget tile(PageInfo p, int i) => Card(
            key: ValueKey('page-${p.id}'),
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(p.title?.isNotEmpty ?? false ? p.title! : l10n.pageNumber(i + 1)),
              subtitle: p.pageDate == null ? null : Text(p.pageDate!),
              onTap: () async {
                // Las páginas ajenas se abren por la ruta pública (solo lectura).
                await context.push(owner ? '/notebook-pages/${p.id}' : '/explore/pages/${p.id}');
                if (mounted) _load();
              },
              trailing: owner
                  ? PopupMenuButton<String>(
                      key: Key('page-menu-${p.id}'),
                      onSelected: (a) => _pageAction(p, a),
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
                        PopupMenuItem(value: 'delete', child: Text(l10n.deletePage)),
                      ],
                    )
                  : null,
            ),
          );
      final header = _NotebookHeader(notebook: nb);
      body = owner
          ? ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              header: header,
              itemCount: _pages.length,
              onReorderItem: _reorder,
              itemBuilder: (context, i) => tile(_pages[i], i),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pages.length + 1,
              itemBuilder: (context, i) => i == 0 ? header : tile(_pages[i - 1], i - 1),
            );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(nb?.title ?? l10n.notebooksTitle),
        actions: [
          if (nb != null && nb.visibility == 'public') _likeButton(nb),
          if (nb != null && !owner && nb.visibility == 'public')
            IconButton(
              key: const Key('notebook-share'),
              tooltip: l10n.sharePost,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareLink(context, notebookLink(nb.id), nb.title),
            ),
          if (nb != null && !owner)
            IconButton(tooltip: l10n.exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: _exportPdf),
          if (owner)
            PopupMenuButton<String>(
              key: const Key('notebook-menu'),
              enabled: !_busy,
              onSelected: _notebookAction,
              itemBuilder: (context) => [
                PopupMenuItem(key: const Key('notebook-edit'), value: 'edit', child: Text(l10n.notebookEditInfo)),
                if (_notebook?.visibility == 'public')
                  PopupMenuItem(key: const Key('notebook-share'), value: 'share', child: Text(l10n.sharePost)),
                PopupMenuItem(key: const Key('export-pdf'), value: 'pdf', child: Text(l10n.exportPdf)),
                PopupMenuItem(
                  key: const Key('notebook-visibility'),
                  value: 'visibility',
                  child: Text(_notebook?.visibility == 'public' ? l10n.notebookUnpublish : l10n.notebookPublish),
                ),
                PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
                PopupMenuItem(value: 'delete', child: Text(l10n.deleteNotebook)),
              ],
            ),
        ],
      ),
      floatingActionButton: owner
          ? FloatingActionButton.extended(
              key: const Key('add-page'),
              onPressed: _busy ? null : _addPage,
              icon: const Icon(Icons.note_add_outlined),
              label: Text(l10n.addPage),
            )
          : null,
      body: body,
    );
  }
}

/// Encabezado: autora, categoría, descripción, fecha y visibilidad.
class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final nb = notebook;
    final owner = nb.owner;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owner != null)
            InkWell(
              key: const Key('notebook-owner'),
              onTap: () => context.push('/people/${owner.id}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    PersonAvatar(
                      person: Person(id: owner.id, name: owner.name, username: owner.username, photo: owner.photo),
                      imageUrl: ApiScope.of(context).absolute(owner.photo),
                      radius: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(owner.name, style: theme.textTheme.titleSmall)),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (nb.category != null) Chip(label: Text(nb.category!), visualDensity: VisualDensity.compact),
              Chip(
                avatar: Icon(nb.visibility == 'public' ? Icons.public : Icons.lock_outline, size: 16),
                label: Text(nb.visibility == 'public' ? l10n.visibilityPublic : l10n.visibilityPrivate),
                visualDensity: VisualDensity.compact,
              ),
              Chip(label: Text(l10n.pagesCount(nb.pageCount)), visualDensity: VisualDensity.compact),
            ],
          ),
          if (nb.description != null && nb.description!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(nb.description!, style: theme.textTheme.bodyMedium)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l10n.notebookUpdated(formatWhen(context, nb.updatedAt)), style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Editar título, descripción y categoría (solo la dueña).
class _EditNotebookDialog extends StatefulWidget {
  const _EditNotebookDialog({required this.api, required this.notebook});

  final NotebooksApi api;
  final Notebook notebook;

  @override
  State<_EditNotebookDialog> createState() => _EditNotebookDialogState();
}

class _EditNotebookDialogState extends State<_EditNotebookDialog> {
  late final _title = TextEditingController(text: widget.notebook.title);
  late final _description = TextEditingController(text: widget.notebook.description ?? '');
  late final _category = TextEditingController(text: widget.notebook.category ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final nb = widget.notebook;
    final fields = <String, Object?>{
      if (title != nb.title) 'title': title,
      if (_description.text.trim() != (nb.description ?? '')) 'description': _description.text.trim(),
      if (_category.text.trim() != (nb.category ?? '')) 'category': _category.text.trim(),
    };
    if (fields.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.update(nb.id, fields);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorText(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.notebookEditInfo),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('edit-notebook-title'),
                controller: _title,
                maxLength: 120,
                decoration: InputDecoration(labelText: l10n.notebookTitleLabel),
              ),
              TextField(
                key: const Key('edit-notebook-description'),
                controller: _description,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.notebookDescriptionLabel),
              ),
              TextField(
                key: const Key('edit-notebook-category'),
                controller: _category,
                maxLength: 40,
                decoration: InputDecoration(labelText: l10n.notebookCategoryLabel, hintText: l10n.notebookCategoryHint),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(key: const Key('edit-notebook-save'), onPressed: _saving ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
