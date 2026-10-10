import 'dart:convert';
import 'dart:typed_data';

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

  /// Hay sesión: las lecturas públicas envían el token para personalizar
  /// la respuesta (p. ej. "me gusta" propios).
  bool get hasSession => _auth.currentUser != null;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) =>
      _send('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> patch(String path, Map<String, Object?> body) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> post(String path, [Map<String, Object?> body = const {}]) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path) => _send('PUT', path);

  Future<Map<String, dynamic>> putJson(String path, Map<String, Object?> body) => _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  /// URL absoluta para rutas de archivos devueltas por la API (`/api/v1/media/...`).
  String? absolute(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  /// Sube bytes tal cual (archivos) con su tipo real.
  Future<Map<String, dynamic>> upload(String path, List<int> bytes, String contentType) =>
      _send('POST', path, rawBody: bytes, rawContentType: contentType);

  /// Descarga un archivo de la API (p. ej. una foto privada) con la sesión.
  /// `path` puede ser absoluto o relativo a `baseUrl` (`/api/v1/media/...`).
  Future<Uint8List> getBytes(String path) async {
    final relative = path.startsWith(baseUrl) ? path.substring(baseUrl.length) : path;
    final apiPath = relative.startsWith('/api/v1') ? relative.substring('/api/v1'.length) : relative;
    final response = await _raw('GET', apiPath, authenticated: hasSession);
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
    throw ApiException(response.statusCode, 'http_error', 'No se pudo descargar el archivo.');
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Map<String, Object?>? body,
    List<int>? rawBody,
    String? rawContentType,
    bool authenticated = true,
  }) async {
    if (!isConfigured) {
      throw const ApiException(0, 'not_configured', 'El servidor todavía no está conectado.');
    }

    Future<http.Response> attempt({required bool forceRefresh}) async {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json';
      if (rawBody != null) headers['Content-Type'] = rawContentType ?? 'application/octet-stream';
      if (authenticated) {
        final token = await _auth.idToken(forceRefresh: forceRefresh);
        if (token == null) throw const ApiException(401, 'unauthorized', 'Inicia sesión para continuar.');
        headers['Authorization'] = 'Bearer $token';
      }
      final request = http.Request(method, _uri(path))..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      if (rawBody != null) request.bodyBytes = rawBody;
      return http.Response.fromStream(await _http.send(request));
    }

    try {
      final response = await attempt(forceRefresh: false);
      if (response.statusCode == 401 && authenticated) {
        return await attempt(forceRefresh: true);
      }
      return response;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(0, 'network_error', 'No se pudo conectar con el servidor.');
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    List<int>? rawBody,
    String? rawContentType,
    bool authenticated = true,
  }) async {
    final response = await _raw(
      method,
      path,
      body: body,
      rawBody: rawBody,
      rawContentType: rawContentType,
      authenticated: authenticated,
    );

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
