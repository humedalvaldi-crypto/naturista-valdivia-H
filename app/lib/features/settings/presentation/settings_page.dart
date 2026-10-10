import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/files/file_export.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../application/settings_controller.dart';
import '../data/account_api.dart';
import '../data/settings_repository.dart';

/// Configuración. Solo contiene opciones que funcionan de verdad: cada
/// interruptor cambia algo visible en la app o en el servidor.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final user = AuthScope.of(context).user;
    final api = ApiScope.of(context);
    final online = user != null && api.isConfigured;
    final currentLanguage =
        settings.language ?? AppLanguage.tryParse(Localizations.localeOf(context).languageCode);

    Future<void> apply(Future<bool> Function() change) async {
      final messenger = ScaffoldMessenger.of(context);
      final errorText = l10n.errorGeneric;
      final ok = await change();
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(errorText)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (user != null) _AccountHeader(user: user) else _SignInPrompt(),

              // ── Cuenta y perfil ──────────────────────────────────────────
              if (user != null) ...[
                _SectionHeader(l10n.settingsSectionAccount),
                if (online)
                  ListTile(
                    key: const Key('settings-edit-profile'),
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(l10n.settingsEditProfile),
                    subtitle: Text(l10n.settingsEditProfileHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/profile'),
                  ),
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
                if (user.usesPassword && user.email != null)
                  ListTile(
                    key: const Key('settings-change-password'),
                    leading: const Icon(Icons.password_outlined),
                    title: Text(l10n.settingsChangePassword),
                    subtitle: Text(l10n.settingsChangePasswordHint),
                    onTap: () => _sendPasswordReset(context, user.email!),
                  ),
              ],

              // ── Privacidad ───────────────────────────────────────────────
              if (user != null) ...[
                _SectionHeader(l10n.settingsSectionPrivacy),
                if (online) const _ProfileVisibilityTile(),
                SwitchListTile(
                  key: const Key('settings-observations-private'),
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(l10n.settingsObservationsPrivate),
                  subtitle: Text(l10n.settingsObservationsPrivateHint),
                  value: settings.observationsPrivate,
                  onChanged: (v) => apply(() => controller.setObservationsPrivate(v)),
                ),
                ListTile(
                  leading: const Icon(Icons.location_searching),
                  title: Text(l10n.settingsGeoprivacyTitle),
                  subtitle: Text(l10n.settingsGeoprivacyBody),
                ),
              ],

              // ── Mapa ─────────────────────────────────────────────────────
              _SectionHeader(l10n.settingsSectionMap),
              RadioGroup<MapBasePreference>(
                groupValue: settings.mapBase,
                onChanged: (v) {
                  if (v != null) apply(() => controller.setMapBase(v));
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

              // ── Apariencia ───────────────────────────────────────────────
              _SectionHeader(l10n.settingsTheme),
              RadioGroup<AppThemePreference>(
                groupValue: settings.theme,
                onChanged: (value) {
                  if (value != null) apply(() => controller.setTheme(value));
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

              // ── Accesibilidad ────────────────────────────────────────────
              _SectionHeader(l10n.settingsSectionAccessibility),
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
                        ButtonSegment(
                          value: v,
                          label: Text('A', style: TextStyle(fontSize: 12.0 + i * 3)),
                          tooltip: _scaleLabel(l10n, v),
                        ),
                    ],
                    selected: {settings.textScale},
                    onSelectionChanged: (s) => apply(() => controller.setTextScale(s.first)),
                  ),
                ),
              ),
              SwitchListTile(
                key: const Key('settings-high-contrast'),
                secondary: const Icon(Icons.contrast),
                title: Text(l10n.settingsHighContrast),
                subtitle: Text(l10n.settingsHighContrastHint),
                value: settings.highContrast,
                onChanged: (v) => apply(() => controller.setHighContrast(v)),
              ),
              SwitchListTile(
                key: const Key('settings-reduce-motion'),
                secondary: const Icon(Icons.motion_photos_off_outlined),
                title: Text(l10n.settingsReduceMotion),
                subtitle: Text(l10n.settingsReduceMotionHint),
                value: settings.reduceMotion,
                onChanged: (v) => apply(() => controller.setReduceMotion(v)),
              ),

              // ── Idioma ───────────────────────────────────────────────────
              _SectionHeader(l10n.settingsLanguage),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l10n.settingsLanguageHint, style: Theme.of(context).textTheme.bodySmall),
              ),
              RadioGroup<AppLanguage>(
                groupValue: currentLanguage,
                onChanged: (value) {
                  if (value != null) apply(() => controller.setLanguage(value));
                },
                child: Column(children: [
                  RadioListTile<AppLanguage>(
                    key: const Key('language-es'),
                    value: AppLanguage.es,
                    title: Text(l10n.languageSpanish),
                  ),
                  RadioListTile<AppLanguage>(
                    key: const Key('language-en'),
                    value: AppLanguage.en,
                    title: Text(l10n.languageEnglish),
                  ),
                ]),
              ),

              // ── Tus datos ────────────────────────────────────────────────
              if (online) ...[
                _SectionHeader(l10n.settingsSectionData),
                ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text(l10n.myAlbum),
                  subtitle: Text(l10n.settingsAlbumHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/album'),
                ),
                ListTile(
                  key: const Key('settings-trash'),
                  leading: const Icon(Icons.restore_from_trash_outlined),
                  title: Text(l10n.trashTitle),
                  subtitle: Text(l10n.trashHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/trash'),
                ),
                ListTile(
                  key: const Key('settings-export-csv'),
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(l10n.settingsExportCsv),
                  subtitle: Text(l10n.settingsExportCsvHint),
                  onTap: () => _download(
                    context,
                    () => AccountApi(api).observationsCsv(user.uid),
                    'naturista-valdivia-observaciones.csv',
                    'text/csv',
                  ),
                ),
                ListTile(
                  key: const Key('settings-export-all'),
                  leading: const Icon(Icons.download_outlined),
                  title: Text(l10n.settingsExportAll),
                  subtitle: Text(l10n.settingsExportAllHint),
                  onTap: () => _download(
                    context,
                    () => AccountApi(api).exportAll(),
                    'naturista-valdivia-mis-datos.json',
                    'application/json',
                  ),
                ),
                ListTile(
                  key: const Key('settings-delete-account'),
                  leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                  title: Text(l10n.deleteAccountTitle, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  subtitle: Text(l10n.deleteAccountHint),
                  onTap: () => _deleteAccount(context),
                ),
              ],

              // ── Ayuda e información ──────────────────────────────────────
              _SectionHeader(l10n.settingsSectionHelp),
              ListTile(
                key: const Key('settings-help'),
                leading: const Icon(Icons.help_outline),
                title: Text(l10n.helpTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/help'),
              ),
              ListTile(
                key: const Key('settings-legal'),
                leading: const Icon(Icons.policy_outlined),
                title: Text(l10n.legalTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/privacy'),
              ),
              ListTile(
                key: const Key('settings-about'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.aboutTitle),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: l10n.appTitle,
                  applicationVersion: '0.1.0',
                  applicationLegalese: l10n.aboutLegalese,
                  children: [Padding(padding: const EdgeInsets.only(top: 12), child: Text(l10n.aboutBody))],
                ),
              ),
              if (user != null) ...[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    key: const Key('settings-sign-out'),
                    onPressed: () => _confirmSignOut(context),
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

  static String _scaleLabel(AppLocalizations l10n, double v) => switch (v) {
        < 1.0 => l10n.textSizeSmall,
        1.0 => l10n.textSizeNormal,
        < 1.2 => l10n.textSizeLarge,
        _ => l10n.textSizeHuge,
      };

  static Future<void> _sendPasswordReset(BuildContext context, String email) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AuthScope.read(context).sendPasswordReset(email);
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsPasswordResetSent(email))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(authErrorText(l10n, e))));
    }
  }

  static Future<void> _download(
    BuildContext context,
    Future<Uint8List> Function() fetch,
    String fileName,
    String mime,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
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
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.errorGeneric)));
    }
  }

  static Future<void> _deleteAccount(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final api = AccountApi(ApiScope.of(context));
    final auth = AuthScope.read(context);
    final confirmed = await showDialog<bool>(context: context, builder: (context) => const _DeleteAccountDialog());
    if (confirmed != true) return;
    try {
      await api.deleteAccount();
      await auth.signOut();
      messenger.showSnackBar(SnackBar(content: Text(l10n.deleteAccountDone), duration: const Duration(seconds: 8)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.errorGeneric)));
    }
  }

  static Future<void> _confirmSignOut(BuildContext context) async {
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Card(
        child: ListTile(
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
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

/// Quién puede ver el perfil (se guarda en el servidor).
class _ProfileVisibilityTile extends StatefulWidget {
  const _ProfileVisibilityTile();

  @override
  State<_ProfileVisibilityTile> createState() => _ProfileVisibilityTileState();
}

class _ProfileVisibilityTileState extends State<_ProfileVisibilityTile> {
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
    final l10n = context.l10n;
    final previous = _value;
    setState(() {
      _value = value;
      _saving = true;
    });
    try {
      await AccountApi(ApiScope.of(context)).updateProfile({'visibility': value});
    } catch (e) {
      if (mounted) setState(() => _value = previous);
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.errorGeneric)));
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
      trailing: _error != null ? IconButton(icon: const Icon(Icons.refresh), tooltip: l10n.retry, onPressed: () {
        setState(() => _error = null);
        _load();
      }) : null,
    );
  }
}

/// Pide escribir ELIMINAR para confirmar.
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

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
