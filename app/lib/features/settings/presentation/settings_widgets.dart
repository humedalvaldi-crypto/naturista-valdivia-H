import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/files/file_export.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/account_api.dart';

/// Pantalla de una sección de Configuración: ancho máximo cómodo y lista.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

/// Nota explicativa (sin acción).
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Aplica un cambio de preferencia y avisa si no se pudo guardar.
Future<void> applySetting(BuildContext context, Future<bool> Function() change) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorText = context.l10n.errorGeneric;
  final ok = await change();
  if (!ok) messenger.showSnackBar(SnackBar(content: Text(errorText)));
}

String errorMessage(BuildContext context, Object e) => e is ApiException ? e.message : context.l10n.errorGeneric;

/// Descarga un archivo generado por el servidor con un diálogo de progreso.
Future<void> downloadFile(BuildContext context, Future<Uint8List> Function() fetch, String fileName, String mime) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final errorText = l10n.errorGeneric;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 20),
        Expanded(child: Text(l10n.settingsPreparingFile)),
      ]),
    ),
  );
  try {
    final bytes = await fetch();
    navigator.pop();
    await FileExport.save(bytes, fileName, mime);
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : errorText)));
  }
}

Future<void> sendPasswordReset(BuildContext context, String email) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await AuthScope.read(context).sendPasswordReset(email);
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsPasswordResetSent(email))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(authErrorText(l10n, e))));
  }
}

Future<void> confirmSignOut(BuildContext context) async {
  final l10n = context.l10n;
  final auth = AuthScope.read(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.signOutConfirmTitle),
      content: Text(l10n.signOutConfirmBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('confirm-sign-out'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.signOut),
        ),
      ],
    ),
  );
  if (ok ?? false) await auth.signOut();
}

/// Eliminar la cuenta: pide escribir la palabra de confirmación.
Future<void> deleteAccount(BuildContext context) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final api = AccountApi(ApiScope.of(context));
  final auth = AuthScope.read(context);
  final errorText = l10n.errorGeneric;
  final confirmed = await showDialog<bool>(context: context, builder: (context) => const _DeleteAccountDialog());
  if (confirmed != true) return;
  try {
    await api.deleteAccount();
    await auth.signOut();
    messenger.showSnackBar(SnackBar(content: Text(l10n.deleteAccountDone), duration: const Duration(seconds: 8)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : errorText)));
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ok = _text.text.trim().toUpperCase() == l10n.deleteAccountWord;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
      title: Text(l10n.deleteAccountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountBody),
            const SizedBox(height: 16),
            TextField(
              key: const Key('delete-account-confirm-text'),
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.deleteAccountTypeWord(l10n.deleteAccountWord)),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('delete-account-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.deleteAccountAction),
        ),
      ],
    );
  }
}

/// Quién puede ver el perfil (se guarda en el servidor).
class ProfileVisibilityTile extends StatefulWidget {
  const ProfileVisibilityTile({super.key});

  @override
  State<ProfileVisibilityTile> createState() => _ProfileVisibilityTileState();
}

class _ProfileVisibilityTileState extends State<ProfileVisibilityTile> {
  String? _value;
  bool _saving = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_value == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final profile = await AccountApi(ApiScope.of(context)).profile();
      if (mounted) setState(() => _value = profile.visibility);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _change(String value) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.l10n.errorGeneric;
    final previous = _value;
    setState(() {
      _value = value;
      _saving = true;
    });
    try {
      await AccountApi(ApiScope.of(context)).updateProfile({'visibility': value});
    } catch (e) {
      if (mounted) setState(() => _value = previous);
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : errorText)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = _value;
    return ListTile(
      leading: const Icon(Icons.visibility_outlined),
      title: Text(l10n.settingsProfileVisibility),
      subtitle: _error != null
          ? Text(l10n.errorGeneric)
          : value == null
              ? const LinearProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<String>(
                    key: const Key('profile-visibility'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'public', label: Text(l10n.visibilityPublic)),
                      ButtonSegment(value: 'followers', label: Text(l10n.visibilityShortFollowers), tooltip: l10n.visibilityFollowers),
                      ButtonSegment(value: 'private', label: Text(l10n.visibilityPrivate)),
                    ],
                    selected: {value},
                    onSelectionChanged: _saving ? null : (s) => _change(s.first),
                  ),
                ),
      trailing: _error != null
          ? IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.retry,
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
            )
          : null,
    );
  }
}

/// Carga y guarda las preferencias del servidor (avisos y mensajes).
class ServerSettingsBuilder extends StatefulWidget {
  const ServerSettingsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ServerSettings settings, Future<void> Function(Map<String, Object?>) save) builder;

  @override
  State<ServerSettingsBuilder> createState() => _ServerSettingsBuilderState();
}

class _ServerSettingsBuilderState extends State<ServerSettingsBuilder> {
  ServerSettings? _settings;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final s = await AccountApi(ApiScope.of(context)).serverSettings();
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(Map<String, Object?> fields) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.l10n.errorGeneric;
    try {
      final s = await AccountApi(ApiScope.of(context)).updateServerSettings(fields);
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : errorText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(errorMessage(context, _error!)),
        trailing: TextButton(
          onPressed: () {
            setState(() => _error = null);
            _load();
          },
          child: Text(context.l10n.retry),
        ),
      );
    }
    if (s == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    return widget.builder(context, s, _save);
  }
}
