import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Catálogo de módulos con su estado REAL. `phase == null` significa que el
/// módulo ya funciona; en otro caso indica la fase del plan en que se construye.
/// Al terminar una fase, se actualiza aquí y la UI refleja el cambio.
class AppModule {
  const AppModule({
    required this.id,
    required this.route,
    required this.icon,
    required this.title,
    required this.description,
    this.phase,
  });

  final String id;
  final String route;
  final IconData icon;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) description;
  final int? phase;

  bool get isAvailable => phase == null;
}

final List<AppModule> appModules = [
  AppModule(
    id: 'observations',
    route: '/observations',
    icon: Icons.visibility_outlined,
    title: (l) => l.moduleObservations,
    description: (l) => l.moduleObservationsBody,
    phase: 7,
  ),
  AppModule(
    id: 'map',
    route: '/map',
    icon: Icons.map_outlined,
    title: (l) => l.moduleMap,
    description: (l) => l.moduleMapBody,
    phase: 7,
  ),
  AppModule(
    id: 'notebooks',
    route: '/notebooks',
    icon: Icons.menu_book_outlined,
    title: (l) => l.moduleNotebooks,
    description: (l) => l.moduleNotebooksBody,
    phase: 6,
  ),
  AppModule(
    id: 'drawing',
    route: '/drawing',
    icon: Icons.brush_outlined,
    title: (l) => l.moduleDrawing,
    description: (l) => l.moduleDrawingBody,
    phase: 6,
  ),
  AppModule(
    id: 'social',
    route: '/community',
    icon: Icons.dynamic_feed_outlined,
    title: (l) => l.moduleSocial,
    description: (l) => l.moduleSocialBody,
  ),
  AppModule(
    id: 'communities',
    route: '/communities',
    icon: Icons.groups_outlined,
    title: (l) => l.moduleCommunities,
    description: (l) => l.moduleCommunitiesBody,
  ),
  AppModule(
    id: 'messages',
    route: '/messages',
    icon: Icons.chat_bubble_outline,
    title: (l) => l.moduleMessages,
    description: (l) => l.moduleMessagesBody,
    phase: 5,
  ),
  AppModule(
    id: 'notifications',
    route: '/notifications',
    icon: Icons.notifications_none,
    title: (l) => l.moduleNotifications,
    description: (l) => l.moduleNotificationsBody,
  ),
  AppModule(
    id: 'profile',
    route: '/profile',
    icon: Icons.person_outline,
    title: (l) => l.moduleProfile,
    description: (l) => l.moduleProfileBody,
  ),
  AppModule(
    id: 'settings',
    route: '/settings',
    icon: Icons.settings_outlined,
    title: (l) => l.moduleSettings,
    description: (l) => l.moduleSettingsBody,
  ),
];

AppModule moduleById(String id) => appModules.firstWhere((m) => m.id == id);

/// Rutas que viven dentro de la navegación principal (pestañas).
const shellRoutes = {'/', '/map', '/notebooks', '/community', '/profile'};
