import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naturista_valdivia/core/network/api_client.dart';
import 'package:naturista_valdivia/features/auth/data/auth_repository.dart';

/// Servidor falso en memoria que imita las respuestas de la API social.
class FakeApiServer {
  final posts = <Map<String, dynamic>>[];
  final comments = <String, List<Map<String, dynamic>>>{};
  final communities = <Map<String, dynamic>>[];
  final notifications = <Map<String, dynamic>>[];
  final requests = <String>[];
  final requestBodies = <String, Map<String, dynamic>>{};
  final people = <String, Map<String, dynamic>>{};
  final conversations = <Map<String, dynamic>>[];
  final messages = <String, List<Map<String, dynamic>>>{};
  bool failNext = false;
  int _seq = 0;

  static Map<String, dynamic> person(String id, String name) => {'id': id, 'name': name, 'username': null, 'photo': null};

  Map<String, dynamic> addPost(String body, {String authorId = 'u-otra', String authorName = 'Otra Persona', int likes = 0}) {
    final p = {
      'id': 'p${_seq++}',
      'author': person(authorId, authorName),
      'body': body,
      'image': null,
      'community': null,
      'visibility': 'public',
      'locationName': null,
      'commentCount': 0,
      'likeCount': likes,
      'likedByMe': false,
      'bookmarkedByMe': false,
      'createdAt': DateTime.utc(2026, 10, 9, 12, _seq).toIso8601String(),
    };
    posts.insert(0, p);
    return p;
  }

  Map<String, dynamic> addPerson(String id, String name, {int followers = 0}) => people[id] = {
        'id': id,
        'name': name,
        'username': null,
        'profile': {'photo': null, 'bio': 'Observadora de aves'},
        'restricted': false,
        'counts': {'followers': followers, 'following': 0, 'posts': 0},
        'followedByMe': false,
        'isMe': false,
      };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  ApiClient client(AuthRepository auth) => ApiClient(
        baseUrl: 'https://api.example.test',
        auth: auth,
        client: MockClient((req) async {
          final path = req.url.path.replaceFirst('/api/v1', '');
          requests.add('${req.method} $path');
          if (failNext) {
            failNext = false;
            return _json({'error': {'code': 'internal_error', 'message': 'Error interno del servidor.'}}, 500);
          }
          if (req.method == 'POST' && path == '/media') {
            return _json({'data': {'id': 'm-${_seq++}', 'contentType': req.headers['content-type'], 'size': req.bodyBytes.length}}, 201);
          }
          final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
          requestBodies['${req.method} $path'] = body;
          final seg = path.split('/').where((s) => s.isNotEmpty).toList();

          if (req.method == 'GET' && path == '/me') return _json({'data': {}});
          if (seg.first == 'posts') {
            if (seg.length == 1 && req.method == 'GET') return _json({'data': posts, 'nextCursor': null});
            if (seg.length == 1 && req.method == 'POST') {
              final p = addPost(body['body'] as String, authorId: 'u1', authorName: 'Eva');
              if (body['mediaAssetId'] != null) p['image'] = '/api/v1/media/${body['mediaAssetId']}';
              return _json({'data': p}, 201);
            }
            final post = posts.firstWhere((p) => p['id'] == seg[1]);
            if (seg.length == 2) return _json({'data': post});
            if (seg[2] == 'like') {
              final liked = req.method == 'PUT';
              if (liked != post['likedByMe']) post['likeCount'] = (post['likeCount'] as int) + (liked ? 1 : -1);
              post['likedByMe'] = liked;
              return _json({'data': post});
            }
            if (seg[2] == 'comments' && req.method == 'GET') return _json({'data': comments[post['id']] ?? [], 'nextCursor': null});
            if (seg[2] == 'comments' && req.method == 'POST') {
              final c = {'id': 'c${_seq++}', 'postId': post['id'], 'author': person('u1', 'Eva'), 'body': body['body'], 'createdAt': DateTime.utc(2026).toIso8601String()};
              (comments[post['id'] as String] ??= []).add(c);
              post['commentCount'] = (post['commentCount'] as int) + 1;
              return _json({'data': c}, 201);
            }
          }
          if (seg.first == 'communities') {
            if (seg.length == 1 && req.method == 'GET') return _json({'data': communities, 'nextAfter': null});
            final c = communities.firstWhere((c) => c['slug'] == seg[1]);
            final join = req.method == 'PUT';
            c['memberCount'] = (c['memberCount'] as int) + (join ? 1 : -1);
            c['myRole'] = join ? 'member' : null;
            return _json({'data': c});
          }
          if (seg.first == 'users') {
            final u = people[seg[1]]!;
            if (seg.length == 2) return _json({'data': u});
            final follow = req.method == 'PUT';
            final counts = u['counts'] as Map<String, dynamic>;
            if (follow != u['followedByMe']) counts['followers'] = (counts['followers'] as int) + (follow ? 1 : -1);
            u['followedByMe'] = follow;
            return _json({'data': {'following': follow, 'counts': counts}});
          }
          if (seg.first == 'conversations') {
            if (seg.length == 1 && req.method == 'GET') return _json({'data': conversations});
            if (seg.length == 1 && req.method == 'POST') {
              final other = people[body['userId']]!;
              final existing = conversations.where((c) => (c['with'] as Map)['id'] == other['id']);
              if (existing.isNotEmpty) return _json({'data': {'id': existing.first['id']}}, 201);
              final c = {'id': 'conv-${_seq++}', 'with': person(other['id'] as String, other['name'] as String), 'lastMessage': null, 'lastMessageAt': null, 'unread': 0};
              conversations.add(c);
              return _json({'data': {'id': c['id']}}, 201);
            }
            final list = messages[seg[1]] ??= [];
            if (seg[2] == 'read') return http.Response('', 204);
            if (req.method == 'GET') return _json({'data': list, 'nextCursor': null});
            final m = {'id': 'msg-${_seq++}', 'body': body['body'], 'mine': true, 'createdAt': DateTime.utc(2026).toIso8601String()};
            list.insert(0, m);
            return _json({'data': m}, 201);
          }
          if (path == '/me/notifications' && req.method == 'GET') return _json({'data': notifications, 'nextCursor': null});
          if (path == '/me/notifications/read') {
            for (final n in notifications) {
              n['read'] = true;
            }
            return http.Response('', 204);
          }
          return _json({'error': {'code': 'not_found', 'message': 'Ruta no encontrada.'}}, 404);
        }),
      );
}
