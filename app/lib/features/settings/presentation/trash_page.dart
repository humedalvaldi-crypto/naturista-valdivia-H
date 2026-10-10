import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../notebooks/data/notebooks_api.dart';
import '../../notebooks/domain/notebook_models.dart';

/// Papelera: cuadernos eliminados en los últimos 30 días, recuperables con
/// todas sus páginas. Pasado ese plazo el servidor los borra definitivamente.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  static const retentionDays = 30;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  late NotebooksApi _api;
  Future<List<Notebook>>? _future;
  final _restoring = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = ApiScope.of(context);
    _api = NotebooksApi(client);
    if (client.isConfigured) _future ??= _api.trash();
  }

  void _reload() => setState(() => _future = _api.trash());

  Future<void> _restore(Notebook n) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _restoring.add(n.id));
    try {
      await _api.restore(n.id);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.trashRestored(n.title)),
        action: SnackBarAction(label: l10n.open, onPressed: () => router.go('/notebooks/${n.id}')),
      ));
      _reload();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _restoring.remove(n.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final future = _future;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trashTitle)),
      body: future == null
          ? const ServerNotConnectedView()
          : FutureBuilder<List<Notebook>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorView(message: apiErrorText(context, snapshot.error), onRetry: _reload);
                }
                final items = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      subtitle: Text(l10n.trashExplanation(TrashPage.retentionDays)),
                    ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(l10n.trashEmpty, textAlign: TextAlign.center),
                      ),
                    for (final n in items)
                      ListTile(
                        key: Key('trash-${n.id}'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(n.title),
                        subtitle: Text(_remaining(context, n.deletedAt)),
                        trailing: _restoring.contains(n.id)
                            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : TextButton.icon(
                                key: Key('restore-${n.id}'),
                                onPressed: () => _restore(n),
                                icon: const Icon(Icons.restore),
                                label: Text(l10n.trashRestore),
                              ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  String _remaining(BuildContext context, DateTime? deletedAt) {
    final l10n = context.l10n;
    if (deletedAt == null) return '';
    final minutes = deletedAt.add(const Duration(days: TrashPage.retentionDays)).difference(DateTime.now()).inMinutes;
    final left = (minutes / Duration.minutesPerDay).ceil();
    return l10n.trashDaysLeft(left < 0 ? 0 : left);
  }
}
