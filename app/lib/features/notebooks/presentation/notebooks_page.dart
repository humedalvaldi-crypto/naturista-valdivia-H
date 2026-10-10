import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../drawing_editor/presentation/painters.dart';
import '../data/notebooks_api.dart';
import '../domain/notebook_models.dart';

/// Mis cuadernos de campo (lámina, pantalla 71 "Cuadernos").
class NotebooksPage extends StatefulWidget {
  const NotebooksPage({super.key});

  @override
  State<NotebooksPage> createState() => _NotebooksPageState();
}

class _NotebooksPageState extends State<NotebooksPage> {
  late NotebooksApi _api;
  List<Notebook> _items = [];
  Object? _error;
  bool _loading = true;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.mine();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    final input = await showDialog<_NewNotebook>(context: context, builder: (context) => const _NewNotebookDialog());
    if (input == null) return;
    try {
      final nb = await _api.create(title: input.title, description: input.description, color: input.color);
      if (!mounted) return;
      setState(() => _items = [nb, ..._items]);
      context.push('/notebooks/${nb.id}');
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else if (_items.isEmpty) {
      body = EmptyView(message: l10n.notebooksEmpty);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.72,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) => _NotebookCover(
              notebook: _items[i],
              onTap: () async {
                await context.push('/notebooks/${_items[i].id}');
                if (mounted) _load();
              },
            ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notebooksTitle)),
      floatingActionButton: _api.isConfigured
          ? FloatingActionButton.extended(
              key: const Key('new-notebook'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(l10n.newNotebook),
            )
          : null,
      body: body,
    );
  }
}

/// Tapa de cuaderno con lomo, como en la lámina.
class _NotebookCover extends StatelessWidget {
  const _NotebookCover({required this.notebook, required this.onTap});

  final Notebook notebook;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = parseHex(notebook.color);
    return Material(
      key: Key('notebook-${notebook.id}'),
      color: color,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 12, color: Colors.black.withValues(alpha: 0.18)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book, color: Colors.white70),
                    const Spacer(),
                    Text(
                      notebook.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.pagesCount(notebook.pageCount)} · ${notebook.visibility == 'public' ? l10n.visibilityPublic : l10n.visibilityPrivate}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const notebookColors = ['#2E5B2A', '#2F6F7E', '#8A5A2B', '#7A3E65', '#B3261E', '#C9A646'];

typedef _NewNotebook = ({String title, String description, String color});

/// Diálogo de nuevo cuaderno. Es dueño de sus controladores, que se liberan
/// cuando el diálogo termina de cerrarse (no antes, mientras aún se anima).
class _NewNotebookDialog extends StatefulWidget {
  const _NewNotebookDialog();

  @override
  State<_NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<_NewNotebookDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _color = notebookColors.first;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, (title: title, description: _description.text.trim(), color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.newNotebook),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('notebook-title'),
              controller: _title,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(labelText: l10n.notebookTitleLabel),
            ),
            TextField(controller: _description, maxLength: 500, decoration: InputDecoration(labelText: l10n.notebookDescriptionLabel)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in notebookColors)
                  Semantics(
                    label: c,
                    selected: _color == c,
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => _color = c),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: parseHex(c),
                        child: _color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(key: const Key('notebook-create'), onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}
