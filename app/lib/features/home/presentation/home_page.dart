import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_modules.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';

/// Inicio: guía de uso, estado real de los módulos e ilustraciones propias.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const featuredIllustrations = <({String asset, String label})>[
    (asset: 'assets/illustrations/aves/chucao.jpg', label: 'Chucao'),
    (asset: 'assets/illustrations/flora/copihue.jpg', label: 'Copihue'),
    (asset: 'assets/illustrations/mamiferos/huillin.jpg', label: 'Huillín'),
    (asset: 'assets/illustrations/aves/cisnes.jpg', label: 'Cisne de cuello negro'),
    (asset: 'assets/illustrations/funga/oreja_de_palo.jpg', label: 'Oreja de palo'),
    (asset: 'assets/illustrations/insectos/bombus.webp', label: 'Bombus'),
    (asset: 'assets/illustrations/flora/nipa.jpg', label: 'Ñipa'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const illustrations = featuredIllustrations;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.navSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 3
              : constraints.maxWidth >= 640
                  ? 2
                  : 1;
          return CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: _HeroCard()),
              ),
              _SectionTitle(l10n.homeHowItWorks),
              SliverToBoxAdapter(child: _Steps()),
              _SectionTitle(l10n.homeModulesTitle, subtitle: l10n.homeModulesBody),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 132,
                  ),
                  itemCount: appModules.length,
                  itemBuilder: (context, i) => _ModuleCard(module: appModules[i]),
                ),
              ),
              _SectionTitle(l10n.galleryTitle, subtitle: l10n.galleryBody),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: illustrations.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _Illustration(
                      asset: illustrations[i].asset,
                      label: illustrations[i].label,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
            if (subtitle != null)
              Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final steps = [
      (Icons.login, l10n.stepEnterTitle, l10n.stepEnterBody),
      (Icons.visibility_outlined, l10n.stepObserveTitle, l10n.stepObserveBody),
      (Icons.add_a_photo_outlined, l10n.stepDetailTitle, l10n.stepDetailBody),
      (Icons.menu_book_outlined, l10n.stepOrganizeTitle, l10n.stepOrganizeBody),
      (Icons.share_outlined, l10n.stepShareTitle, l10n.stepShareBody),
    ];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final (icon, title, body) = steps[i];
          final theme = Theme.of(context);
          return SizedBox(
            width: 210,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        Icon(icon, size: 20, color: theme.colorScheme.primary),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(body, style: theme.textTheme.bodySmall, overflow: TextOverflow.fade),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final phase = module.phase;
    final status = phase == null ? l10n.statusAvailable : l10n.statusInPhase(phase);
    final statusColor = phase == null ? theme.colorScheme.primary : theme.colorScheme.outline;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => shellRoutes.contains(module.route)
            ? context.go(module.route)
            : context.push(module.route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(module.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(module.title(l10n), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        module.description(l10n),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                    Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: label,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  width: 150,
                  cacheWidth: 300,
                  errorBuilder: (context, _, _) => ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.image_not_supported_outlined)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Cabecera del inicio (pantalla 41 de la lámina): ilustración con velo
/// oscuro, saludo o invitación a iniciar sesión.
class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final auth = AuthScope.of(context);
    final user = auth.user;
    final name = user?.displayName?.split(' ').first ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/illustrations/aves/cisnes.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => const ColoredBox(color: AppColors.forestDark),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x331C3320), Color(0xE61C3320)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    user == null ? l10n.appTitle : l10n.homeGreeting(name.isEmpty ? (user.email ?? '') : name),
                    style: text.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user == null ? l10n.homeSignInPrompt : l10n.appTagline,
                    style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  if (user == null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('home-sign-in'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.forestDark,
                        minimumSize: const Size(140, 44),
                      ),
                      onPressed: () => context.go('/login'),
                      child: Text(l10n.signIn),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
