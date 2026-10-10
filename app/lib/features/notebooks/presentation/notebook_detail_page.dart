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
      case 'pdf':
        await _exportPdf();
      case 'visibility':
        await _run(() async {
          final updated = await _api.update(nb.id, {'visibility': nb.visibility == 'public' ? 'private' : 'public'});
          if (mounted) setState(() => _notebook = updated);
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
                await context.push('/notebook-pages/${p.id}');
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
      body = owner
          ? ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _pages.length,
              onReorderItem: _reorder,
              itemBuilder: (context, i) => tile(_pages[i], i),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pages.length,
              itemBuilder: (context, i) => tile(_pages[i], i),
            );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(nb?.title ?? l10n.notebooksTitle),
        actions: [
          if (nb != null && !owner)
            IconButton(tooltip: l10n.exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: _exportPdf),
          if (owner)
            PopupMenuButton<String>(
              key: const Key('notebook-menu'),
              enabled: !_busy,
              onSelected: _notebookAction,
              itemBuilder: (context) => [
                PopupMenuItem(key: const Key('export-pdf'), value: 'pdf', child: Text(l10n.exportPdf)),
                PopupMenuItem(value: 'visibility', child: Text(_notebook?.visibility == 'public' ? l10n.makePrivate : l10n.makePublic)),
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
