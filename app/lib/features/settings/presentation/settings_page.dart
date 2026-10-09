import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../application/settings_controller.dart';
import '../data/settings_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final currentLanguage =
        settings.language ?? AppLanguage.tryParse(Localizations.localeOf(context).languageCode);

    Future<void> apply(Future<bool> Function() change) async {
      final messenger = ScaffoldMessenger.of(context);
      final errorText = l10n.errorGeneric;
      final ok = await change();
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(errorText)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
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
            child: Column(
              children: [
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
              ],
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.settingsTheme),
          RadioGroup<AppThemePreference>(
            groupValue: settings.theme,
            onChanged: (value) {
              if (value != null) apply(() => controller.setTheme(value));
            },
            child: Column(
              children: [
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
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            subtitle: Text(l10n.settingsSyncNote),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }
}
