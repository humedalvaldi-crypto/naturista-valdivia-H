import 'package:flutter/widgets.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';

/// Si la cuenta aceptó la versión vigente de los términos y confirmó la edad
/// mínima. El servidor lo exige igual (responde 428); esto solo lleva a la
/// persona a la pantalla de aceptación en vez de mostrar errores.
class ConsentController extends ChangeNotifier {
  ConsentController(this._auth, this._api) {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final AuthController _auth;
  final ApiClient _api;

  String? _uid;
  String? _requiredVersion;
  int _minAge = 14;
  bool _needsConsent = false;

  bool get needsConsent => _needsConsent;
  String? get requiredVersion => _requiredVersion;
  int get minAge => _minAge;

  void _onAuth() {
    final uid = _auth.user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _needsConsent = false;
    _requiredVersion = null;
    notifyListeners();
    if (uid != null) refresh();
  }

  /// Consulta el estado en `GET /me` (sin servidor, no hay nada que aceptar).
  Future<void> refresh() async {
    if (!_api.isConfigured || _auth.user == null) return;
    try {
      final data = (await _api.get('/me'))['data'];
      final consent = data is Map ? data['consent'] : null;
      if (consent is! Map) return;
      _requiredVersion = consent['requiredVersion'] as String?;
      _minAge = (consent['minAge'] as num?)?.toInt() ?? 14;
      _needsConsent = consent['upToDate'] == false;
      notifyListeners();
    } catch (_) {
      // Sin conexión: el servidor seguirá exigiendo el consentimiento al escribir.
    }
  }

  /// Envía la aceptación (las dos casillas deben estar marcadas en la pantalla).
  Future<void> accept() async {
    final version = _requiredVersion;
    if (version == null) return;
    await _api.post('/me/consent', {'version': version, 'termsAccepted': true, 'ageConfirmed': true});
    _needsConsent = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}

class ConsentScope extends InheritedNotifier<ConsentController> {
  const ConsentScope({super.key, required ConsentController controller, required super.child}) : super(notifier: controller);

  static ConsentController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsentScope>()!.notifier!;
}
