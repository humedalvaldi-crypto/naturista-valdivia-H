import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/app_modules.dart';
import 'state_views.dart';

/// Página de un módulo todavía no construido, basada en el catálogo real.
class PlannedModulePage extends StatelessWidget {
  const PlannedModulePage({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final module = moduleById(moduleId);
    final l10n = context.l10n;
    return PlannedFeatureView(
      title: module.title(l10n),
      description: module.description(l10n),
      phase: module.phase ?? 0,
      icon: module.icon,
    );
  }
}
