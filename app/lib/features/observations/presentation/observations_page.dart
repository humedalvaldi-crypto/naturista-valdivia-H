import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/paged_controller.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/observations_api.dart';
import '../domain/observation_models.dart';
import 'taxon_ui.dart';

/// Observaciones: recientes de la comunidad y las propias.
class ObservationsPage extends StatelessWidget {
  const ObservationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final api = ObservationsApi(ApiScope.of(context));
    final me = AuthScope.of(context).user?.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.observationsTitle),
          actions: [
            IconButton(tooltip: l10n.moduleMap, icon: const Icon(Icons.map_outlined), onPressed: () => context.go('/map')),
          ],
          bottom: api.isConfigured ? TabBar(tabs: [Tab(text: l10n.observationsRecent), Tab(text: l10n.observationsMine)]) : null,
        ),
        floatingActionButton: api.isConfigured
            ? FloatingActionButton.extended(
                key: const Key('new-observation'),
                onPressed: () => context.push('/observations/new'),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(l10n.newObservation),
              )
            : null,
        body: !api.isConfigured
            ? const ServerNotConnectedView()
            : TabBarView(
                children: [
                  ObservationList(key: const PageStorageKey('obs-recent'), api: api),
                  me == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: FilledButton(
                              onPressed: () => context.go('/login?from=%2Fobservations'),
                              child: Text(l10n.signIn),
                            ),
                          ),
                        )
                      : ObservationList(key: const PageStorageKey('obs-mine'), api: api, user: me),
                ],
              ),
      ),
    );
  }
}

/// Lista paginada de observaciones (todas o de una persona).
class ObservationList extends StatefulWidget {
  const ObservationList({super.key, required this.api, this.user});

  final ObservationsApi api;
  final String? user;

  @override
  State<ObservationList> createState() => _ObservationListState();
}

class _ObservationListState extends State<ObservationList> {
  late final PagedController<Observation> _c = PagedController((cursor) => widget.api.list(user: widget.user, cursor: cursor));

  @override
  void initState() {
    super.initState();
    _c.refresh();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _open(Observation o) async {
    await context.push('/observations/${o.id}');
    if (mounted) _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (_c.initialLoading) return const LoadingView();
        if (_c.error != null && _c.items.isEmpty) return ErrorView(message: apiErrorText(context, _c.error), onRetry: _c.refresh);
        if (_c.isEmpty) return EmptyView(message: l10n.observationsEmpty);
        return RefreshIndicator(
          onRefresh: _c.refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            itemCount: _c.items.length + (_c.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _c.items.length) {
                return Center(
                  child: _c.loadingMore
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                      : TextButton(onPressed: _c.loadMore, child: Text(l10n.loadMore)),
                );
              }
              final o = _c.items[i];
              final where = o.obscured && !o.isMine ? l10n.obscuredLocation : o.locationName;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Card(
                    child: ListTile(
                      key: Key('observation-${o.id}'),
                      leading: GroupDot(group: o.group, faded: o.obscured && !o.isMine),
                      title: Text(o.title(lang)),
                      subtitle: Text(
                        [formatObservedAt(context, o.observedAt), ?where, if (!o.isMine) o.owner.name].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: o.visibility == 'private'
                          ? Icon(Icons.lock_outline, semanticLabel: l10n.privateBadge)
                          : (o.species?.threatened ?? false)
                              ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error)
                              : null,
                      onTap: () => _open(o),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
