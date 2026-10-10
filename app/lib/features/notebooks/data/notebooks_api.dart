import '../../../core/network/api_client.dart';
import '../domain/notebook_models.dart';

/// Resultado de guardar: nueva versión o conflicto (otro dispositivo cambió la página).
sealed class SaveResult {
  const SaveResult();
}

class Saved extends SaveResult {
  const Saved(this.version);
  final int version;
}

class Conflict extends SaveResult {
  const Conflict();
}

/// Contrato que usa el editor (las pruebas pueden sustituirlo).
abstract interface class PageStore {
  Future<PageDocument> load(String pageId);
  Future<SaveResult> save(PageDocument doc, List<PageElement> elements);
}

class NotebooksApi implements PageStore {
  NotebooksApi(this._api);

  final ApiClient _api;

  bool get isConfigured => _api.isConfigured;
  ApiClient get client => _api;
  String? url(String? path) => _api.absolute(path);

  List<Map<String, dynamic>> _list(Map<String, dynamic> body) =>
      (body['data'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  Future<List<Notebook>> mine() async => _list(await _api.get('/notebooks')).map(Notebook.fromJson).toList();

  Future<Notebook> create({required String title, String? description, String? color}) async => Notebook.fromJson(
        (await _api.post('/notebooks', {
          'title': title,
          if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
          'color': ?color,
        }))['data'] as Map<String, dynamic>,
      );

  Future<Notebook> get(String id) async =>
      Notebook.fromJson((await _api.get('/notebooks/$id', authenticated: _api.hasSession))['data'] as Map<String, dynamic>);

  Future<Notebook> update(String id, Map<String, Object?> fields) async =>
      Notebook.fromJson((await _api.patch('/notebooks/$id', fields))['data'] as Map<String, dynamic>);

  Future<void> delete(String id) => _api.delete('/notebooks/$id');

  /// Da o quita "me gusta". Devuelve (total, míoAhora).
  Future<(int, bool)> setLiked(String id, bool liked) async {
    final body = liked ? await _api.put('/notebooks/$id/like') : await _api.delete('/notebooks/$id/like');
    final data = body['data'] as Map<String, dynamic>;
    return ((data['likeCount'] as num).toInt(), data['likedByMe'] as bool);
  }

  /// Cuadernos eliminados en los últimos 30 días.
  Future<List<Notebook>> trash() async => _list(await _api.get('/notebooks/trash')).map(Notebook.fromJson).toList();

  Future<Notebook> restore(String id) async =>
      Notebook.fromJson((await _api.post('/notebooks/$id/restore'))['data'] as Map<String, dynamic>);

  Future<Notebook> duplicate(String id) async =>
      Notebook.fromJson((await _api.post('/notebooks/$id/duplicate'))['data'] as Map<String, dynamic>);

  Future<List<PageInfo>> pages(String notebookId) async =>
      _list(await _api.get('/notebooks/$notebookId/pages', authenticated: _api.hasSession)).map(PageInfo.fromJson).toList();

  Future<PageInfo> addPage(String notebookId) async =>
      PageInfo.fromJson((await _api.post('/notebooks/$notebookId/pages'))['data'] as Map<String, dynamic>);

  Future<List<PageInfo>> reorder(String notebookId, List<String> pageIds) async => _list(
        await _api.putJson('/notebooks/$notebookId/page-order', {'pageIds': pageIds}),
      ).map(PageInfo.fromJson).toList();

  Future<PageInfo> duplicatePage(String pageId) async =>
      PageInfo.fromJson((await _api.post('/pages/$pageId/duplicate'))['data'] as Map<String, dynamic>);

  Future<void> deletePage(String pageId) => _api.delete('/pages/$pageId');

  @override
  Future<PageDocument> load(String pageId) async =>
      PageDocument.fromJson((await _api.get('/pages/$pageId', authenticated: _api.hasSession))['data'] as Map<String, dynamic>);

  @override
  Future<SaveResult> save(PageDocument doc, List<PageElement> elements) async {
    try {
      final res = await _api.putJson('/pages/${doc.id}', {
        'version': doc.version,
        'paper': doc.paper,
        'elements': [for (final e in elements) e.toJson()],
      });
      return Saved(((res['data'] as Map<String, dynamic>)['version'] as num).toInt());
    } on ApiException catch (e) {
      if (e.statusCode == 409) return const Conflict();
      rethrow;
    }
  }

  Future<String> uploadPhoto(List<int> bytes, String contentType) async {
    final res = await _api.upload('/media?purpose=notebook-photo', bytes, contentType);
    return (res['data'] as Map<String, dynamic>)['id'] as String;
  }
}
