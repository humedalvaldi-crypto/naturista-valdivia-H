import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/paged_controller.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';
import '../../social/presentation/person_avatar.dart';

/// Notificaciones guardadas en el servidor (lámina, pantalla 49).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late SocialApi _api;
  PagedController<AppNotification>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SocialApi(ApiScope.of(context));
    if (_controller == null && _api.isConfigured) {
      final c = PagedController<AppNotification>((cursor) => _api.notifications(cursor: cursor));
      _controller = c;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.refresh();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _markAll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.markAllNotificationsRead();
      await _controller?.refresh();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  String _text(AppLocalizations l10n, AppNotification n) {
    final name = n.actor?.name ?? l10n.someone;
    return switch (n.type) {
      'follow' => l10n.notifFollow(name),
      'comment' => l10n.notifComment(name),
      'reaction' => l10n.notifReaction(name),
      'message' => l10n.notifMessage(name),
      _ => l10n.notifOther,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          if (c != null)
            IconButton(
              key: const Key('mark-all-read'),
              tooltip: l10n.markAllRead,
              icon: const Icon(Icons.done_all),
              onPressed: _markAll,
            ),
        ],
      ),
      body: c == null
          ? const ServerNotConnectedView()
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                if (c.initialLoading) return const LoadingView();
                if (c.error != null && c.items.isEmpty) {
                  return ErrorView(message: apiErrorText(context, c.error), onRetry: c.refresh);
                }
                if (c.isEmpty) return EmptyView(message: l10n.notificationsEmpty);
                return RefreshIndicator(
                  onRefresh: c.refresh,
                  child: ListView.builder(
                    itemCount: c.items.length + (c.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == c.items.length) {
                        return TextButton(onPressed: c.loadMore, child: Text(l10n.loadMore));
                      }
                      final n = c.items[i];
                      final actor = n.actor;
                      final postId = n.postId;
                      return ListTile(
                        key: Key('notification-${n.id}'),
                        tileColor: n.read ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                        leading: actor == null
                            ? const CircleAvatar(child: Icon(Icons.notifications_none))
                            : PersonAvatar(person: actor, imageUrl: _api.url(actor.photo)),
                        title: Text(_text(l10n, n)),
                        subtitle: Text(formatWhen(context, n.createdAt)),
                        onTap: postId == null ? null : () => context.push('/posts/$postId'),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
