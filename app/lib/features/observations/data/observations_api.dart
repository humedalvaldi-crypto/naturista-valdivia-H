import '../../../core/network/api_client.dart';
import '../../social/domain/models.dart';
import '../domain/observation_models.dart';

/// Acceso a especies, observaciones y lugares. Los permisos y la ocultación
/// de ubicaciones sensibles se aplican en el servidor.
class ObservationsApi {
  ObservationsApi(this._api);

  final ApiClient _api;

  bool get isConfigured => _api.isConfigured;
  bool get hasSession => _api.hasSession;
  ApiClient get client => _api;

  /// Máximo de puntos que se piden para el mapa.
  static const mapLimit = 500;

  String _q(Map<String, String?> params) {
    final entries = params.entries.where((e) => e.value != null && e.value!.isNotEmpty);
    if (entries.isEmpty) return '';
    return '?${entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}').join('&')}';
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> body) =>
      (body['data'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  Future<List<Species>> species({String? query, String? group}) async =>
      _list(await _api.get('/species${_q({'q': query, 'group': group})}', authenticated: false)).map(Species.fromJson).toList();

  Future<List<Observation>> inBounds(GeoBounds bounds, {String? group, String? user}) async {
    final body = await _api.get(
      '/observations${_q({'bbox': bounds.query, 'group': group, 'user': user, 'limit': '$mapLimit'})}',
      authenticated: _api.hasSession,
    );
    return _list(body).map(Observation.fromJson).toList();
  }

  Future<ResultPage<Observation>> list({String? user, String? cursor}) async {
    final body = await _api.get('/observations${_q({'user': user, 'cursor': cursor, 'limit': '20'})}', authenticated: _api.hasSession);
    return ResultPage(_list(body).map(Observation.fromJson).toList(), body['nextCursor'] as String?);
  }

  Future<Observation> get(String id) async =>
      Observation.fromJson((await _api.get('/observations/$id', authenticated: _api.hasSession))['data'] as Map<String, dynamic>);

  Future<Observation> create(Map<String, Object?> fields) async =>
      Observation.fromJson((await _api.post('/observations', fields))['data'] as Map<String, dynamic>);

  Future<Observation> update(String id, Map<String, Object?> fields) async =>
      Observation.fromJson((await _api.patch('/observations/$id', fields))['data'] as Map<String, dynamic>);

  Future<void> delete(String id) => _api.delete('/observations/$id');

  Future<List<Place>> places(GeoBounds bounds) async =>
      _list(await _api.get('/places${_q({'bbox': bounds.query})}', authenticated: false)).map(Place.fromJson).toList();

  Future<String> uploadPhoto(List<int> bytes, String contentType) async {
    final res = await _api.upload('/media?purpose=observation-photo', bytes, contentType);
    return (res['data'] as Map<String, dynamic>)['id'] as String;
  }
}
