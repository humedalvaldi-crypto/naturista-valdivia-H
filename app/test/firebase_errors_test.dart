import 'package:flutter_test/flutter_test.dart';
import 'package:naturista_valdivia/features/auth/data/firebase_auth_repository.dart';
import 'package:naturista_valdivia/features/auth/domain/auth_user.dart';

void main() {
  test('traduce los códigos de Firebase', () {
    const cases = {
      'invalid-credential': AuthErrorCode.invalidCredentials,
      'wrong-password': AuthErrorCode.invalidCredentials,
      'user-not-found': AuthErrorCode.invalidCredentials,
      'email-already-in-use': AuthErrorCode.emailInUse,
      'weak-password': AuthErrorCode.weakPassword,
      'invalid-email': AuthErrorCode.invalidEmail,
      'too-many-requests': AuthErrorCode.tooManyRequests,
      'network-request-failed': AuthErrorCode.network,
      'popup-closed-by-user': AuthErrorCode.cancelled,
      'account-exists-with-different-credential': AuthErrorCode.accountExistsWithDifferentCredential,
      'unauthorized-domain': AuthErrorCode.notConfigured,
      'algo-nuevo': AuthErrorCode.unknown,
    };
    cases.forEach((code, expected) => expect(FirebaseAuthRepository.mapFirebaseCode(code), expected, reason: code));
  });

  test('las cuentas de Google no piden verificar el correo', () {
    const google = AuthUser(uid: 'a', providers: ['google.com']);
    const password = AuthUser(uid: 'b', providers: ['password']);
    expect(google.needsEmailVerification, isFalse);
    expect(password.needsEmailVerification, isTrue);
  });

  test('iniciales del avatar', () {
    expect(const AuthUser(uid: 'a', displayName: 'Ana Pérez').initials, 'AP');
    expect(const AuthUser(uid: 'a', email: 'eva@example.test').initials, 'EE');
    expect(const AuthUser(uid: 'a').initials, '?');
  });
}
