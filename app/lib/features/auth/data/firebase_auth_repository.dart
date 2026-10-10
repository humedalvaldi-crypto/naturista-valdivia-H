import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../domain/auth_user.dart';
import 'auth_repository.dart';

/// Implementación con Firebase Authentication. Firebase guarda la sesión
/// (en el navegador o en el dispositivo) y renueva el ID token solo.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final fb.FirebaseAuth _auth;

  static AuthUser? _map(fb.User? u) {
    if (u == null) return null;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      displayName: u.displayName,
      photoUrl: u.photoURL,
      emailVerified: u.emailVerified,
      providers: [for (final p in u.providerData) p.providerId],
      createdAt: u.metadata.creationTime,
      lastSignInAt: u.metadata.lastSignInTime,
    );
  }

  @override
  Stream<AuthUser?> userChanges() => _auth.userChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on fb.FirebaseAuthMultiFactorException catch (e) {
      throw AuthException(AuthErrorCode.multiFactorRequired, e.code);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseCode(e.code), e.code);
    }
  }

  /// Traduce códigos de Firebase a códigos propios (público para pruebas).
  static AuthErrorCode mapFirebaseCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return AuthErrorCode.invalidCredentials;
      case 'email-already-in-use':
        return AuthErrorCode.emailInUse;
      case 'weak-password':
      case 'password-does-not-meet-requirements':
        return AuthErrorCode.weakPassword;
      case 'invalid-email':
      case 'missing-email':
        return AuthErrorCode.invalidEmail;
      case 'user-disabled':
        return AuthErrorCode.userDisabled;
      case 'too-many-requests':
        return AuthErrorCode.tooManyRequests;
      case 'network-request-failed':
        return AuthErrorCode.network;
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-canceled':
      case 'web-context-cancelled':
      case 'canceled':
        return AuthErrorCode.cancelled;
      case 'account-exists-with-different-credential':
        return AuthErrorCode.accountExistsWithDifferentCredential;
      case 'requires-recent-login':
        return AuthErrorCode.requiresRecentLogin;
      case 'operation-not-allowed':
      case 'unauthorized-domain':
      case 'invalid-api-key':
      case 'app-not-authorized':
        return AuthErrorCode.notConfigured;
      default:
        return AuthErrorCode.unknown;
    }
  }

  @override
  Future<void> signInWithGoogle() => _guard(() async {
        final provider = fb.GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
        if (kIsWeb) {
          await _auth.signInWithPopup(provider);
        } else {
          await _auth.signInWithProvider(provider);
        }
      });

  @override
  Future<void> signInWithEmail({required String email, required String password}) => _guard(() async {
        await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      });

  @override
  Future<void> registerWithEmail({required String name, required String email, required String password}) =>
      _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        final user = cred.user;
        if (user == null) return;
        await user.updateDisplayName(name.trim());
        await user.sendEmailVerification();
        await user.reload();
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sendEmailVerification() => _guard(() async {
        await _auth.currentUser?.sendEmailVerification();
      });

  @override
  Future<void> reloadUser() => _guard(() async {
        await _auth.currentUser?.reload();
      });

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _guard(() => user.getIdToken(forceRefresh));
  }
}
