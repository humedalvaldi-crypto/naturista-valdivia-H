import 'package:flutter/material.dart';

import '../../../shared/widgets/planned_module_page.dart';

/// Módulo planificado (ver `core/router/app_modules.dart` para su fase).
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) => const PlannedModulePage(moduleId: 'messages');
}
