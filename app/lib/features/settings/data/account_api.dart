import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../../observations/data/observations_api.dart';
import '../../observations/domain/observation_models.dart';

/// Perfil propio tal como lo guarda el servidor (`/api/v1/me/profile`).
class MyProfile {
  const MyProfile({
    this.username,
    this.fullName,
    this.bio,
    this.location,
    this.photo,
    this.banner,
    this.visibility = 'public',
  });

  factory MyProfile.fromJson(Map<String, dynamic>? j) => j == null
      ? const MyProfile()
      : MyProfile(
          username: j['username'] as String?,
          fullName: j['fullName'] as String?,
          bio: j['bio'] as String?,
          location: j['location'] as String?,
          photo: j['photo'] as String?,
          banner: j['banner'] as String?,
          visibility: j['visibility'] as String? ?? 'public',
        );

  final String? username;
  final String? fullName;
  final String? bio;
  final String? location;
  final String? photo;
  final String? banner;

  /// `public`, `followers` o `private`.
  final String visibility;
}

/// Preferencias guardadas en el servidor (afectan a otras personas o a avisos).
class ServerSettings {
  const ServerSettings({required this.notifications, required this.messagesFrom});

  factory ServerSettings.fromJson(Map<String, dynamic> j) => ServerSettings(
        notifications: {
          for (final k in notificationKinds) k: ((j['notifications'] as Map?)?[k] as bool?) ?? true,
        },
        messagesFrom: ((j['privacy'] as Map?)?['messages'] as String?) ?? 'everyone',
      );

  static const notificationKinds = ['follow', 'comment', 'reaction', 'message'];

  /// Tipo de aviso → activado.
  final Map<String, bool> notifications;

  /// `everyone`, `following` o `nobody`.
  final String messagesFrom;
}

/// Números propios (`/me/stats`).
class MyStats {
  const MyStats(this.raw);

  final Map<String, dynamic> raw;

  int operator [](String key) => (raw[key] as num?)?.toInt() ?? 0;

  DateTime? get firstObservationAt => DateTime.tryParse(raw['firstObservationAt'] as String? ?? '')?.toLocal();
}

/// Persona bloqueada.
class BlockedPerson {
  const BlockedPerson({required this.id, required this.name, this.username});

  factory BlockedPerson.fromJson(Map<String, dynamic> j) =>
      BlockedPerson(id: j['id'] as String, name: j['name'] as String? ?? '', username: j['username'] as String?);

  final String id;
  final String name;
  final String? username;
}

/// Acciones sobre la cuenta propia: perfil, copia de los datos y eliminación.
class AccountApi {
  AccountApi(this._api);

  final ApiClient _api;

  ApiClient get client => _api;

  Future<MyProfile> profile() async => MyProfile.fromJson((await _api.get('/me/profile'))['data'] as Map<String, dynamic>?);

  /// Solo se envían los campos indicados.
  Future<MyProfile> updateProfile(Map<String, Object?> fields) async =>
      MyProfile.fromJson((await _api.patch('/me/profile', fields))['data'] as Map<String, dynamic>?);

  /// Sube una imagen de perfil (`profile-photo`) o portada (`profile-banner`) y devuelve su id.
  Future<String> uploadImage(String purpose, List<int> bytes, String contentType) async {
    final res = await _api.upload('/media?purpose=$purpose', bytes, contentType);
    return (res['data'] as Map<String, dynamic>)['id'] as String;
  }

  Future<ServerSettings> serverSettings() async =>
      ServerSettings.fromJson((await _api.get('/me/settings'))['data'] as Map<String, dynamic>);

  Future<ServerSettings> updateServerSettings(Map<String, Object?> fields) async =>
      ServerSettings.fromJson((await _api.patch('/me/settings', fields))['data'] as Map<String, dynamic>);

  Future<MyStats> stats() async => MyStats((await _api.get('/me/stats'))['data'] as Map<String, dynamic>);

  Future<List<BlockedPerson>> blocked() async => [
        for (final j in ((await _api.get('/me/blocked'))['data'] as List).cast<Map<String, dynamic>>()) BlockedPerson.fromJson(j),
      ];

  Future<void> unblock(String userId) => _api.delete('/users/$userId/block');

  Future<void> sendFeedback({required String kind, required String message, String? appVersion, String? platform}) =>
      _api.post('/me/feedback', {
        'kind': kind,
        'message': message,
        'appVersion': ?appVersion,
        'platform': ?platform,
      });

  /// Copia completa de los datos propios (JSON).
  Future<Uint8List> exportAll() => _api.getBytes('/me/export');

  /// Elimina la cuenta en el servidor de Naturista Valdivia.
  Future<void> deleteAccount() => _api.delete('/me', headers: const {'X-Confirm-Delete': 'ELIMINAR'});

  /// Todas las observaciones propias en CSV (UTF-8 con BOM para que Excel respete los acentos).
  Future<Uint8List> observationsCsv(String uid) async {
    final observations = ObservationsApi(_api);
    final rows = <Observation>[];
    String? cursor;
    var pages = 0;
    do {
      final page = await observations.list(user: uid, cursor: cursor);
      rows.addAll(page.items);
      cursor = page.nextCursor;
      pages++;
    } while (cursor != null && pages < 500);
    return encodeObservationsCsv(rows);
  }
}

/// CSV con una fila por observación. Público para probarlo sin red.
Uint8List encodeObservationsCsv(List<Observation> rows) {
  String cell(Object? v) {
    final text = v?.toString() ?? '';
    // Evita que una hoja de cálculo interprete el texto como fórmula.
    final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(text) ? "'$text" : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final buffer = StringBuffer()
    ..writeln([
      'id', 'fecha_utc', 'nombre_cientifico', 'nombre_comun', 'nombre_libre', 'cantidad',
      'latitud', 'longitud', 'precision_m', 'lugar', 'ubicacion_oculta', 'visibilidad', 'notas',
    ].map(cell).join(','));
  for (final o in rows) {
    buffer.writeln([
      o.id,
      o.observedAt.toUtc().toIso8601String(),
      o.species?.scientificName,
      o.species?.commonNameEs,
      o.taxonName,
      o.count,
      o.latitude,
      o.longitude,
      o.accuracyM,
      o.locationName,
      o.geoprivacy == 'obscured' ? 'si' : 'no',
      o.visibility,
      o.notes,
    ].map(cell).join(','));
  }
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(buffer.toString())]);
}
