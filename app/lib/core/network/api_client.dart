import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/auth/data/auth_repository.dart';

/// Error de la API con el código estable que devuelve el Worker.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

/// Cliente HTTP de la API `/api/v1`. Adjunta el Firebase ID token y, si la
/// API responde 401, pide un token nuevo y reintenta una sola vez.
class ApiClient {
  ApiClient({required this.baseUrl, required AuthRepository auth, http.Client? client})
      : _auth = auth,
        _http = client ?? http.Client();

  final String baseUrl;
  final AuthRepository _auth;
  final http.Client _http;

  bool get isConfigured => baseUrl.isNotEmpty;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) =>
      _send('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> patch(String path, Map<String, Object?> body) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    if (!isConfigured) {
      throw const ApiException(0, 'not_configured', 'El servidor todavía no está conectado.');
    }

    Future<http.Response> attempt({required bool forceRefresh}) async {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json';
      if (authenticated) {
        final token = await _auth.idToken(forceRefresh: forceRefresh);
        if (token == null) throw const ApiException(401, 'unauthorized', 'Inicia sesión para continuar.');
        headers['Authorization'] = 'Bearer $token';
      }
      final request = http.Request(method, _uri(path))..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      return http.Response.fromStream(await _http.send(request));
    }

    late http.Response response;
    try {
      response = await attempt(forceRefresh: false);
      if (response.statusCode == 401 && authenticated) {
        response = await attempt(forceRefresh: true);
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(0, 'network_error', 'No se pudo conectar con el servidor.');
    }

    final decoded = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw ApiException(
        response.statusCode,
        error['code'] as String? ?? 'http_error',
        error['message'] as String? ?? 'Error del servidor.',
      );
    }
    throw ApiException(response.statusCode, 'http_error', 'Error del servidor.');
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } catch (_) {
      return const {};
    }
  }

  void close() => _http.close();
}
