import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';
import '../../social/presentation/person_avatar.dart';

/// Lista de conversaciones (lámina, pantalla 117 "Chat").
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late SocialApi _api;
  List<Conversation> _items = [];
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
    _api = SocialApi(ApiScope.of(context));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.conversations();
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
      body = EmptyView(message: l10n.messagesEmpty);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = _items[i];
            final when = c.lastMessageAt;
            return ListTile(
              key: Key('conversation-${c.id}'),
              leading: PersonAvatar(person: c.withPerson, imageUrl: _api.url(c.withPerson.photo)),
              title: Text(c.withPerson.name),
              subtitle: Text(c.lastMessage ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: c.unread > 0
                  ? Badge(label: Text('${c.unread}'))
                  : (when == null ? null : Text(MaterialLocalizations.of(context).formatShortDate(when))),
              onTap: () async {
                await context.push('/messages/${c.id}', extra: c.withPerson);
                if (mounted) _load();
              },
            );
          },
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(l10n.messagesTitle)), body: body);
  }
}
