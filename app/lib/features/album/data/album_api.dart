import '../../../core/network/api_client.dart';
import '../domain/album_models.dart';

class AlbumApi {
  AlbumApi(this._api);

  final ApiClient _api;

  bool get isConfigured => _api.isConfigured;

  Future<AlbumData> album(String userId) async => AlbumData.fromJson(
        (await _api.get('/users/$userId/album', authenticated: _api.hasSession))['data'] as Map<String, dynamic>,
      );
}
