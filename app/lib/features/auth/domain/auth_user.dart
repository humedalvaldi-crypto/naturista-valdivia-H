import 'package:flutter/widgets.dart';

/// Usuario autenticado. `uid` es el UID de Firebase y la clave en la API.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
    this.providers = const [],
    this.createdAt,
    this.lastSignInAt,
  });

  /// Fechas de Firebase: creación de la cuenta y último inicio de sesión.
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;

  /// IDs de proveedor de Firebase: `google.com`, `password`, ...
  final List<String> providers;

  bool get usesPassword => providers.contains('password');

  /// Las cuentas de Google ya vienen con el correo verificado; solo pedimos
  /// verificación a las cuentas creadas con correo y contraseña.
  bool get needsEmailVerification => usesPassword && !emailVerified;

  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : (email ?? '?');
    final parts = source.split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }
}

/// Errores de autenticación con códigos estables para traducir en la UI.
enum AuthErrorCode {
  invalidCredentials,
  emailInUse,
  weakPassword,
  invalidEmail,
  userDisabled,
  tooManyRequests,
  network,
  cancelled,
  accountExistsWithDifferentCredential,
  multiFactorRequired,
  requiresRecentLogin,
  notConfigured,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code, [this.debugMessage]);

  final AuthErrorCode code;

  /// Solo para registros de desarrollo; nunca se muestra al usuario.
  final String? debugMessage;

  @override
  String toString() => 'AuthException($code)';
}
