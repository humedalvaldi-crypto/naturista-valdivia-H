import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

enum AuthStatus {
  /// Restaurando la sesión guardada (se muestra el splash).
  unknown,
  signedOut,
  signedIn,
}

/// Estado de sesión de la app. El router lo escucha para proteger rutas.
class AuthController extends ChangeNotifier {
  AuthController(this._repository, {this.available = true}) {
    _subscription = _repository.userChanges().listen(_onUser, onError: (Object _) => _onUser(null));
  }

  final AuthRepository _repository;

  /// `false` si Firebase no se pudo configurar en este dispositivo.
  final bool available;

  late final StreamSubscription<AuthUser?> _subscription;

  AuthStatus _status = AuthStatus.unknown;
  AuthUser? _user;
  bool _busy = false;

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  bool get isSignedIn => _status == AuthStatus.signedIn;

  /// Hay una operación en curso (deshabilita botones para evitar dobles envíos).
  bool get busy => _busy;

  AuthRepository get repository => _repository;

  void _onUser(AuthUser? user) {
    _user = user;
    _status = user == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Lanzan [AuthException]; la pantalla decide qué mostrar.
  Future<void> signInWithGoogle() => _run(_repository.signInWithGoogle);

  Future<void> signInWithEmail(String email, String password) =>
      _run(() => _repository.signInWithEmail(email: email, password: password));

  Future<void> register({required String name, required String email, required String password}) =>
      _run(() => _repository.registerWithEmail(name: name, email: email, password: password));

  Future<void> sendPasswordReset(String email) => _run(() => _repository.sendPasswordReset(email));

  Future<void> sendEmailVerification() => _run(_repository.sendEmailVerification);

  Future<void> reloadUser() => _run(_repository.reloadUser);

  Future<void> signOut() => _run(_repository.signOut);

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Expone el [AuthController] al árbol de widgets.
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({super.key, required AuthController controller, required super.child})
      : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope no encontrado en el árbol de widgets.');
    return scope!.notifier!;
  }

  /// Sin suscribirse a cambios (para callbacks).
  static AuthController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthScope>()!.notifier!;
}
