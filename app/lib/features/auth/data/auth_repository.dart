import '../domain/auth_user.dart';

/// Contrato de autenticación. La implementación real usa Firebase
/// Authentication; las pruebas usan una implementación en memoria.
abstract interface class AuthRepository {
  /// Emite el usuario actual y cada cambio (inicio/cierre de sesión,
  /// verificación de correo, cambio de nombre).
  Stream<AuthUser?> userChanges();

  AuthUser? get currentUser;

  Future<void> signInWithGoogle();
  Future<void> signInWithEmail({required String email, required String password});

  /// Crea la cuenta, guarda el nombre y envía el correo de verificación.
  Future<void> registerWithEmail({required String name, required String email, required String password});

  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();

  /// Recarga el usuario desde el servidor (p. ej. tras verificar el correo).
  Future<void> reloadUser();

  Future<void> signOut();

  /// Firebase ID token para la API. `forceRefresh` obtiene uno nuevo aunque
  /// el actual no haya caducado. `null` si no hay sesión.
  Future<String?> idToken({bool forceRefresh = false});
}

/// Usada cuando Firebase no pudo inicializarse: todo falla con
/// [AuthErrorCode.notConfigured] y la UI lo explica, sin simular una sesión.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  Never _fail() => throw const AuthException(AuthErrorCode.notConfigured);

  @override
  Stream<AuthUser?> userChanges() => Stream.value(null);
  @override
  AuthUser? get currentUser => null;
  @override
  Future<void> signInWithGoogle() async => _fail();
  @override
  Future<void> signInWithEmail({required String email, required String password}) async => _fail();
  @override
  Future<void> registerWithEmail({required String name, required String email, required String password}) async =>
      _fail();
  @override
  Future<void> sendPasswordReset(String email) async => _fail();
  @override
  Future<void> sendEmailVerification() async => _fail();
  @override
  Future<void> reloadUser() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> idToken({bool forceRefresh = false}) async => null;
}
