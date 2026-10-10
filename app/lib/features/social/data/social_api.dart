import '../../../core/network/api_client.dart';
import '../domain/models.dart';

/// Acceso a la API social. Todas las reglas de permisos viven en el servidor.
class SocialApi {
  SocialApi(this._api);

  final ApiClient _api;

  bool get isConfigured => _api.isConfigured;
  String? url(String? path) => _api.absolute(path);

  String _q(Map<String, String?> params) {
    final entries = params.entries.where((e) => e.value != null && e.value!.isNotEmpty);
    if (entries.isEmpty) return '';
    return '?${entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}').join('&')}';
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> body) =>
      (body['data'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  Future<ResultPage<Post>> feed({String scope = 'all', String? community, String? author, String? cursor}) async {
    final signedIn = scope != 'all';
    final body = await _api.get(
      '/posts${_q({'scope': community == null && author == null ? scope : null, 'community': community, 'author': author, 'cursor': cursor, 'limit': '20'})}',
      authenticated: signedIn || _api.hasSession,
    );
    return ResultPage(_list(body).map(Post.fromJson).toList(), body['nextCursor'] as String?);
  }

  Future<Post> createPost({
    required String body,
    String visibility = 'public',
    String? locationName,
    String? communitySlug,
    String? mediaAssetId,
  }) async {
    final res = await _api.post('/posts', {
      'body': body,
      'visibility': visibility,
      'mediaAssetId': ?mediaAssetId,
      if (locationName != null && locationName.trim().isNotEmpty) 'locationName': locationName.trim(),
      'communitySlug': ?communitySlug,
    });
    return Post.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Post> getPost(String id) async =>
      Post.fromJson((await _api.get('/posts/$id', authenticated: _api.hasSession))['data'] as Map<String, dynamic>);

  Future<Post> setLiked(String id, bool liked) async {
    final res = liked ? await _api.put('/posts/$id/like') : await _api.delete('/posts/$id/like');
    return Post.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String id) => _api.delete('/posts/$id');

  Future<ResultPage<Comment>> comments(String postId, {String? cursor}) async {
    final body = await _api.get('/posts/$postId/comments${_q({'cursor': cursor, 'limit': '50'})}', authenticated: _api.hasSession);
    return ResultPage(_list(body).map(Comment.fromJson).toList(), body['nextCursor'] as String?);
  }

  Future<Comment> addComment(String postId, String body) async {
    final res = await _api.post('/posts/$postId/comments', {'body': body});
    return Comment.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<List<Community>> communities({bool mine = false, String? query}) async {
    final body = await _api.get(
      '/communities${_q({'mine': mine ? '1' : null, 'q': query, 'limit': '50'})}',
      authenticated: mine || _api.hasSession,
    );
    return _list(body).map(Community.fromJson).toList();
  }

  Future<Community> setMembership(String slug, bool join) async {
    final res = join ? await _api.put('/communities/$slug/membership') : await _api.delete('/communities/$slug/membership');
    return Community.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Community> createCommunity({required String name, required String slug, String? description, String? wetland}) async {
    final res = await _api.post('/communities', {
      'name': name,
      'slug': slug,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (wetland != null && wetland.trim().isNotEmpty) 'wetland': wetland.trim(),
    });
    return Community.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<ResultPage<AppNotification>> notifications({String? cursor}) async {
    final body = await _api.get('/me/notifications${_q({'cursor': cursor})}');
    return ResultPage(_list(body).map(AppNotification.fromJson).toList(), body['nextCursor'] as String?);
  }

  Future<void> markAllNotificationsRead() => _api.post('/me/notifications/read');

  // ── Fotos ───────────────────────────────────────────────────────────────

  /// Sube una imagen y devuelve el ID del archivo. El servidor comprueba el
  /// tipo real y el tamaño.
  Future<String> uploadImage(List<int> bytes, String contentType, {String purpose = 'post-photo'}) async {
    final res = await _api.upload('/media?purpose=$purpose', bytes, contentType);
    return (res['data'] as Map<String, dynamic>)['id'] as String;
  }

  // ── Personas ────────────────────────────────────────────────────────────

  Future<PersonSummary> person(String userId) async =>
      PersonSummary.fromJson((await _api.get('/users/$userId', authenticated: _api.hasSession))['data'] as Map<String, dynamic>);

  Future<void> setFollowing(String userId, bool follow) async {
    if (follow) {
      await _api.put('/users/$userId/follow');
    } else {
      await _api.delete('/users/$userId/follow');
    }
  }

  Future<void> block(String userId) => _api.put('/users/$userId/block');

  Future<void> report({required String targetType, required String targetId, required String reason}) =>
      _api.post('/reports', {'targetType': targetType, 'targetId': targetId, 'reason': reason});

  // ── Mensajes ────────────────────────────────────────────────────────────

  Future<List<Conversation>> conversations() async => _list(await _api.get('/conversations')).map(Conversation.fromJson).toList();

  Future<String> openConversation(String userId) async =>
      ((await _api.post('/conversations', {'userId': userId}))['data'] as Map<String, dynamic>)['id'] as String;

  Future<ResultPage<ChatMessage>> messages(String conversationId, {String? cursor}) async {
    final body = await _api.get('/conversations/$conversationId/messages${_q({'cursor': cursor, 'limit': '50'})}');
    return ResultPage(_list(body).map(ChatMessage.fromJson).toList(), body['nextCursor'] as String?);
  }

  Future<ChatMessage> sendMessage(String conversationId, String body) async =>
      ChatMessage.fromJson((await _api.post('/conversations/$conversationId/messages', {'body': body}))['data'] as Map<String, dynamic>);

  Future<void> markConversationRead(String conversationId) => _api.post('/conversations/$conversationId/read');
}
