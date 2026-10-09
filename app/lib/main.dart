import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
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

  runApp(NaturistaApp(settings: settings));
}
