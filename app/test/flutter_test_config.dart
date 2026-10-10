import 'dart:async';

import 'package:naturista_valdivia/shared/map/map_tiles.dart';

/// Configuración común: las pruebas no piden teselas de mapa por la red.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MapTiles.enabled = false;
  await testMain();
}
