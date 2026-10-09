/// Configuración inyectada en compilación con `--dart-define`.
/// Nunca contiene secretos: todo lo que viaja en la app es público.
abstract final class AppConfig {
  /// URL base de la API (Cloudflare Worker), sin barra final. Vacía mientras
  /// la API no esté desplegada: la app lo indica y no intenta conectarse.
  /// Desarrollo local: `--dart-define=API_BASE_URL=http://localhost:8787`.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// `development`, `staging` o `production`.
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static bool get isProduction => environment == 'production';
}
