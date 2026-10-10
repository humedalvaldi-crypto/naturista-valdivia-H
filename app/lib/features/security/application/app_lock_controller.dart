import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../auth/application/auth_controller.dart';
import '../data/biometric_auth.dart';

/// Bloqueo local de la app con huella o rostro.
///
/// - Solo protege una sesión de Firebase ya iniciada: no crea cuentas ni
///   reemplaza el inicio de sesión.
/// - Se activa por cuenta (UID); al cerrar sesión o cambiar de cuenta se borra.
/// - Al desbloquear se renueva el token de Firebase: si la sesión fue revocada
///   o cambiaron las credenciales, se cierra sesión y se pide la cuenta.
/// - Tras [maxFailures] intentos fallidos o un bloqueo del sistema, exige la cuenta.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController(this._auth, {this.lockAfter = const Duration(minutes: 2)}) {
    _auth.addListener(_onAuth);
    WidgetsBinding.instance.addObserver(this);
    _onAuth();
  }

  static const maxFailures = 5;

  final AuthController _auth;
  final Duration lockAfter;

  bool _locked = false;
  bool _enabled = false;
  bool _busy = false;
  int _failures = 0;
  String? _uid;
  DateTime? _pausedAt;
  BiometricResult? _lastResult;

  /// La app está tapada por la pantalla de desbloqueo.
  bool get locked => _locked;

  /// El desbloqueo está activado para la cuenta actual.
  bool get enabled => _enabled;
  bool get busy => _busy;
  int get failures => _failures;
  BiometricResult? get lastResult => _lastResult;

  Future<void> _onAuth() async {
    final user = _auth.user;
    if (user?.uid == _uid) return;
    final previous = _uid;
    _uid = user?.uid;
    if (user == null) {
      // Cerrar sesión exige volver a entrar con la cuenta: se desactiva.
      if (previous != null) await BiometricStore.instance.disable();
      _set(locked: false, enabled: false);
      return;
    }
    final stored = await BiometricStore.instance.enabledUid();
    if (stored != null && stored != user.uid) {
      await BiometricStore.instance.disable(); // era de otra cuenta
      _set(locked: false, enabled: false);
      return;
    }
    final on = stored == user.uid;
    // Al abrir la app con una sesión guardada, se pide la huella.
    _set(locked: on && previous == null, enabled: on);
  }

  void _set({required bool locked, required bool enabled}) {
    _locked = locked;
    _enabled = enabled;
    if (!locked) _failures = 0;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (_enabled && !_locked && pausedAt != null && DateTime.now().difference(pausedAt) >= lockAfter) {
        _locked = true;
        notifyListeners();
      }
    }
  }

  /// Intenta desbloquear. Devuelve el resultado para mostrar un mensaje genérico.
  Future<BiometricResult> unlock(String reason) async {
    if (_busy) return BiometricResult.cancelled;
    _busy = true;
    notifyListeners();
    try {
      final result = await BiometricAuth.instance.authenticate(reason);
      _lastResult = result;
      if (result == BiometricResult.success) {
        // La huella abre la sesión local; Firebase confirma que sigue válida.
        if (!await _sessionStillValid()) {
          await usePrimaryAuth();
          return BiometricResult.unavailable;
        }
        _set(locked: false, enabled: true);
      } else if (result == BiometricResult.failed) {
        _failures++;
        if (_failures >= maxFailures) await usePrimaryAuth();
      } else if (result == BiometricResult.lockedOut) {
        await usePrimaryAuth();
      }
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Activa el desbloqueo: exige una huella válida y una sesión de Firebase vigente.
  Future<BiometricResult> enable(String reason) async {
    final user = _auth.user;
    if (user == null) return BiometricResult.unavailable;
    if (await BiometricAuth.instance.availability() != BiometricAvailability.available) {
      return BiometricResult.unavailable;
    }
    final result = await BiometricAuth.instance.authenticate(reason);
    if (result != BiometricResult.success) return result;
    if (!await _sessionStillValid()) return BiometricResult.unavailable;
    await BiometricStore.instance.enable(user.uid);
    _set(locked: false, enabled: true);
    return result;
  }

  Future<void> disable() async {
    await BiometricStore.instance.disable();
    _set(locked: false, enabled: false);
  }

  /// Alternativa segura: cerrar sesión y entrar con la cuenta (Google o correo).
  Future<void> usePrimaryAuth() async {
    await BiometricStore.instance.disable();
    _set(locked: false, enabled: false);
    await _auth.signOut();
  }

  Future<bool> _sessionStillValid() async {
    try {
      return await _auth.repository.idToken(forceRefresh: true) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}

class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({super.key, required AppLockController controller, required super.child}) : super(notifier: controller);

  static AppLockController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()!.notifier!;

  static AppLockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}
