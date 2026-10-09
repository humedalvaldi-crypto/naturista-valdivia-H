import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';

/// Perfil (pantalla 111 de la lámina, versión de la Fase 3): datos reales de
/// la cuenta de Firebase y cierre de sesión. El perfil público llega en la Fase 5.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final user = AuthScope.of(context).user;
    if (user == null) return const SizedBox.shrink(); // el router redirige al login

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navProfile),
        actions: [
          IconButton(
            tooltip: l10n.navSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(child: _Avatar(user: user)),
                  const SizedBox(height: 14),
                  Text(
                    user.displayName?.isNotEmpty ?? false ? user.displayName! : (user.email ?? ''),
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (user.email != null && (user.displayName?.isNotEmpty ?? false))
                    Text(
                      user.email!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            user.emailVerified ? Icons.verified_outlined : Icons.mark_email_unread_outlined,
                            color: user.emailVerified ? theme.colorScheme.primary : theme.colorScheme.error,
                          ),
                          title: Text(user.emailVerified ? l10n.emailVerified : l10n.emailNotVerified),
                          trailing: user.needsEmailVerification
                              ? TextButton(onPressed: () => context.go('/verify-email'), child: Text(l10n.verifyNow))
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: Text(l10n.accountMethods),
                          subtitle: Text(
                            [
                              if (user.providers.contains('google.com')) l10n.providerGoogle,
                              if (user.usesPassword) l10n.providerPassword,
                            ].join(' · '),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (AppConfig.apiBaseUrl.isEmpty)
                    _InfoNote(icon: Icons.cloud_off_outlined, text: l10n.serverSyncPending),
                  _InfoNote(icon: Icons.lightbulb_outline, text: l10n.publicProfileSoon),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    key: const Key('sign-out'),
                    onPressed: () => _confirmSignOut(context),
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.signOut),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = user.photoUrl;
    return CircleAvatar(
      radius: 44,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: photo == null ? null : NetworkImage(photo),
      child: Text(user.initials, style: TextStyle(fontSize: 28, color: scheme.onPrimaryContainer)),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
