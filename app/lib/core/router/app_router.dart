import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/biodiversity_map/presentation/biodiversity_map_page.dart';
import '../../features/communities/presentation/communities_page.dart';
import '../../features/drawing_editor/presentation/drawing_editor_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/notebooks/presentation/notebooks_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/observations/presentation/observations_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/social/presentation/social_page.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../shared/widgets/state_views.dart';
import '../l10n/l10n.dart';

/// Rutas de la aplicación. En la Fase 3 se añade `redirect` para proteger
/// las pantallas privadas según el estado de autenticación.
///
/// [initialLocation] solo se usa en pruebas. En la web debe quedar en `null`
/// para que un enlace directo (p. ej. `#/settings`) abra esa pantalla.
GoRouter buildRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/map', builder: (context, state) => const BiodiversityMapPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notebooks', builder: (context, state) => const NotebooksPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/community', builder: (context, state) => const SocialFeedPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
          ]),
        ],
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(path: '/observations', builder: (context, state) => const ObservationsPage()),
      GoRoute(path: '/drawing', builder: (context, state) => const DrawingEditorPage()),
      GoRoute(path: '/communities', builder: (context, state) => const CommunitiesPage()),
      GoRoute(path: '/messages', builder: (context, state) => const MessagesPage()),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsPage()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.notFoundTitle)),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Expanded(child: EmptyView(icon: Icons.explore_off_outlined)),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: FilledButton(
              onPressed: () => context.go('/'),
              child: Text(context.l10n.goHome),
            ),
          ),
        ],
      ),
    ),
  );
}
