import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';
import '../../social/presentation/person_avatar.dart';
import '../../notebooks/data/notebooks_api.dart';
import '../../notebooks/domain/notebook_models.dart';
import '../../notebooks/presentation/notebook_card.dart';
import 'follow_confirm.dart';

/// Perfil de otra persona (lámina, pantalla 118): seguir, escribir, bloquear,
/// denunciar y ver sus cuadernos públicos, seguidores y seguidos.
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.userId});

  final String userId;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  late SocialApi _api;
  PersonSummary? _summary;
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
    _api = SocialApi(ApiScope.of(context));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _api.person(widget.userId);
      if (mounted) {
        setState(() {
          _summary = s;
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

  bool _requireSignIn() {
    if (AuthScope.read(context).isSignedIn) return true;
    context.go(Uri(path: '/login', queryParameters: {'from': '/people/${widget.userId}'}).toString());
    return false;
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFollow(PersonSummary s) async {
    if (!_requireSignIn()) return;
    if (s.followedByMe && !await confirmUnfollow(context, s.person.name)) return;
    if (!mounted) return;
    await _run(() => _api.setFollowing(s.person.id, !s.followedByMe));
    // Los contadores se vuelven a leer del servidor.
    if (mounted) await _load();
  }

  Future<void> _message(PersonSummary s) async {
    if (!_requireSignIn()) return;
    final router = GoRouter.of(context);
    await _run(() async {
      final id = await _api.openConversation(s.person.id);
      router.push('/messages/$id', extra: s.person);
    });
  }

  Future<void> _block(PersonSummary s) async {
    if (!_requireSignIn()) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.blockConfirm(s.person.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.blockUser)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => _api.block(s.person.id), done: l10n.blocked);
    if (mounted) context.go('/community');
  }

  Future<void> _report(PersonSummary s) async {
    if (!_requireSignIn()) return;
    await _run(() => _api.report(targetType: 'user', targetId: s.person.id, reason: 'abuse'), done: context.l10n.reported);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _summary;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null || s == null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      final theme = Theme.of(context);
      final header = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PersonAvatar(person: s.person, imageUrl: _api.url(s.person.photo), radius: 40),
            const SizedBox(height: 10),
            Text(s.person.name, style: theme.textTheme.titleLarge),
            if (s.person.username != null) Text('@${s.person.username}', style: theme.textTheme.bodyMedium),
            if (s.followsMe && !s.isMe)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(key: const Key('follows-you'), label: Text(l10n.followsYou), visualDensity: VisualDensity.compact),
              ),
            if (s.bio != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.bio!, textAlign: TextAlign.center)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              alignment: WrapAlignment.center,
              children: [Text(l10n.followers(s.followers)), Text(l10n.followingCount(s.following)), Text(l10n.postsCount(s.posts))],
            ),
            if (!s.isMe) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  s.followedByMe
                      ? OutlinedButton(key: const Key('unfollow'), onPressed: _busy ? null : () => _toggleFollow(s), child: Text(l10n.unfollow))
                      : FilledButton(key: const Key('follow'), onPressed: _busy ? null : () => _toggleFollow(s), child: Text(s.followsMe ? l10n.followBack : l10n.follow)),
                  OutlinedButton.icon(
                    key: const Key('message-person'),
                    onPressed: _busy ? null : () => _message(s),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(l10n.sendMessage),
                  ),
                  if (!s.restricted)
                    OutlinedButton.icon(
                      key: const Key('person-album'),
                      onPressed: () => context.push('/people/${s.person.id}/album'),
                      icon: const Icon(Icons.collections_bookmark_outlined),
                      label: Text(l10n.viewAlbum),
                    ),
                ],
              ),
            ],
            if (s.restricted) Padding(padding: const EdgeInsets.only(top: 12), child: Text(l10n.profileRestricted)),
          ],
        ),
      );
      body = s.restricted
          ? SingleChildScrollView(child: header)
          : DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(
                    child: TabBar(
                      tabs: [
                        Tab(key: const Key('person-tab-notebooks'), text: l10n.notebooksTitle),
                        Tab(key: const Key('person-tab-followers'), text: l10n.followersTab),
                        Tab(key: const Key('person-tab-following'), text: l10n.feedFollowing),
                      ],
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _PersonNotebooks(key: ValueKey('nb-${s.person.id}-${s.followers}'), userId: s.person.id),
                    _Connections(key: ValueKey('followers-${s.person.id}-${s.followers}'), api: _api, userId: s.person.id, followers: true),
                    _Connections(key: ValueKey('following-${s.person.id}-${s.following}'), api: _api, userId: s.person.id, followers: false),
                  ],
                ),
              ),
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s?.person.name ?? ''),
        actions: [
          if (s != null && !s.isMe)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'block' ? _block(s) : _report(s),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'block', child: Text(l10n.blockUser)),
                PopupMenuItem(value: 'report', child: Text(l10n.reportUser)),
              ],
            ),
        ],
      ),
      body: body,
    );
  }
}

/// Cuadernos públicos de la persona, con «me gusta» reales.
class _PersonNotebooks extends StatefulWidget {
  const _PersonNotebooks({super.key, required this.userId});

  final String userId;

  @override
  State<_PersonNotebooks> createState() => _PersonNotebooksState();
}

class _PersonNotebooksState extends State<_PersonNotebooks> {
  late NotebooksApi _api;
  List<Notebook>? _items;
  Object? _error;
  final _liking = <String>{};
  bool _started = false;

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

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _api.byOwner(widget.userId);
      if (mounted) setState(() => _items = items.where((n) => n.visibility == 'public').toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _replace(Notebook nb) {
    if (!mounted) return;
    setState(() => _items = [for (final n in _items ?? <Notebook>[]) n.id == nb.id ? nb : n]);
  }

  Future<void> _like(Notebook nb) async {
    if (!AuthScope.read(context).isSignedIn) {
      context.go(Uri(path: '/login', queryParameters: {'from': '/people/${widget.userId}'}).toString());
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final want = !nb.likedByMe;
    setState(() => _liking.add(nb.id));
    _replace(nb.withLikes(nb.likeCount + (want ? 1 : -1), want));
    try {
      final (count, mine) = await _api.setLiked(nb.id, want);
      _replace(nb.withLikes(count, mine));
    } catch (e) {
      _replace(nb);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _liking.remove(nb.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _items;
    if (_error != null) return ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    if (items == null) return const LoadingView();
    if (items.isEmpty) return EmptyView(message: l10n.personNoNotebooks);
    return ListView.separated(
      key: const Key('person-notebooks'),
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final nb = items[i];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: NotebookCard(
              notebook: nb,
              showOwner: false,
              liking: _liking.contains(nb.id),
              onOpen: () => context.push('/explore/notebooks/${nb.id}'),
              onLike: () => _like(nb),
            ),
          ),
        );
      },
    );
  }
}

/// Seguidores o seguidos visibles de la persona (paginado).
class _Connections extends StatefulWidget {
  const _Connections({super.key, required this.api, required this.userId, required this.followers});

  final SocialApi api;
  final String userId;
  final bool followers;

  @override
  State<_Connections> createState() => _ConnectionsState();
}

class _ConnectionsState extends State<_Connections> {
  final _items = <PersonResult>[];
  String? _next;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.connections(widget.userId, followers: widget.followers, before: more ? _next : null);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _next = page.nextCursor;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_error != null && _items.isEmpty) return ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_items.isEmpty) return EmptyView(message: widget.followers ? l10n.personNoFollowers : l10n.personNoFollowing);
    final me = AuthScope.of(context).user?.uid;
    return ListView.builder(
      key: Key(widget.followers ? 'person-followers' : 'person-following'),
      itemCount: _items.length + (_next != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Center(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                : TextButton(onPressed: () => _load(more: true), child: Text(l10n.loadMore)),
          );
        }
        final r = _items[i];
        final tags = [
          if (r.person.id == me) l10n.you,
          if (r.followedByMe) l10n.youFollow,
          if (r.followsMe) l10n.followsYou,
        ];
        return ListTile(
          key: Key('connection-${r.person.id}'),
          leading: PersonAvatar(person: r.person, imageUrl: widget.api.url(r.person.photo)),
          title: Text(r.person.name),
          subtitle: Text([if (r.person.username != null) '@${r.person.username}', ...tags].join(' · ')),
          onTap: () => context.push('/people/${r.person.id}'),
        );
      },
    );
  }
}
