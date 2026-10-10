import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';

/// Estado real de la cuenta en el servidor de Naturista Valdivia.
/// Llama a GET /api/v1/me, que registra al usuario en la base de datos con
/// su UID de Firebase. Sin API configurada, lo dice y no intenta conectar.
class ServerAccountStatus extends StatefulWidget {
  const ServerAccountStatus({super.key});

  @override
  State<ServerAccountStatus> createState() => _ServerAccountStatusState();
}

class _ServerAccountStatusState extends State<ServerAccountStatus> {
  Future<Map<String, dynamic>>? _request;
  ApiClient? _api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ApiScope.of(context);
    _api = api;
    if (api.isConfigured) _request ??= api.get('/me');
  }

  void _retry() {
    final api = _api;
    if (api == null) return;
    setState(() => _request = api.get('/me'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final request = _request;
    if (request == null) return _Note(icon: Icons.cloud_off_outlined, text: l10n.serverSyncPending);

    return FutureBuilder<Map<String, dynamic>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Note(icon: Icons.cloud_sync_outlined, text: l10n.serverSyncing);
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final detail = error is ApiException ? error.message : l10n.errorGeneric;
          return _Note(
            icon: Icons.cloud_off_outlined,
            text: '${l10n.serverSyncError} $detail',
            action: TextButton(onPressed: _retry, child: Text(l10n.retry)),
          );
        }
        return _Note(icon: Icons.cloud_done_outlined, text: l10n.serverSynced);
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ?action,
        ],
      ),
    );
  }
}
