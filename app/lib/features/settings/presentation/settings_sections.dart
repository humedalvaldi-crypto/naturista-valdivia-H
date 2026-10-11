import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/media/api_image.dart';
import '../../../shared/widgets/server_required.dart';
import '../../auth/application/auth_controller.dart';
import '../../drawing_editor/presentation/drawing_editor_page.dart' show orderStickers;
import '../../drawing_editor/presentation/painters.dart' show parseHex;
import '../../profile/presentation/server_status.dart';
import '../../security/application/app_lock_controller.dart';
import '../../security/data/biometric_auth.dart';
import '../application/settings_controller.dart';
import '../data/account_api.dart';
import '../data/settings_repository.dart';
import 'help_pages.dart';
import 'settings_page.dart';
import 'settings_widgets.dart';

/// Pantalla de una sección de Configuración.
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = section.title(l10n);
    return switch (section) {
      SettingsSection.profile => const SizedBox.shrink(), // usa EditProfilePage (ruta propia)
      SettingsSection.account => SettingsScaffold(title: title, children: const [_AccountSection()]),
      SettingsSection.security => SettingsScaffold(title: title, children: const [_SecuritySection()]),
      SettingsSection.privacy => SettingsScaffold(title: title, children: const [_PrivacySection()]),
      SettingsSection.map => SettingsScaffold(title: title, children: const [_MapSection()]),
      SettingsSection.notebook => SettingsScaffold(title: title, children: const [_NotebookSection()]),
      SettingsSection.stickers => SettingsScaffold(title: title, children: const [_StickersSection()]),
      SettingsSection.notifications => SettingsScaffold(title: title, children: const [_NotificationsSection()]),
      SettingsSection.appearance => SettingsScaffold(title: title, children: const [_AppearanceSection()]),
      SettingsSection.language => SettingsScaffold(title: title, children: const [_LanguageSection()]),
      SettingsSection.sync => SettingsScaffold(title: title, children: const [_SyncSection()]),
      SettingsSection.accessibility => SettingsScaffold(title: title, children: const [_AccessibilitySection()]),
      SettingsSection.stats => SettingsScaffold(title: title, children: const [_StatsSection()]),
      SettingsSection.contact => SettingsScaffold(title: title, children: const [_ContactSection()]),
      SettingsSection.help => const HelpPage(),
      SettingsSection.legal => const LegalPage(),
      SettingsSection.about => SettingsScaffold(title: title, children: const [_AboutSection()]),
    };
  }
}

/// Columna sin desplazamiento propio (la lista la pone [SettingsScaffold]).
class _Col extends StatelessWidget {
  const _Col(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
}

/// Sin servidor configurado (dentro de una lista: sin desplazamiento propio).
class _NoServer extends StatelessWidget {
  const _NoServer();

  @override
  Widget build(BuildContext context) => InfoNote(context.l10n.serverNotConnectedBody, icon: Icons.cloud_off_outlined);
}

String _date(BuildContext context, DateTime? d) =>
    d == null ? '—' : MaterialLocalizations.of(context).formatMediumDate(d.toLocal());

// ── 2. Cuenta ───────────────────────────────────────────────────────────────
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = AuthScope.of(context).user;
    if (user == null) return const SizedBox.shrink();
    return _Col([
      ListTile(
        leading: Icon(user.emailVerified ? Icons.verified_outlined : Icons.mark_email_unread_outlined),
        title: Text(user.email ?? '—'),
        subtitle: Text(user.emailVerified ? l10n.emailVerified : l10n.emailNotVerified),
        trailing: user.needsEmailVerification
            ? TextButton(onPressed: () => context.go('/verify-email'), child: Text(l10n.verifyNow))
            : null,
      ),
      ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Text(l10n.accountMethods),
        subtitle: Text([
          if (user.providers.contains('google.com')) l10n.providerGoogle,
          if (user.usesPassword) l10n.providerPassword,
        ].join(' · ')),
      ),
      ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(l10n.accountMemberSince),
        subtitle: Text(_date(context, user.createdAt)),
      ),
      ListTile(
        key: const Key('account-uid'),
        leading: const Icon(Icons.fingerprint),
        title: Text(l10n.accountId),
        subtitle: SelectableText(user.uid),
        trailing: IconButton(
          tooltip: l10n.copy,
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final copied = l10n.copied;
            await Clipboard.setData(ClipboardData(text: user.uid));
            messenger.showSnackBar(SnackBar(content: Text(copied)));
          },
        ),
      ),
      InfoNote(l10n.accountIdHint),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(l10n.settingsEditProfile),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/profile'),
      ),
    ]);
  }
}

// ── 3. Seguridad ────────────────────────────────────────────────────────────
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = AuthScope.of(context).user;
    if (user == null) return const SizedBox.shrink();
    final online = ApiScope.of(context).isConfigured;
    return _Col([
      ListTile(
        leading: const Icon(Icons.history),
        title: Text(l10n.securityLastSignIn),
        subtitle: Text(user.lastSignInAt == null
            ? '—'
            : '${_date(context, user.lastSignInAt)} · ${TimeOfDay.fromDateTime(user.lastSignInAt!.toLocal()).format(context)}'),
      ),
      if (user.usesPassword && user.email != null)
        ListTile(
          key: const Key('settings-change-password'),
          leading: const Icon(Icons.password_outlined),
          title: Text(l10n.settingsChangePassword),
          subtitle: Text(l10n.settingsChangePasswordHint),
          onTap: () => sendPasswordReset(context, user.email!),
        )
      else
        InfoNote(l10n.securityGoogleManaged, icon: Icons.key_outlined),
      if (user.needsEmailVerification)
        ListTile(
          leading: const Icon(Icons.mark_email_unread_outlined),
          title: Text(l10n.emailNotVerified),
          trailing: TextButton(onPressed: () => context.go('/verify-email'), child: Text(l10n.verifyNow)),
        ),
      const _BiometricTile(),
      ListTile(
        key: const Key('security-sign-out'),
        leading: const Icon(Icons.logout),
        title: Text(l10n.securitySignOutHere),
        onTap: () => confirmSignOut(context),
      ),
      if (online)
        ListTile(
          key: const Key('security-revoke-all'),
          leading: const Icon(Icons.devices_other_outlined),
          title: Text(l10n.securityRevokeAll),
          subtitle: Text(l10n.securityRevokeAllHint),
          onTap: () => _revokeAll(context),
        ),
      InfoNote(l10n.securityNotAvailable),
      if (online) ...[
        SectionHeader(l10n.securityDangerZone),
        ListTile(
          key: const Key('settings-delete-account'),
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: Text(l10n.deleteAccountTitle, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          subtitle: Text(l10n.deleteAccountHint),
          onTap: () => deleteAccount(context),
        ),
      ],
    ]);
  }
}

Future<void> _revokeAll(BuildContext context) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final api = ApiScope.of(context);
  final auth = AuthScope.read(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.securityRevokeAll),
      content: Text(l10n.securityRevokeAllBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(key: const Key('confirm-revoke-all'), onPressed: () => Navigator.pop(context, true), child: Text(l10n.securityRevokeAllAction)),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await api.post('/me/sessions/revoke');
    await auth.signOut();
    messenger.showSnackBar(SnackBar(content: Text(l10n.securityRevokedDone)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.errorGeneric)));
  }
}

/// Desbloqueo con huella o rostro (sección 19).
class _BiometricTile extends StatefulWidget {
  const _BiometricTile();

  @override
  State<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends State<_BiometricTile> {
  BiometricAvailability? _availability;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    BiometricAuth.instance.availability().then((a) {
      if (mounted) setState(() => _availability = a);
    });
  }

  Future<void> _toggle(AppLockController lock, bool on) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      if (!on) {
        await lock.disable();
        messenger.showSnackBar(SnackBar(content: Text(l10n.biometricDisabled)));
        return;
      }
      final result = await lock.enable(l10n.biometricEnableReason);
      messenger.showSnackBar(SnackBar(
        content: Text(switch (result) {
          BiometricResult.success => l10n.biometricEnabled,
          BiometricResult.cancelled => l10n.biometricCancelled,
          BiometricResult.lockedOut => l10n.lockLockedOut,
          _ => l10n.biometricNotEnabled,
        }),
      ));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lock = AppLockScope.maybeOf(context);
    final availability = _availability;
    if (lock == null || availability == null) {
      return ListTile(leading: const Icon(Icons.fingerprint), title: Text(l10n.biometricTitle), subtitle: const LinearProgressIndicator());
    }
    final supported = availability == BiometricAvailability.available;
    return Column(children: [
      SwitchListTile(
        key: const Key('biometric-switch'),
        secondary: const Icon(Icons.fingerprint),
        title: Text(l10n.biometricTitle),
        subtitle: Text(switch (availability) {
          BiometricAvailability.available => l10n.biometricHint,
          BiometricAvailability.notEnrolled => l10n.biometricNotEnrolled,
          BiometricAvailability.unsupported => l10n.biometricUnsupported,
        }),
        value: lock.enabled,
        onChanged: _working || (!supported && !lock.enabled) ? null : (v) => _toggle(lock, v),
      ),
      InfoNote(l10n.biometricPrivacy, icon: Icons.privacy_tip_outlined),
    ]);
  }
}

// ── 4. Privacidad y visibilidad ─────────────────────────────────────────────
class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final online = ApiScope.of(context).isConfigured;
    return _Col([
      if (online) ...[
        const ProfileVisibilityTile(),
        ServerSettingsBuilder(
          builder: (context, s, save) => ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(l10n.privacyMessagesFrom),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                key: const Key('messages-from'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'everyone', label: Text(l10n.privacyEveryone)),
                  ButtonSegment(value: 'following', label: Text(l10n.privacyFollowing), tooltip: l10n.privacyFollowingHint),
                  ButtonSegment(value: 'nobody', label: Text(l10n.privacyNobody)),
                ],
                selected: {s.messagesFrom},
                onSelectionChanged: (v) => save({'privacy': {'messages': v.first}}),
              ),
            ),
          ),
        ),
      ],
      SectionHeader(l10n.privacyObservations),
      SwitchListTile(
        key: const Key('settings-observations-private'),
        secondary: const Icon(Icons.lock_outline),
        title: Text(l10n.settingsObservationsPrivate),
        subtitle: Text(l10n.settingsObservationsPrivateHint),
        value: settings.observationsPrivate,
        onChanged: (v) => applySetting(context, () => controller.setObservationsPrivate(v)),
      ),
      SwitchListTile(
        key: const Key('settings-hide-location'),
        secondary: const Icon(Icons.location_off_outlined),
        title: Text(l10n.privacyHideLocation),
        subtitle: Text(l10n.privacyHideLocationHint),
        value: settings.hideLocationByDefault,
        onChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(hideLocationByDefault: v))),
      ),
      InfoNote(l10n.settingsGeoprivacyBody, icon: Icons.location_searching),
      if (online) ...[
        SectionHeader(l10n.privacyBlockedTitle),
        ListTile(
          key: const Key('settings-blocked'),
          leading: const Icon(Icons.block),
          title: Text(l10n.privacyBlockedTitle),
          subtitle: Text(l10n.privacyBlockedHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/blocked'),
        ),
      ],
    ]);
  }
}

/// Personas bloqueadas, con la opción de desbloquear.
class BlockedPeoplePage extends StatefulWidget {
  const BlockedPeoplePage({super.key});

  @override
  State<BlockedPeoplePage> createState() => _BlockedPeoplePageState();
}

class _BlockedPeoplePageState extends State<BlockedPeoplePage> {
  Future<List<BlockedPerson>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ApiScope.of(context);
    if (api.isConfigured) _future ??= AccountApi(api).blocked();
  }

  Future<void> _unblock(BlockedPerson p) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final api = AccountApi(ApiScope.of(context));
    try {
      await api.unblock(p.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.privacyUnblocked(p.name))));
      final next = api.blocked();
      setState(() {
        _future = next;
      });
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(errorMessage(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final future = _future;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyBlockedTitle)),
      body: future == null
          ? const ServerNotConnectedView()
          : FutureBuilder<List<BlockedPerson>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return Center(child: Text(errorMessage(context, snap.error!)));
                final people = snap.data!;
                if (people.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l10n.privacyBlockedEmpty)));
                return ListView(children: [
                  for (final p in people)
                    ListTile(
                      key: Key('blocked-${p.id}'),
                      leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
                      title: Text(p.name),
                      subtitle: p.username == null ? null : Text('@${p.username}'),
                      trailing: TextButton(
                        key: Key('unblock-${p.id}'),
                        onPressed: () => _unblock(p),
                        child: Text(l10n.privacyUnblock),
                      ),
                    ),
                ]);
              },
            ),
    );
  }
}

// ── 5. Mapa ─────────────────────────────────────────────────────────────────
class _MapSection extends StatelessWidget {
  const _MapSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    return _Col([
      SectionHeader(l10n.mapDefaultBase),
      RadioGroup<MapBasePreference>(
        groupValue: settings.mapBase,
        onChanged: (v) {
          if (v != null) applySetting(context, () => controller.setMapBase(v));
        },
        child: Column(children: [
          RadioListTile<MapBasePreference>(
            key: const Key('map-base-streets'),
            value: MapBasePreference.streets,
            secondary: const Icon(Icons.map_outlined),
            title: Text(l10n.mapBaseStreets),
          ),
          RadioListTile<MapBasePreference>(
            key: const Key('map-base-topo'),
            value: MapBasePreference.topo,
            secondary: const Icon(Icons.terrain_outlined),
            title: Text(l10n.mapBaseTopo),
          ),
        ]),
      ),
      SectionHeader(l10n.mapDefaultLayers),
      SwitchListTile(
        key: const Key('map-show-observations'),
        secondary: const Icon(Icons.place_outlined),
        title: Text(l10n.mapLayerObservations),
        value: settings.mapShowObservations,
        onChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(mapShowObservations: v))),
      ),
      SwitchListTile(
        key: const Key('map-show-places'),
        secondary: const Icon(Icons.water_outlined),
        title: Text(l10n.mapLayerPlaces),
        value: settings.mapShowPlaces,
        onChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(mapShowPlaces: v))),
      ),
      InfoNote(l10n.mapOfflineNote, icon: Icons.cloud_off_outlined),
      ListTile(
        leading: const Icon(Icons.open_in_new),
        title: Text(l10n.mapOpen),
        onTap: () => context.go('/map'),
      ),
    ]);
  }
}

// ── 6. Cuaderno de campo ────────────────────────────────────────────────────
class _NotebookSection extends StatelessWidget {
  const _NotebookSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final signedIn = AuthScope.of(context).user != null;
    return _Col([
      SectionHeader(l10n.notebookDefaultColor),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in notebookColorOptions)
              Semantics(
                button: true,
                selected: settings.notebookColor == c,
                label: c,
                child: InkWell(
                  key: Key('notebook-color-$c'),
                  customBorder: const CircleBorder(),
                  onTap: () => applySetting(context, () => controller.update((s) => s.copyWith(notebookColor: c))),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: parseHex(c),
                    child: settings.notebookColor == c ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        key: const Key('notebook-public-default'),
        secondary: const Icon(Icons.public),
        title: Text(l10n.notebookPublicDefault),
        subtitle: Text(l10n.notebookPublicDefaultHint),
        value: settings.notebookPublic,
        onChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(notebookPublic: v))),
      ),
      InfoNote(l10n.notebookAutosaveNote, icon: Icons.save_outlined),
      if (signedIn)
        ListTile(
          leading: const Icon(Icons.restore_from_trash_outlined),
          title: Text(l10n.trashTitle),
          subtitle: Text(l10n.trashHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/trash'),
        ),
    ]);
  }
}

// ── 7. Stickers y cartas ────────────────────────────────────────────────────
class _StickersSection extends StatelessWidget {
  const _StickersSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final stickers = orderStickers(settings.favoriteStickers);
    return _Col([
      ListTile(
        leading: const Icon(Icons.photo_size_select_large_outlined),
        title: Text(l10n.stickerSize),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<double>(
            key: const Key('sticker-size'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: stickerSizeOptions[0], label: Text(l10n.sizeSmall)),
              ButtonSegment(value: stickerSizeOptions[1], label: Text(l10n.sizeMedium)),
              ButtonSegment(value: stickerSizeOptions[2], label: Text(l10n.sizeLarge)),
            ],
            selected: {settings.stickerSize},
            onSelectionChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(stickerSize: v.first))),
          ),
        ),
      ),
      SectionHeader(l10n.stickerFavorites),
      InfoNote(l10n.stickerFavoritesHint),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in stickers)
              _StickerTile(
                asset: a,
                favorite: settings.favoriteStickers.contains(a),
                onTap: () => applySetting(context, () => controller.toggleFavoriteSticker(a)),
              ),
          ],
        ),
      ),
      SectionHeader(l10n.cardsTitle),
      ListTile(
        key: const Key('stickers-album'),
        leading: const Icon(Icons.collections_bookmark_outlined),
        title: Text(l10n.cardsAlbum),
        subtitle: Text(l10n.cardsAlbumHint),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/album'),
      ),
    ]);
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.asset, required this.favorite, required this.onTap});

  final String asset;
  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: favorite,
      label: favorite ? l10n.stickerRemoveFavorite : l10n.stickerAddFavorite,
      child: InkWell(
        key: Key('fav-sticker-$asset'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 84,
          height: 84,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: favorite ? scheme.primary : scheme.outlineVariant, width: favorite ? 2 : 1),
          ),
          child: Stack(children: [
            Positioned.fill(
              child: Image.asset(asset, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined)),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Icon(favorite ? Icons.star : Icons.star_border, size: 18, color: favorite ? scheme.primary : scheme.outline),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── 8. Notificaciones ───────────────────────────────────────────────────────
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!ApiScope.of(context).isConfigured) return const _NoServer();
    String label(String k) => switch (k) {
          'follow' => l10n.notifPrefFollow,
          'comment' => l10n.notifPrefComment,
          'reaction' => l10n.notifPrefReaction,
          _ => l10n.notifPrefMessage,
        };
    IconData icon(String k) => switch (k) {
          'follow' => Icons.person_add_alt,
          'comment' => Icons.chat_bubble_outline,
          'reaction' => Icons.favorite_border,
          _ => Icons.mail_outline,
        };
    return _Col([
      InfoNote(l10n.notifPrefIntro),
      ServerSettingsBuilder(
        builder: (context, s, save) => Column(children: [
          for (final k in ServerSettings.notificationKinds)
            SwitchListTile(
              key: Key('notif-$k'),
              secondary: Icon(icon(k)),
              title: Text(label(k)),
              value: s.notifications[k] ?? true,
              onChanged: (v) => save({'notifications': {k: v}}),
            ),
        ]),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(l10n.notificationsTitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/notifications'),
      ),
      InfoNote(l10n.notifPushNote, icon: Icons.phonelink_off_outlined),
    ]);
  }
}

// ── 9. Apariencia ───────────────────────────────────────────────────────────
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    return _Col([
      SectionHeader(l10n.settingsTheme),
      RadioGroup<AppThemePreference>(
        groupValue: controller.settings.theme,
        onChanged: (value) {
          if (value != null) applySetting(context, () => controller.setTheme(value));
        },
        child: Column(children: [
          RadioListTile<AppThemePreference>(
            key: const Key('theme-system'),
            value: AppThemePreference.system,
            secondary: const Icon(Icons.brightness_auto_outlined),
            title: Text(l10n.themeSystem),
          ),
          RadioListTile<AppThemePreference>(
            key: const Key('theme-light'),
            value: AppThemePreference.light,
            secondary: const Icon(Icons.light_mode_outlined),
            title: Text(l10n.themeLight),
          ),
          RadioListTile<AppThemePreference>(
            key: const Key('theme-dark'),
            value: AppThemePreference.dark,
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.themeDark),
          ),
        ]),
      ),
      ListTile(
        leading: const Icon(Icons.accessibility_new),
        title: Text(l10n.appearanceMoreInAccessibility),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(SettingsSection.accessibility.route),
      ),
    ]);
  }
}

// ── 10. Idioma y región ─────────────────────────────────────────────────────
class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final current = settings.language ?? AppLanguage.tryParse(Localizations.localeOf(context).languageCode);
    final sample = DateTime(2026, 10, 9, 15, 30);
    return _Col([
      SectionHeader(l10n.settingsLanguage),
      InfoNote(l10n.settingsLanguageHint),
      RadioGroup<AppLanguage>(
        groupValue: current,
        onChanged: (value) {
          if (value != null) applySetting(context, () => controller.setLanguage(value));
        },
        child: Column(children: [
          for (final lang in AppLanguage.values)
            RadioListTile<AppLanguage>(
              key: Key('language-${lang.name}'),
              value: lang,
              title: Text(lang.nativeName, locale: Locale(lang == AppLanguage.arn ? 'es' : lang.name)),
              subtitle: lang.draft ? const Icon(Icons.rate_review_outlined, size: 16) : null,
            ),
        ]),
      ),
      if (current?.draft ?? false) InfoNote(l10n.languageDraftNote, icon: Icons.rate_review_outlined),
      if (current?.machine ?? false) InfoNote(l10n.languageMachineNote, icon: Icons.translate),
      SectionHeader(l10n.regionTitle),
      SwitchListTile(
        key: const Key('settings-24h'),
        secondary: const Icon(Icons.schedule),
        title: Text(l10n.region24h),
        subtitle: Text(l10n.regionExample(
          MaterialLocalizations.of(context).formatMediumDate(sample),
          MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(sample), alwaysUse24HourFormat: settings.use24h),
        )),
        value: settings.use24h,
        onChanged: (v) => applySetting(context, () => controller.update((s) => s.copyWith(use24h: v))),
      ),
      InfoNote(l10n.regionNote, icon: Icons.public),
    ]);
  }
}

// ── 11. Sincronización y almacenamiento ─────────────────────────────────────
class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  Future<MyStats>? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ApiScope.of(context);
    if (api.isConfigured) _stats ??= AccountApi(api).stats();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final api = ApiScope.of(context);
    final user = AuthScope.of(context).user;
    if (!api.isConfigured || user == null) return const _NoServer();
    final account = AccountApi(api);
    return _Col([
      const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: ServerAccountStatus()),
      InfoNote(l10n.syncWhatWhere, icon: Icons.cloud_done_outlined),
      SectionHeader(l10n.syncStorage),
      FutureBuilder<MyStats>(
        future: _stats,
        builder: (context, snap) {
          final s = snap.data;
          return ListTile(
            key: const Key('sync-storage'),
            leading: const Icon(Icons.storage_outlined),
            title: Text(s == null ? '…' : l10n.syncFiles(s['files'], formatBytes(s['storageBytes']))),
            subtitle: Text(l10n.syncStorageHint),
          );
        },
      ),
      ListTile(
        key: const Key('sync-clear-cache'),
        leading: const Icon(Icons.cleaning_services_outlined),
        title: Text(l10n.syncClearCache),
        subtitle: Text(l10n.syncClearCacheHint),
        onTap: () {
          final n = ApiImage.cachedCount;
          ApiImage.clearCache();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.syncCacheCleared(n))));
        },
      ),
      SectionHeader(l10n.settingsSectionData),
      ListTile(
        key: const Key('settings-trash'),
        leading: const Icon(Icons.restore_from_trash_outlined),
        title: Text(l10n.trashTitle),
        subtitle: Text(l10n.trashHint),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/trash'),
      ),
      ListTile(
        key: const Key('settings-export-all'),
        leading: const Icon(Icons.download_outlined),
        title: Text(l10n.settingsExportAll),
        subtitle: Text(l10n.settingsExportAllHint),
        onTap: () => downloadFile(context, account.exportAll, 'naturista-valdivia-mis-datos.json', 'application/json'),
      ),
      ListTile(
        key: const Key('settings-export-csv'),
        leading: const Icon(Icons.table_chart_outlined),
        title: Text(l10n.settingsExportCsv),
        subtitle: Text(l10n.settingsExportCsvHint),
        onTap: () => downloadFile(context, () => account.observationsCsv(user.uid), 'naturista-valdivia-observaciones.csv', 'text/csv'),
      ),
    ]);
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ── 12. Accesibilidad ───────────────────────────────────────────────────────
class _AccessibilitySection extends StatelessWidget {
  const _AccessibilitySection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    String scaleLabel(double v) => switch (v) {
          < 1.0 => l10n.textSizeSmall,
          1.0 => l10n.textSizeNormal,
          < 1.2 => l10n.textSizeLarge,
          _ => l10n.textSizeHuge,
        };
    return _Col([
      ListTile(
        leading: const Icon(Icons.format_size),
        title: Text(l10n.settingsTextSize),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<double>(
            key: const Key('text-size'),
            showSelectedIcon: false,
            segments: [
              for (final (i, v) in textScaleOptions.indexed)
                ButtonSegment(value: v, label: Text('A', style: TextStyle(fontSize: 12.0 + i * 3)), tooltip: scaleLabel(v)),
            ],
            selected: {settings.textScale},
            onSelectionChanged: (s) => applySetting(context, () => controller.setTextScale(s.first)),
          ),
        ),
      ),
      SwitchListTile(
        key: const Key('settings-high-contrast'),
        secondary: const Icon(Icons.contrast),
        title: Text(l10n.settingsHighContrast),
        subtitle: Text(l10n.settingsHighContrastHint),
        value: settings.highContrast,
        onChanged: (v) => applySetting(context, () => controller.setHighContrast(v)),
      ),
      SwitchListTile(
        key: const Key('settings-reduce-motion'),
        secondary: const Icon(Icons.motion_photos_off_outlined),
        title: Text(l10n.settingsReduceMotion),
        subtitle: Text(l10n.settingsReduceMotionHint),
        value: settings.reduceMotion,
        onChanged: (v) => applySetting(context, () => controller.setReduceMotion(v)),
      ),
      InfoNote(l10n.accessibilityScreenReader, icon: Icons.record_voice_over_outlined),
    ]);
  }
}

// ── 13. Estadísticas y logros ───────────────────────────────────────────────
class _StatsSection extends StatefulWidget {
  const _StatsSection();

  @override
  State<_StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<_StatsSection> {
  Future<MyStats>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ApiScope.of(context);
    if (api.isConfigured) _future ??= AccountApi(api).stats();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final future = _future;
    final user = AuthScope.of(context).user;
    if (future == null || user == null) return const _NoServer();
    return _Col([
      FutureBuilder<MyStats>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) return InfoNote(errorMessage(context, snap.error!), icon: Icons.cloud_off_outlined);
          final s = snap.data!;
          final items = [
            (l10n.statObservations, s['observations'], Icons.place_outlined),
            (l10n.statSpeciesObserved, s['speciesObserved'], Icons.eco_outlined),
            (l10n.statSpeciesUnlocked, s['speciesUnlocked'], Icons.collections_bookmark_outlined),
            (l10n.statNotebooks, s['notebooks'], Icons.menu_book_outlined),
            (l10n.statPages, s['pages'], Icons.description_outlined),
            (l10n.statPosts, s['posts'], Icons.forum_outlined),
            (l10n.statFollowers, s['followers'], Icons.people_outline),
            (l10n.statFollowing, s['following'], Icons.person_add_alt),
          ];
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, value, icon) in items)
                      SizedBox(
                        width: 160,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Semantics(
                              label: '$label: $value',
                              excludeSemantics: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(height: 6),
                                  Text('$value', style: Theme.of(context).textTheme.headlineSmall),
                                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (s.firstObservationAt != null)
                  InfoNote(l10n.statFirstObservation(_date(context, s.firstObservationAt)), icon: Icons.flag_outlined),
              ],
            ),
          );
        },
      ),
      ListTile(
        key: const Key('stats-album'),
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text(l10n.statAchievements),
        subtitle: Text(l10n.settingsAlbumHint),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/album'),
      ),
      ListTile(
        leading: const Icon(Icons.table_chart_outlined),
        title: Text(l10n.settingsExportCsv),
        subtitle: Text(l10n.settingsExportCsvHint),
        onTap: () => downloadFile(
          context,
          () => AccountApi(ApiScope.of(context)).observationsCsv(user.uid),
          'naturista-valdivia-observaciones.csv',
          'text/csv',
        ),
      ),
    ]);
  }
}

// ── 14. Contacto ────────────────────────────────────────────────────────────
class _ContactSection extends StatefulWidget {
  const _ContactSection();

  @override
  State<_ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends State<_ContactSection> {
  final _message = TextEditingController();
  String _kind = 'bug';
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final api = AccountApi(ApiScope.of(context));
    setState(() => _sending = true);
    try {
      await api.sendFeedback(kind: _kind, message: text, appVersion: appVersion, platform: Theme.of(context).platform.name);
      _message.clear();
      messenger.showSnackBar(SnackBar(content: Text(l10n.contactSent)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(errorMessage(context, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!ApiScope.of(context).isConfigured) return const _NoServer();
    return _Col([
      InfoNote(l10n.contactIntro, icon: Icons.mail_outline),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SegmentedButton<String>(
          key: const Key('contact-kind'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'bug', label: Text(l10n.contactBug)),
            ButtonSegment(value: 'idea', label: Text(l10n.contactIdea)),
            ButtonSegment(value: 'question', label: Text(l10n.contactQuestion)),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const Key('contact-message'),
          controller: _message,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          decoration: InputDecoration(labelText: l10n.contactMessage, alignLabelWithHint: true),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          key: const Key('contact-send'),
          onPressed: _sending || _message.text.trim().isEmpty ? null : _send,
          icon: _sending
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_outlined),
          label: Text(l10n.contactSend),
        ),
      ),
      InfoNote(l10n.contactReportNote, icon: Icons.flag_outlined),
    ]);
  }
}

/// Versión mostrada en "Información" y enviada con los mensajes de contacto.
const appVersion = '0.1.0';

// ── 17. Información ─────────────────────────────────────────────────────────
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final api = ApiScope.of(context);
    return _Col([
      ListTile(leading: const Icon(Icons.eco_outlined), title: Text(l10n.appTitle), subtitle: Text(l10n.aboutLegalese)),
      ListTile(leading: const Icon(Icons.numbers), title: Text(l10n.aboutVersion), subtitle: const Text(appVersion)),
      ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text(l10n.aboutServer),
        subtitle: Text(api.isConfigured ? l10n.aboutServerConnected : l10n.serverNotConnectedTitle),
      ),
      InfoNote(l10n.aboutBody, icon: Icons.map_outlined),
      InfoNote(l10n.aboutTech, icon: Icons.build_outlined),
      ListTile(
        key: const Key('about-licenses'),
        leading: const Icon(Icons.description_outlined),
        title: Text(l10n.aboutLicenses),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showLicensePage(context: context, applicationName: l10n.appTitle, applicationVersion: appVersion),
      ),
    ]);
  }
}
