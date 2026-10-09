import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/auth/presentation/verify_email_page.dart';
import '../../features/auth/presentation/welcome_page.dart';
import '../../features/biodiversity_map/presentation/biodiversity_map_page.dart';
import '../../features/communities/presentation/communities_page.dart';
import '../../features/drawing_editor/presentation/drawing_editor_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/notebooks/presentation/notebooks_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/observations/presentation/observations_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/settings/application/settings_controller.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/social/presentation/social_page.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../shared/widgets/state_views.dart';
import '../l10n/l10n.dart';

/// Rutas que exigen sesión iniciada.
const privateRoutes = {'/profile', '/notebooks', '/drawing', '/observations', '/messages', '/notifications'};

/// Pantallas de acceso: con sesión iniciada no tienen sentido.
const authRoutes = {'/login', '/register', '/forgot-password'};

bool _matches(Set<String> routes, String path) =>
    routes.any((r) => path == r || path.startsWith('$r/'));

/// Decide a dónde ir según la sesión y la bienvenida. Pública para probarla
/// sin construir widgets.
String? resolveRedirect({
  required AuthStatus status,
  required bool needsEmailVerification,
  required bool onboardingDone,
  required Uri location,
}) {
  final path = location.path;

  // 1. Mientras se restaura la sesión guardada: splash.
  if (status == AuthStatus.unknown) {
    return path == '/splash' ? null : Uri(path: '/splash', queryParameters: {'from': location.toString()}).toString();
  }
  final from = location.queryParameters['from'];
  if (path == '/splash') return _safeFrom(from) ?? '/';

  // 2. Bienvenida, una sola vez por dispositivo.
  if (!onboardingDone) return path == '/welcome' ? null : '/welcome';
  if (path == '/welcome') return '/';

  final signedIn = status == AuthStatus.signedIn;

  // 3. Rutas privadas sin sesión → login, recordando a dónde se quería ir.
  if (!signedIn && (_matches(privateRoutes, path) || path == '/verify-email')) {
    return Uri(path: '/login', queryParameters: {'from': location.toString()}).toString();
  }

  // 4. Con sesión, fuera de las pantallas de acceso.
  if (signedIn && _matches(authRoutes, path)) {
    if (needsEmailVerification && path == '/register') return '/verify-email';
    return _safeFrom(from) ?? '/';
  }
  return null;
}

/// Solo rutas internas: evita redirecciones abiertas a otros sitios.
String? _safeFrom(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) return null;
  if (from.startsWith('/splash') || from.startsWith('/welcome')) return null;
  return from;
}

/// [initialLocation] solo se usa en pruebas. En la web debe quedar en `null`
/// para que un enlace directo (p. ej. `#/settings`) abra esa pantalla.
GoRouter buildRouter({
  required AuthController auth,
  required SettingsController settings,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([auth, settings]),
    redirect: (context, state) => resolveRedirect(
      status: auth.status,
      needsEmailVerification: auth.user?.needsEmailVerification ?? false,
      onboardingDone: settings.settings.onboardingDone,
      location: state.uri,
    ),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomePage()),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(from: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegisterPage(from: state.uri.queryParameters['from']),
      ),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordPage()),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailPage()),
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
