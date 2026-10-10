import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../observations/domain/observation_models.dart';
import '../../observations/presentation/taxon_ui.dart';
import '../data/album_api.dart';
import '../domain/album_models.dart';

/// Álbum de especies y logros (lámina, pantallas 63–70). Sin `userId`: el propio.
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, this.userId});

  final String? userId;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late AlbumApi _api;
  AlbumData? _data;
  Object? _error;
  bool _loading = true;
  String? _group;

  String? get _uid => widget.userId ?? AuthScope.read(context).user?.uid;

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
    _api = AlbumApi(ApiScope.of(context));
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.album(uid);
      if (mounted) {
        setState(() {
          _data = data;
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

  bool get _isMine => widget.userId == null || widget.userId == AuthScope.read(context).user?.uid;

  void _openSpecies(AlbumSpecies s) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final m = MaterialLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.species.illustration != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _Locked(
                      locked: !s.unlocked,
                      child: Image.asset(s.species.illustration!, fit: BoxFit.cover, errorBuilder: (context, _, _) => const SizedBox.shrink()),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(s.species.commonName(lang), style: Theme.of(sheet).textTheme.headlineSmall),
              Text(s.species.scientificName, style: const TextStyle(fontStyle: FontStyle.italic)),
              Text(groupLabel(l10n, s.species.group)),
              const SizedBox(height: 8),
              StatusChip(species: s.species),
              const SizedBox(height: 8),
              if (s.unlocked) ...[
                if (s.firstSeen != null) Text(l10n.unlockedOn(m.formatMediumDate(s.firstSeen!))),
                if (s.observationCount > 0) Text(l10n.observationsCount(s.observationCount)),
                if (s.via == 'legacy') Text(l10n.viaLegacy),
              ] else
                Text(l10n.lockedSpecies),
              if (_isMine) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('observe-species'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    context.push('/observations/new').then((_) {
                      if (mounted) _load();
                    });
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(l10n.observeThis),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = _data;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading && data == null) {
      body = const LoadingView();
    } else if (_error != null || data == null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      body = _content(context, data);
    }
    return Scaffold(appBar: AppBar(title: Text(l10n.albumTitle)), body: body);
  }

  Widget _content(BuildContext context, AlbumData data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final groups = {for (final s in data.species) s.species.group};
    final visible = data.species.where((s) => _group == null || s.species.group == _group).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.albumProgress(data.unlocked, data.total), key: const Key('album-progress'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(minHeight: 10, value: data.total == 0 ? 0 : data.unlocked / data.total),
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.achievementsTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final a in data.achievements) _AchievementBadge(achievement: a)],
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final g in [null, ...taxonGroups.where(groups.contains)])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              key: Key('album-group-${g ?? 'all'}'),
                              label: Text(g == null ? l10n.mapAllGroups : groupLabel(l10n, g)),
                              selected: _group == g,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _group = g),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final s = visible[i];
                return Semantics(
                  button: true,
                  label: '${s.species.commonName(lang)}${s.unlocked ? '' : ' — ${l10n.lockedSpecies}'}',
                  child: Card(
                    key: Key('album-${s.species.id}'),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openSpecies(s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Locked(
                              locked: !s.unlocked,
                              child: s.species.illustration != null
                                  ? Image.asset(s.species.illustration!, fit: BoxFit.cover, errorBuilder: (context, _, _) => _placeholder(s))
                                  : _placeholder(s),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              s.species.commonName(lang),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(AlbumSpecies s) => ColoredBox(
        color: groupColor(s.species.group).withValues(alpha: 0.15),
        child: Center(child: GroupDot(group: s.species.group, size: 48)),
      );
}

/// Especie aún no observada: en gris con un candado.
class _Locked extends StatelessWidget {
  const _Locked({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 0.45, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(colorFilter: _grey, child: child),
        const Center(child: Icon(Icons.lock_outline, color: Colors.white, size: 32, shadows: [Shadow(blurRadius: 6)])),
      ],
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final a = achievement;
    final (title, description, icon) = achievementText(l10n, a.id);
    return Tooltip(
      message: description,
      child: Semantics(
        label: '$title. $description ${a.unlocked ? '' : l10n.achievementProgress(a.progress, a.target)}',
        excludeSemantics: true,
        child: Container(
          key: Key('achievement-${a.id}'),
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: a.unlocked ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: a.unlocked ? scheme.primary : scheme.outline),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (a.unlocked)
                Text(l10n.achievementUnlocked, style: Theme.of(context).textTheme.bodySmall)
              else ...[
                LinearProgressIndicator(value: a.progress / a.target),
                const SizedBox(height: 2),
                Text(l10n.achievementProgress(a.progress, a.target), style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Nombre, descripción e ícono de cada logro (los textos viven en la app, en es/en).
(String, String, IconData) achievementText(AppLocalizations l, String id) => switch (id) {
      'first-observation' => (l.achFirstObservation, l.achFirstObservationBody, Icons.visibility_outlined),
      'observations-10' => (l.achObservations10, l.achObservations10Body, Icons.repeat),
      'species-5' => (l.achSpecies5, l.achSpecies5Body, Icons.collections_bookmark_outlined),
      'species-15' => (l.achSpecies15, l.achSpecies15Body, Icons.workspace_premium_outlined),
      'groups-3' => (l.achGroups3, l.achGroups3Body, Icons.diversity_3_outlined),
      'threatened-species' => (l.achThreatened, l.achThreatenedBody, Icons.shield_outlined),
      'first-notebook' => (l.achFirstNotebook, l.achFirstNotebookBody, Icons.menu_book_outlined),
      'pages-10' => (l.achPages10, l.achPages10Body, Icons.auto_stories_outlined),
      'followers-5' => (l.achFollowers5, l.achFollowers5Body, Icons.groups_outlined),
      'pioneer' => (l.achPioneer, l.achPioneerBody, Icons.history_edu_outlined),
      _ => (id, '', Icons.emoji_events_outlined),
    };
