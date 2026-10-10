import 'dart:async';

import 'package:naturista_valdivia/features/security/data/biometric_auth.dart';
import 'package:naturista_valdivia/shared/map/map_tiles.dart';

/// Configuración común: las pruebas no piden teselas de mapa por la red y
/// no usan el almacenamiento seguro ni la biometría reales del sistema.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MapTiles.enabled = false;
  BiometricAuth.instance = const UnsupportedBiometricAuth();
  BiometricStore.instance = MemoryBiometricStore();
  await testMain();
}
