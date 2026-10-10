import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
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

  Future<void> _reorder(int from, int to) async {
    final list = [..._pages];
    final item = list.removeAt(from);
    list.insert(to > from ? to - 1 : to, item);
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

  Future<void> _notebookAction(String action) async {
    final nb = _notebook;
    if (nb == null) return;
    final l10n = context.l10n;
    switch (action) {
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
              onReorder: _reorder,
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
          if (owner)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: _notebookAction,
              itemBuilder: (context) => [
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
