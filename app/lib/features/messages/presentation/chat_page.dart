import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';

/// Conversación 1 a 1. Sin tiempo real todavía: se actualiza cada 10 s
/// mientras la pantalla está abierta (y lo dice).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.conversationId, this.withPerson, this.pollInterval = const Duration(seconds: 10)});

  final String conversationId;
  final Person? withPerson;
  final Duration pollInterval;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late SocialApi _api;
  final _input = TextEditingController();
  List<ChatMessage> _messages = []; // más recientes primero
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_api.isConfigured) return;
      _load();
      _timer = Timer.periodic(widget.pollInterval, (_) => _load(silent: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SocialApi(ApiScope.of(context));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _api.messages(widget.conversationId);
      await _api.markConversationRead(widget.conversationId);
      if (mounted) {
        setState(() {
          _messages = page.items;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final msg = await _api.sendMessage(widget.conversationId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages = [msg, ..._messages];
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      body = Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Text(l10n.chatEmpty))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return Align(
                        key: Key('message-${m.id}'),
                        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: m.mine ? scheme.primary : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(m.body, style: TextStyle(color: m.mine ? scheme.onPrimary : scheme.onSurface)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l10n.chatRefreshNote, style: Theme.of(context).textTheme.labelSmall),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-input'),
                      controller: _input,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: l10n.messageHint, counterText: ''),
                    ),
                  ),
                  IconButton(
                    key: const Key('chat-send'),
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.withPerson?.name ?? l10n.messagesTitle)),
      body: body,
    );
  }
}
