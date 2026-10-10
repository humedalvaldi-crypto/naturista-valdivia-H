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
import '../../social/presentation/social_page.dart';

/// Perfil de otra persona (lámina, pantalla 118): seguir, escribir, bloquear,
/// denunciar y ver sus publicaciones.
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
    await _run(() => _api.setFollowing(s.person.id, !s.followedByMe));
    await _load();
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
                      : FilledButton(key: const Key('follow'), onPressed: _busy ? null : () => _toggleFollow(s), child: Text(l10n.follow)),
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
      body = Column(
        children: [
          header,
          const Divider(height: 1),
          Expanded(child: FeedList(key: ValueKey('person-${s.person.id}'), api: _api, scope: 'all', author: s.person.id)),
        ],
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
