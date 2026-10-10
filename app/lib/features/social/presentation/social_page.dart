import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/paged_controller.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/social_api.dart';
import '../domain/models.dart';
import 'post_card.dart';

/// Pestaña Comunidad: feed "Todo" y "Siguiendo", publicar, me gusta.
class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({super.key});

  @override
  State<SocialFeedPage> createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  final _allFeed = GlobalKey<FeedListState>();

  Future<void> _compose() async {
    final post = await context.push<Post>('/community/new');
    if (post != null) _allFeed.currentState?.insert(post);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final api = SocialApi(ApiScope.of(context));
    final auth = AuthScope.of(context);
    final signedIn = auth.isSignedIn;

    return DefaultTabController(
      length: 2,
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
              IconButton(
                tooltip: l10n.notificationsTitle,
                icon: const Icon(Icons.notifications_none),
                onPressed: () => context.push('/notifications'),
              ),
          ],
          bottom: api.isConfigured
              ? TabBar(tabs: [Tab(text: l10n.feedAll), Tab(text: l10n.feedFollowing)])
              : null,
        ),
        floatingActionButton: api.isConfigured
            ? FloatingActionButton.extended(
                key: const Key('new-post'),
                onPressed: () => signedIn ? _compose() : context.go('/login?from=%2Fcommunity'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.newPost),
              )
            : null,
        body: !api.isConfigured
            ? const ServerNotConnectedView()
            : TabBarView(
                children: [
                  FeedList(key: _allFeed, api: api, scope: 'all'),
                  signedIn
                      ? FeedList(key: const PageStorageKey('feed-following'), api: api, scope: 'following')
                      : _SignInPrompt(text: l10n.signInToParticipate),
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

/// Lista de publicaciones con "me gusta" optimista y paginación.
class FeedList extends StatefulWidget {
  const FeedList({super.key, required this.api, required this.scope, this.community});

  final SocialApi api;
  final String scope;
  final String? community;

  @override
  State<FeedList> createState() => FeedListState();
}

class FeedListState extends State<FeedList> {
  late final PagedController<Post> _controller =
      PagedController((cursor) => widget.api.feed(scope: widget.scope, community: widget.community, cursor: cursor));

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void insert(Post post) => _controller.insertFirst(post);

  Future<void> _toggleLike(Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (!AuthScope.read(context).isSignedIn) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.signInToParticipate)));
      return;
    }
    final liked = !post.likedByMe;
    // Cambio inmediato en pantalla; se confirma con la respuesta del servidor.
    _controller.replace((p) => p.id == post.id, post.copyWith(likedByMe: liked, likeCount: post.likeCount + (liked ? 1 : -1)));
    try {
      final updated = await widget.api.setLiked(post.id, liked);
      _controller.replace((p) => p.id == post.id, updated);
    } catch (e) {
      _controller.replace((p) => p.id == post.id, post);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  Future<void> _delete(Post post) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deletePostConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deletePost(post.id);
      _controller.remove((p) => p.id == post.id);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  Future<void> _open(Post post) async {
    final updated = await context.push<Post>('/posts/${post.id}');
    if (updated != null) _controller.replace((p) => p.id == post.id, updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = AuthScope.of(context).user?.uid;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        if (c.initialLoading) return const LoadingView();
        if (c.error != null && c.items.isEmpty) {
          return ErrorView(message: apiErrorText(context, c.error), onRetry: c.refresh);
        }
        if (c.isEmpty) {
          return EmptyView(message: widget.scope == 'following' ? l10n.followingEmpty : l10n.feedEmpty);
        }
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: c.items.length + (c.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == c.items.length) {
                return Center(
                  child: c.loadingMore
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                      : TextButton(onPressed: c.loadMore, child: Text(l10n.loadMore)),
                );
              }
              final post = c.items[i];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: PostCard(
                    post: post,
                    api: widget.api,
                    onLike: () => _toggleLike(post),
                    onOpen: () => _open(post),
                    onDelete: post.author.id == me ? () => _delete(post) : null,
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
