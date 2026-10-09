import 'dart:async';

import 'package:naturista_valdivia/features/auth/data/auth_repository.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

/// Autenticación en memoria para pruebas. Acepta la contraseña registrada
/// en [accounts]; Google inicia sesión con [googleUser] o lanza [googleError].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? initialUser, Map<String, String>? accounts})
      : _user = initialUser,
        accounts = accounts ?? {'ana@example.test': 'secreta123'};

  final Map<String, String> accounts;
  AuthUser googleUser = const AuthUser(
    uid: 'uid-google',
    email: 'gabi@example.test',
    displayName: 'Gabi Google',
    emailVerified: true,
    providers: ['google.com'],
  );
  AuthException? googleError;

  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  int tokenRequests = 0;
  int forcedRefreshes = 0;
  int verificationEmails = 0;
  final List<String> resetEmails = [];

  void _set(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Stream<AuthUser?> userChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> signInWithGoogle() async {
    final error = googleError;
    if (error != null) throw error;
    _set(googleUser);
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    if (accounts[email.trim()] != password) {
      throw const AuthException(AuthErrorCode.invalidCredentials);
    }
    _set(AuthUser(
      uid: 'uid-${email.trim()}',
      email: email.trim(),
      displayName: 'Ana Pérez',
      emailVerified: true,
      providers: const ['password'],
    ));
  }

  @override
  Future<void> registerWithEmail({required String name, required String email, required String password}) async {
    if (accounts.containsKey(email.trim())) throw const AuthException(AuthErrorCode.emailInUse);
    accounts[email.trim()] = password;
    verificationEmails++;
    _set(AuthUser(uid: 'uid-new', email: email.trim(), displayName: name.trim(), providers: const ['password']));
  }

  @override
  Future<void> sendPasswordReset(String email) async => resetEmails.add(email);

  @override
  Future<void> sendEmailVerification() async => verificationEmails++;

  @override
  Future<void> reloadUser() async {}

  /// Simula que el usuario abrió el enlace de verificación.
  void markEmailVerified() {
    final u = _user;
    if (u == null) return;
    _set(AuthUser(
      uid: u.uid,
      email: u.email,
      displayName: u.displayName,
      emailVerified: true,
      providers: u.providers,
    ));
  }

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (_user == null) return null;
    tokenRequests++;
    if (forceRefresh) forcedRefreshes++;
    return forceRefresh ? 'token-fresh' : 'token-cached';
  }
}
