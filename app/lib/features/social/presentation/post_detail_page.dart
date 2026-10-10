import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/social_api.dart';
import '../domain/models.dart';
import 'person_avatar.dart';
import 'post_card.dart';

/// Publicación con sus comentarios. Al volver devuelve la publicación actualizada.
class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late SocialApi _api;
  Post? _post;
  List<Comment> _comments = [];
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Carga tras el primer frame (no se puede llamar a setState durante el build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _api.isConfigured) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SocialApi(ApiScope.of(context));
  }

  /// Vuelve a la pantalla anterior con la publicación actualizada, o al feed
  /// si se llegó por un enlace directo.
  void _leave() {
    if (context.canPop()) {
      context.pop(_post);
    } else {
      context.go('/community');
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await _api.getPost(widget.postId);
      final comments = await _api.comments(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments.items;
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

  Future<void> _send() async {
    final text = _comment.text.trim();
    final post = _post;
    if (text.isEmpty || post == null || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final c = await _api.addComment(post.id, text);
      if (!mounted) return;
      _comment.clear();
      setState(() {
        _comments = [..._comments, c];
        _post = post.copyWith(commentCount: post.commentCount + 1);
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  Future<void> _like() async {
    final post = _post;
    if (post == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!AuthScope.read(context).isSignedIn) {
      messenger.showSnackBar(SnackBar(content: Text(context.l10n.signInToParticipate)));
      return;
    }
    try {
      final updated = await _api.setLiked(post.id, !post.likedByMe);
      if (mounted) setState(() => _post = updated);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final post = _post;
    final signedIn = AuthScope.of(context).isSignedIn;

    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null || post == null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      body = Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                PostCard(post: post, api: _api, onLike: _like, onOpen: () {}),
                const SizedBox(height: 16),
                Text(l10n.commentsTitle, style: Theme.of(context).textTheme.titleMedium),
                if (_comments.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(l10n.noComments)),
                for (final c in _comments)
                  ListTile(
                    key: Key('comment-${c.id}'),
                    leading: PersonAvatar(person: c.author, imageUrl: _api.url(c.author.photo), radius: 16),
                    title: Text(c.author.name, style: Theme.of(context).textTheme.labelLarge),
                    subtitle: Text(c.body),
                  ),
              ],
            ),
          ),
          if (signedIn)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('comment-input'),
                        controller: _comment,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(hintText: l10n.commentHint, counterText: ''),
                      ),
                    ),
                    IconButton(
                      key: const Key('comment-send'),
                      tooltip: l10n.send,
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return PopScope<Post>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.commentsTitle),
          leading: BackButton(onPressed: _leave),
        ),
        body: body,
      ),
    );
  }
}
