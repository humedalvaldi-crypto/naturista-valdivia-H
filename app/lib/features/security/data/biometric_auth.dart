import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Qué ofrece este dispositivo.
enum BiometricAvailability {
  /// Hay huella o rostro registrados.
  available,

  /// El dispositivo lo admite pero no hay huella ni rostro registrados.
  notEnrolled,

  /// No hay sensor o la plataforma no lo admite (p. ej. el navegador).
  unsupported,
}

/// Resultado de un intento. Nunca incluye datos biométricos: el sistema
/// operativo compara la huella o el rostro y solo responde sí o no.
enum BiometricResult { success, failed, cancelled, lockedOut, unavailable }

/// Acceso a la biometría del sistema operativo (BiometricPrompt en Android).
/// Las pruebas reemplazan [instance]; la app nunca simula un éxito.
abstract class BiometricAuth {
  static BiometricAuth instance = kIsWeb ? const UnsupportedBiometricAuth() : DeviceBiometricAuth();

  Future<BiometricAvailability> availability();

  /// Muestra el diálogo del sistema. Solo huella o rostro: sin PIN propio de la app.
  Future<BiometricResult> authenticate(String reason);
}

/// Navegador u otra plataforma sin biometría compatible.
class UnsupportedBiometricAuth implements BiometricAuth {
  const UnsupportedBiometricAuth();

  @override
  Future<BiometricAvailability> availability() async => BiometricAvailability.unsupported;

  @override
  Future<BiometricResult> authenticate(String reason) async => BiometricResult.unavailable;
}

class DeviceBiometricAuth implements BiometricAuth {
  final _auth = LocalAuthentication();

  @override
  Future<BiometricAvailability> availability() async {
    try {
      if (!await _auth.isDeviceSupported()) return BiometricAvailability.unsupported;
      if (!await _auth.canCheckBiometrics) return BiometricAvailability.unsupported;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isEmpty ? BiometricAvailability.notEnrolled : BiometricAvailability.available;
    } catch (_) {
      return BiometricAvailability.unsupported;
    }
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout =>
          BiometricResult.cancelled,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => BiometricResult.lockedOut,
        _ => BiometricResult.unavailable,
      };
    } catch (_) {
      return BiometricResult.unavailable;
    }
  }
}

/// Dónde se recuerda que el desbloqueo está activado y para qué cuenta.
/// Se guarda solo el UID (nunca tokens ni datos biométricos) en el
/// almacenamiento seguro del sistema (Keystore en Android).
abstract class BiometricStore {
  static BiometricStore instance = SecureBiometricStore();

  Future<String?> enabledUid();
  Future<void> enable(String uid);
  Future<void> disable();
}

class SecureBiometricStore implements BiometricStore {
  static const _key = 'nv.biometricUnlock.uid';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> enabledUid() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null; // si el almacén falla, se pide la cuenta (más seguro)
    }
  }

  @override
  Future<void> enable(String uid) => _storage.write(key: _key, value: uid);

  @override
  Future<void> disable() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// Para pruebas.
class MemoryBiometricStore implements BiometricStore {
  String? uid;

  @override
  Future<String?> enabledUid() async => uid;

  @override
  Future<void> enable(String uid) async => this.uid = uid;

  @override
  Future<void> disable() async => uid = null;
}
