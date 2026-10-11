import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../people/presentation/search_people_page.dart';
import '../data/notebooks_api.dart';
import '../domain/notebook_models.dart';
import 'notebook_card.dart';
import 'notebooks_page.dart' show createNotebookFlow;

/// Comunidad de cuadernos de campo: Explorar (cuadernos públicos reales),
/// Mis cuadernos y Personas. El contenido de la comunidad son los cuadernos,
/// no publicaciones sueltas.
class NotebookCommunityPage extends StatelessWidget {
  const NotebookCommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signedIn = AuthScope.of(context).isSignedIn;
    final configured = ApiScope.of(context).isConfigured;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navCommunity),
          actions: [
            IconButton(
              tooltip: l10n.communitiesTitle,
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => context.push('/communities'),
            ),
            if (signedIn)
              IconButton(tooltip: l10n.messagesTitle, icon: const Icon(Icons.chat_bubble_outline), onPressed: () => context.push('/messages')),
            if (signedIn)
              IconButton(
                tooltip: l10n.notificationsTitle,
                icon: const Icon(Icons.notifications_none),
                onPressed: () => context.push('/notifications'),
              ),
          ],
          bottom: configured
              ? TabBar(
                  tabs: [
                    Tab(key: const Key('tab-explore'), text: l10n.communityExplore),
                    Tab(key: const Key('tab-mine'), text: l10n.communityMine),
                    Tab(key: const Key('tab-people'), text: l10n.communityPeople),
                  ],
                )
              : null,
        ),
        body: !configured
            ? const ServerNotConnectedView()
            : TabBarView(
                children: [
                  const ExploreNotebooksView(),
                  signedIn ? const _MyNotebooksView() : _SignInPrompt(text: l10n.communitySignInMine),
                  const PeopleSearchView(),
                ],
              ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go('/login?from=%2Fcommunity'), child: Text(context.l10n.signIn)),
          ],
        ),
      ),
    );
  }
}

/// Lógica común: dar o quitar «me gusta» con respuesta del servidor.
mixin _NotebookLikes<T extends StatefulWidget> on State<T> {
  NotebooksApi get api;
  final liking = <String>{};

  void replaceNotebook(Notebook nb);

  Future<void> toggleLike(Notebook nb) async {
    if (!AuthScope.read(context).isSignedIn) {
      context.go(Uri(path: '/login', queryParameters: {'from': '/community'}).toString());
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final want = !nb.likedByMe;
    setState(() => liking.add(nb.id));
    replaceNotebook(nb.withLikes(nb.likeCount + (want ? 1 : -1), want));
    try {
      final (count, mine) = await api.setLiked(nb.id, want);
      replaceNotebook(nb.withLikes(count, mine));
    } catch (e) {
      replaceNotebook(nb);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => liking.remove(nb.id));
    }
  }
}

/// Explorar: todos los cuadernos públicos (también los de la app antigua),
/// del más reciente al más antiguo, con búsqueda y filtro «Siguiendo».
class ExploreNotebooksView extends StatefulWidget {
  const ExploreNotebooksView({super.key});

  @override
  State<ExploreNotebooksView> createState() => _ExploreNotebooksViewState();
}

class _ExploreNotebooksViewState extends State<ExploreNotebooksView>
    with _NotebookLikes<ExploreNotebooksView>, AutomaticKeepAliveClientMixin<ExploreNotebooksView> {
  late NotebooksApi _api;
  final _input = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  bool _following = false;
  String _query = '';
  List<Notebook> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _started = false;

  @override
  NotebooksApi get api => _api;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = NotebooksApi(ApiScope.of(context));
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  void replaceNotebook(Notebook nb) {
    if (!mounted) return;
    setState(() => _items = [for (final n in _items) n.id == nb.id ? nb : n]);
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.explore(query: _query, following: _following);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    final seq = _seq;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loadingMore = true);
    try {
      final page = await _api.explore(query: _query, following: _following, cursor: cursor);
      if (!mounted || seq != _seq) return;
      final seen = _items.map((n) => n.id).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((n) => !seen.contains(n.id))];
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  Future<void> _open(Notebook nb) async {
    await context.push('/explore/notebooks/${nb.id}');
    if (!mounted) return;
    // Al volver, los «me gusta» y páginas pueden haber cambiado: se relee solo ese cuaderno.
    try {
      final fresh = await _api.get(nb.id);
      replaceNotebook(nb.mergeServer(fresh).withLikes(fresh.likeCount, fresh.likedByMe));
    } catch (_) {
      // Si ya no es visible (se hizo privado), desaparece de Explorar.
      if (mounted) setState(() => _items = _items.where((n) => n.id != nb.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    final signedIn = AuthScope.of(context).isSignedIn;

    Widget list;
    if (_loading) {
      list = const LoadingView();
    } else if (_error != null) {
      list = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else if (_items.isEmpty) {
      list = EmptyView(message: _following ? l10n.exploreFollowingEmpty : (_query.isEmpty ? l10n.exploreEmpty : l10n.exploreNoResults));
    } else {
      list = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          key: const Key('explore-list'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: _items.length + (_cursor != null ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            if (i == _items.length) {
              return Center(
                child: _loadingMore
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                    : TextButton(key: const Key('explore-load-more'), onPressed: _loadMore, child: Text(l10n.loadMore)),
              );
            }
            final nb = _items[i];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: NotebookCard(notebook: nb, liking: liking.contains(nb.id), onOpen: () => _open(nb), onLike: () => toggleLike(nb)),
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            key: const Key('explore-search'),
            controller: _input,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _query = v.trim();
                _load();
              });
            },
            decoration: InputDecoration(
              hintText: l10n.exploreSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (signedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('explore-all'),
                  label: Text(l10n.feedAll),
                  selected: !_following,
                  onSelected: (_) {
                    setState(() => _following = false);
                    _load();
                  },
                ),
                ChoiceChip(
                  key: const Key('explore-following'),
                  label: Text(l10n.feedFollowing),
                  selected: _following,
                  onSelected: (_) {
                    setState(() => _following = true);
                    _load();
                  },
                ),
              ],
            ),
          ),
        Expanded(child: list),
      ],
    );
  }
}

/// Mis cuadernos (públicos y privados), con sus «me gusta» reales.
class _MyNotebooksView extends StatefulWidget {
  const _MyNotebooksView();

  @override
  State<_MyNotebooksView> createState() => _MyNotebooksViewState();
}

class _MyNotebooksViewState extends State<_MyNotebooksView>
    with _NotebookLikes<_MyNotebooksView>, AutomaticKeepAliveClientMixin<_MyNotebooksView> {
  late NotebooksApi _api;
  List<Notebook> _items = [];
  bool _loading = true;
  Object? _error;
  bool _started = false;

  @override
  NotebooksApi get api => _api;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = NotebooksApi(ApiScope.of(context));
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void replaceNotebook(Notebook nb) {
    if (!mounted) return;
    setState(() => _items = [for (final n in _items) n.id == nb.id ? nb : n]);
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
    final nb = await createNotebookFlow(context, _api);
    if (nb == null || !mounted) return;
    setState(() => _items = [nb, ..._items]);
    await context.push('/notebooks/${nb.id}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else if (_items.isEmpty) {
      body = EmptyView(message: l10n.notebooksEmpty);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          key: const Key('my-notebooks-list'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final nb = _items[i];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: NotebookCard(
                  notebook: nb,
                  showOwner: false,
                  liking: liking.contains(nb.id),
                  onOpen: () async {
                    await context.push('/notebooks/${nb.id}');
                    if (mounted) _load();
                  },
                  onLike: () => toggleLike(nb),
                ),
              ),
            );
          },
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            key: const Key('community-new-notebook'),
            heroTag: 'community-new-notebook',
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: Text(l10n.newNotebook),
          ),
        ),
      ],
    );
  }
}
