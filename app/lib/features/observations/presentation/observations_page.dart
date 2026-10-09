import 'package:flutter/material.dart';

import '../../../shared/widgets/planned_module_page.dart';

/// Módulo planificado (ver `core/router/app_modules.dart` para su fase).
class ObservationsPage extends StatelessWidget {
  const ObservationsPage({super.key});

  @override
  Widget build(BuildContext context) => const PlannedModulePage(moduleId: 'observations');
}
