import 'package:flutter/material.dart';

import '../../../shared/widgets/planned_module_page.dart';

/// Módulo planificado (ver `core/router/app_modules.dart` para su fase).
class NotebooksPage extends StatelessWidget {
  const NotebooksPage({super.key});

  @override
  Widget build(BuildContext context) => const PlannedModulePage(moduleId: 'notebooks');
}
