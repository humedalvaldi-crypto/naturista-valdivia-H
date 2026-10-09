import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../branding/brand.dart';

/// Vistas estándar de estado: carga, error, vacío y módulo planificado.
/// Todas las pantallas que cargan datos deben usar estas piezas.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: message ?? context.l10n.loading,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message ?? context.l10n.loading),
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return _CenteredMessage(
      frog: FrogSticker.crying,
      title: message ?? context.l10n.errorGeneric,
      action: retry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.retry),
            ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, this.message, this.icon = Icons.eco_outlined});

  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(frog: FrogSticker.tired, title: message ?? context.l10n.emptyGeneric);
  }
}

/// Pantalla honesta para un módulo que todavía no existe: no simula datos
/// ni ofrece botones que no hacen nada.
class PlannedFeatureView extends StatelessWidget {
  const PlannedFeatureView({
    super.key,
    required this.title,
    required this.description,
    required this.phase,
    required this.icon,
  });

  final String title;
  final String description;
  final int phase;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _CenteredMessage(
        frog: FrogSticker.idea,
        title: l10n.plannedTitle,
        body: '$description\n\n${l10n.plannedBody(phase)}',
        badge: l10n.statusInPhase(phase),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.frog,
    required this.title,
    this.body,
    this.badge,
    this.action,
  });

  final FrogSticker frog;
  final String title;
  final String? body;
  final String? badge;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = this.body;
    final badge = this.badge;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FrogImage(frog, size: 120),
              const SizedBox(height: 16),
              if (badge != null) ...[
                Chip(label: Text(badge)),
                const SizedBox(height: 8),
              ],
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
