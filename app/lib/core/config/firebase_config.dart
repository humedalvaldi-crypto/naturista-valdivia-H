import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuración del proyecto Firebase `humedalvaldivia-c7d08`.
///
/// Estos valores NO son secretos: Firebase los entrega para incluirlos en la
/// app y cualquiera puede verlos en el código de una web. La seguridad depende
/// de los dominios autorizados en Firebase Authentication y de la API, que
/// verifica cada token. Se pueden reemplazar en compilación con
/// `--dart-define=FIREBASE_API_KEY=...` (p. ej. para un proyecto de pruebas).
abstract final class FirebaseConfig {
  static const _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyAeqH2JyxSpEWeob24Xk3w9bnaJ6wLLkrw',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'humedalvaldivia-c7d08');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '207771391405');
  static const _authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'humedalvaldivia-c7d08.firebaseapp.com',
  );
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'humedalvaldivia-c7d08.firebasestorage.app',
  );
  static const _webAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:207771391405:web:362c86c59cc72e05fabd24',
  );

  /// App Android registrada en Firebase. OJO: está registrada con el paquete
  /// `App_val.nat`, distinto del de esta app. Ver docs/architecture.md.
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
    defaultValue: '1:207771391405:android:953062d722c16716fabd24',
  );

  static FirebaseOptions get currentPlatform => FirebaseOptions(
        apiKey: _apiKey,
        appId: kIsWeb || defaultTargetPlatform != TargetPlatform.android ? _webAppId : _androidAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        authDomain: _authDomain,
        storageBucket: _storageBucket,
      );
}
