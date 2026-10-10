import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import 'settings_widgets.dart';

/// Las 17 secciones de Configuración (las mismas de la app anterior).
/// Cada una abre su pantalla con opciones que funcionan de verdad.
enum SettingsSection {
  profile('profile', Icons.badge_outlined, needsAccount: true),
  account('account', Icons.account_circle_outlined, needsAccount: true),
  security('security', Icons.shield_outlined, needsAccount: true),
  privacy('privacy', Icons.lock_outline, needsAccount: true),
  map('map', Icons.map_outlined),
  notebook('notebook', Icons.menu_book_outlined),
  stickers('stickers', Icons.emoji_nature_outlined),
  notifications('notifications', Icons.notifications_outlined, needsAccount: true),
  appearance('appearance', Icons.palette_outlined),
  language('language', Icons.translate),
  sync('sync', Icons.cloud_sync_outlined, needsAccount: true),
  accessibility('accessibility', Icons.accessibility_new),
  stats('stats', Icons.insights_outlined, needsAccount: true),
  contact('contact', Icons.mail_outline, needsAccount: true),
  help('help', Icons.help_outline),
  legal('legal', Icons.policy_outlined),
  about('about', Icons.info_outline);

  const SettingsSection(this.id, this.icon, {this.needsAccount = false});

  final String id;
  final IconData icon;

  /// Necesita sesión iniciada (el router manda al inicio de sesión).
  final bool needsAccount;

  String get route => '/settings/$id';

  static SettingsSection? byId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  String title(AppLocalizations l) => switch (this) {
        profile => l.secProfile,
        account => l.secAccount,
        security => l.secSecurity,
        privacy => l.secPrivacy,
        map => l.secMap,
        notebook => l.secNotebook,
        stickers => l.secStickers,
        notifications => l.secNotifications,
        appearance => l.secAppearance,
        language => l.secLanguage,
        sync => l.secSync,
        accessibility => l.secAccessibility,
        stats => l.secStats,
        contact => l.secContact,
        help => l.secHelp,
        legal => l.secLegal,
        about => l.secAbout,
      };

  String subtitle(AppLocalizations l) => switch (this) {
        profile => l.secProfileHint,
        account => l.secAccountHint,
        security => l.secSecurityHint,
        privacy => l.secPrivacyHint,
        map => l.secMapHint,
        notebook => l.secNotebookHint,
        stickers => l.secStickersHint,
        notifications => l.secNotificationsHint,
        appearance => l.secAppearanceHint,
        language => l.secLanguageHint,
        sync => l.secSyncHint,
        accessibility => l.secAccessibilityHint,
        stats => l.secStatsHint,
        contact => l.secContactHint,
        help => l.secHelpHint,
        legal => l.secLegalHint,
        about => l.secAboutHint,
      };
}

/// Rutas de Configuración que exigen sesión (para el router).
final privateSettingsRoutes = {
  for (final s in SettingsSection.values)
    if (s.needsAccount) s.route,
  '/settings/trash',
  '/settings/blocked',
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = AuthScope.of(context).user;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (user != null) _AccountHeader(user: user) else const _SignInPrompt(),
              const SizedBox(height: 8),
              for (final s in SettingsSection.values)
                ListTile(
                  key: Key('settings-section-${s.id}'),
                  leading: Icon(s.icon),
                  title: Text(s.title(l10n)),
                  subtitle: Text(s.subtitle(l10n), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: s.needsAccount && user == null
                      ? Tooltip(message: l10n.settingsNeedsAccount, child: const Icon(Icons.lock_outline, size: 18))
                      : const Icon(Icons.chevron_right),
                  onTap: () => context.push(s.route),
                ),
              if (user != null) ...[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    key: const Key('settings-sign-out'),
                    onPressed: () => confirmSignOut(context),
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.signOut),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = user.photoUrl;
    final name = (user.displayName?.isNotEmpty ?? false) ? user.displayName! : (user.email ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: ListTile(
          key: const Key('settings-header'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundImage: photo == null ? null : NetworkImage(photo),
            child: Text(user.initials),
          ),
          title: Text(name, style: theme.textTheme.titleMedium),
          subtitle: Text(context.l10n.settingsSeeProfile),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/profile'),
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: ListTile(
          key: const Key('settings-sign-in'),
          leading: const Icon(Icons.login),
          title: Text(l10n.settingsSignInTitle),
          subtitle: Text(l10n.settingsSignInBody),
          onTap: () => context.go('/login?from=%2Fsettings'),
        ),
      ),
    );
  }
}
