import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/firebase_config.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/settings/application/settings_controller.dart';
import 'features/settings/data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En la web, que la URL refleje también las pantallas abiertas con push
  // (p. ej. Configuración), para poder recargar o compartir el enlace.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(LocalSettingsRepository(prefs));
  await settings.load();

  runApp(NaturistaApp(settings: settings, auth: await _createAuth()));
}

/// Inicializa Firebase. Si falla (sin red al primer arranque, configuración
/// inválida), la app sigue funcionando sin sesión y lo explica al intentar entrar.
Future<AuthController> _createAuth() async {
  try {
    await Firebase.initializeApp(options: FirebaseConfig.currentPlatform);
    return AuthController(FirebaseAuthRepository(FirebaseAuth.instance));
  } catch (error) {
    if (kDebugMode) debugPrint('Firebase no disponible: $error');
    return AuthController(const UnavailableAuthRepository(), available: false);
  }
}
