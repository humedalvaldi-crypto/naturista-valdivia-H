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
  final species = <Map<String, dynamic>>[
    {'id': 'sp-chucao', 'scientificName': 'Scelorchilus rubecula', 'commonNameEs': 'Chucao', 'commonNameEn': 'Chucao tapaculo', 'group': 'aves', 'conservationStatus': 'LC', 'sensitive': false, 'illustration': null},
    {'id': 'sp-huillin', 'scientificName': 'Lontra provocax', 'commonNameEs': 'Huillín', 'commonNameEn': 'Southern river otter', 'group': 'mamiferos', 'conservationStatus': 'EN', 'sensitive': true, 'illustration': null},
  ];
  final observations = <Map<String, dynamic>>[];
  Map<String, dynamic> album = {
    'species': [
      {'id': 'sp-chucao', 'scientificName': 'Scelorchilus rubecula', 'commonNameEs': 'Chucao', 'group': 'aves', 'conservationStatus': 'LC', 'sensitive': false, 'illustration': null, 'unlocked': true, 'via': 'observation', 'firstSeen': '2026-10-01T11:00:00Z', 'observationCount': 2},
      {'id': 'sp-huillin', 'scientificName': 'Lontra provocax', 'commonNameEs': 'Huillín', 'group': 'mamiferos', 'conservationStatus': 'EN', 'sensitive': true, 'illustration': null, 'unlocked': false, 'via': null, 'firstSeen': null, 'observationCount': 0},
    ],
    'stats': {'unlocked': 1, 'total': 2},
    'achievements': [
      {'id': 'first-observation', 'target': 1, 'progress': 1, 'unlocked': true},
      {'id': 'species-5', 'target': 5, 'progress': 1, 'unlocked': false},
    ],
  };
  final notebooks = <Map<String, dynamic>>[];

  /// Cuadernos en la papelera (con `deletedAt`).
  final trashed = <Map<String, dynamic>>[];

  /// Perfil propio (`/me/profile`).
  Map<String, dynamic> myProfile = {
    'userId': 'u1', 'username': 'eva', 'fullName': 'Eva', 'bio': null, 'location': null,
    'photo': null, 'banner': null, 'visibility': 'public',
  };
  bool accountDeleted = false;

  /// Preferencias del servidor (`/me/settings`).
  Map<String, dynamic> serverSettings = {
    'language': 'es',
    'theme': 'system',
    'notifications': {'follow': true, 'comment': true, 'reaction': true, 'message': true},
    'privacy': {'messages': 'everyone'},
  };
  Map<String, dynamic> stats = {
    'observations': 3, 'speciesObserved': 2, 'speciesUnlocked': 5, 'notebooks': 1, 'pages': 4, 'posts': 0,
    'followers': 7, 'following': 2, 'files': 3, 'storageBytes': 1572864, 'firstObservationAt': '2025-04-02T10:00:00Z',
  };
  final blocked = <Map<String, dynamic>>[];
  final feedback = <Map<String, dynamic>>[];
  final pages = <String, Map<String, dynamic>>{};
  bool failNext = false;

  /// Si es true, el próximo guardado de página responde 409 (otro dispositivo guardó antes).
  bool conflictNext = false;
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

  Map<String, dynamic> addNotebook(String title, {String ownerId = 'u1', List<Map<String, dynamic>> elements = const []}) {
    final nb = {
      'id': 'nb${_seq++}',
      'ownerId': ownerId,
      'title': title,
      'description': null,
      'color': '#2E5B2A',
      'visibility': 'private',
      'pageCount': 0,
      'updatedAt': DateTime.utc(2026, 10, 9).toIso8601String(),
    };
    notebooks.insert(0, nb);
    _addPage(nb, elements: elements);
    return nb;
  }

  Map<String, dynamic> _addPage(Map<String, dynamic> nb, {List<Map<String, dynamic>> elements = const [], int? at}) {
    final list = pagesOf(nb['id'] as String);
    final page = {
      'id': 'pg${_seq++}',
      'notebookId': nb['id'],
      'position': list.length,
      'version': 1,
      'title': null,
      'pageDate': null,
      'paper': 'plain',
      'editable': true,
      'elements': [...elements],
    };
    pages[page['id'] as String] = page;
    if (at != null) {
      for (final p in list.where((p) => (p['position'] as int) >= at)) {
        p['position'] = (p['position'] as int) + 1;
      }
      page['position'] = at;
    }
    nb['pageCount'] = list.length + 1;
    return page;
  }

  List<Map<String, dynamic>> pagesOf(String notebookId) =>
      pages.values.where((p) => p['notebookId'] == notebookId).toList()..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

  Map<String, dynamic> _pageInfo(Map<String, dynamic> p) => {...p}..remove('elements');

  Map<String, dynamic> addObservation({
    String? speciesId,
    String? taxonName,
    double lat = -39.86,
    double lng = -73.23,
    String ownerId = 'u-otra',
    String ownerName = 'Otra Persona',
    bool obscured = false,
    String? locationName,
  }) {
    final sp = speciesId == null ? null : species.firstWhere((s) => s['id'] == speciesId);
    final o = {
      'id': 'o${_seq++}',
      'owner': person(ownerId, ownerName),
      'species': sp,
      'taxonName': taxonName,
      'count': null,
      'observedAt': DateTime.utc(2026, 10, 1, 11).toIso8601String(),
      'latitude': lat,
      'longitude': lng,
      'accuracyM': obscured ? null : 10,
      'locationSource': obscured ? null : 'gps',
      'locationName': obscured ? null : locationName,
      'obscured': obscured,
      'notes': null,
      'photo': null,
      'visibility': 'public',
      'isMine': ownerId == 'u1',
      'createdAt': DateTime.utc(2026, 10, 1, 12, _seq).toIso8601String(),
    };
    observations.insert(0, o);
    return o;
  }

  http.Response? _observationsRoute(String method, List<String> seg, Map<String, dynamic> body, Map<String, String> query) {
    if (seg.first == 'species') {
      final q = (query['q'] ?? '').toLowerCase();
      return _json({
        'data': species.where((s) => q.isEmpty || '${s['commonNameEs']} ${s['scientificName']}'.toLowerCase().contains(q)).toList(),
      });
    }
    if (seg.first == 'places') return _json({'data': <Object>[]});
    if (seg.first != 'observations') return null;
    if (seg.length == 1 && method == 'GET') {
      final user = query['user'];
      final group = query['group'];
      final list = observations
          .where((o) => user == null || (o['owner'] as Map)['id'] == user)
          .where((o) => group == null || ((o['species'] as Map?)?['group'] ?? 'otros') == group)
          .toList();
      return _json({'data': list, 'nextCursor': null});
    }
    if (seg.length == 1 && method == 'POST') {
      final sp = body['speciesId'] == null ? null : species.firstWhere((s) => s['id'] == body['speciesId']);
      final o = addObservation(
        speciesId: sp?['id'] as String?,
        taxonName: body['taxonName'] as String?,
        lat: (body['latitude'] as num).toDouble(),
        lng: (body['longitude'] as num).toDouble(),
        ownerId: 'u1',
        ownerName: 'Eva',
        locationName: body['locationName'] as String?,
      );
      o['obscured'] = body['geoprivacy'] == 'obscured' || (sp?['sensitive'] as bool? ?? false);
      o['geoprivacy'] = body['geoprivacy'];
      o['locationSource'] = body['locationSource'];
      o['accuracyM'] = body['accuracyM'];
      o['visibility'] = body['visibility'];
      o['count'] = body['count'];
      o['notes'] = body['notes'];
      if (body['photoAssetId'] != null) o['photo'] = '/api/v1/media/${body['photoAssetId']}';
      return _json({'data': o}, 201);
    }
    final o = observations.where((x) => x['id'] == seg[1]).firstOrNull;
    if (o == null) return _json({'error': {'code': 'not_found', 'message': 'Observación no encontrada.'}}, 404);
    if (method == 'GET') return _json({'data': o});
    if (method == 'PATCH') {
      if (body.containsKey('notes')) o['notes'] = body['notes'];
      return _json({'data': o});
    }
    if (method == 'DELETE') {
      observations.remove(o);
      return http.Response('', 204);
    }
    return null;
  }

  http.Response? _notebooksRoute(String method, List<String> seg, Map<String, dynamic> body) {
    if (seg.first == 'notebooks') {
      if (seg.length == 2 && seg[1] == 'trash' && method == 'GET') return _json({'data': trashed});
      if (seg.length == 3 && seg[2] == 'restore' && method == 'POST') {
        final t = trashed.where((n) => n['id'] == seg[1]).firstOrNull;
        if (t == null) return _json({'error': {'code': 'not_found', 'message': 'Cuaderno no encontrado en la papelera.'}}, 404);
        trashed.remove(t);
        notebooks.add(t..remove('deletedAt'));
        return _json({'data': t});
      }
      if (seg.length == 1 && method == 'GET') return _json({'data': notebooks});
      if (seg.length == 1 && method == 'POST') {
        final nb = addNotebook(body['title'] as String);
        nb['color'] = body['color'] ?? nb['color'];
        nb['description'] = body['description'];
        return _json({'data': nb}, 201);
      }
      final nb = notebooks.where((n) => n['id'] == seg[1]).firstOrNull;
      if (nb == null) return null;
      if (seg.length == 2 && method == 'GET') return _json({'data': nb});
      if (seg.length == 3 && seg[2] == 'like') {
        final liked = method == 'PUT';
        if (liked != (nb['likedByMe'] ?? false)) nb['likeCount'] = ((nb['likeCount'] as int?) ?? 0) + (liked ? 1 : -1);
        nb['likedByMe'] = liked;
        return _json({'data': {'likeCount': nb['likeCount'], 'likedByMe': liked}});
      }
      if (seg.length == 2 && method == 'PATCH') {
        nb.addAll(body);
        return _json({'data': nb});
      }
      if (seg.length == 2 && method == 'DELETE') {
        notebooks.remove(nb);
        trashed.add({...nb, 'deletedAt': DateTime.now().toUtc().toIso8601String()});
        return http.Response('', 204);
      }
      if (seg[2] == 'pages' && method == 'GET') return _json({'data': [for (final p in pagesOf(nb['id'] as String)) _pageInfo(p)]});
      if (seg[2] == 'pages' && method == 'POST') return _json({'data': _pageInfo(_addPage(nb))}, 201);
      if (seg[2] == 'page-order') {
        final ids = (body['pageIds'] as List).cast<String>();
        for (var i = 0; i < ids.length; i++) {
          pages[ids[i]]!['position'] = i;
        }
        return _json({'data': [for (final p in pagesOf(nb['id'] as String)) _pageInfo(p)]});
      }
    }
    if (seg.first == 'pages') {
      final page = pages[seg[1]];
      if (page == null) return null;
      if (seg.length == 2 && method == 'GET') return _json({'data': page});
      if (seg.length == 2 && method == 'PUT') {
        if (conflictNext || body['version'] != page['version']) {
          conflictNext = false;
          return _json({'error': {'code': 'version_conflict', 'message': 'La página cambió.', 'details': {'currentVersion': page['version']}}}, 409);
        }
        page['elements'] = body['elements'];
        page['version'] = (page['version'] as int) + 1;
        return _json({'data': {'id': page['id'], 'version': page['version']}});
      }
      if (seg.length == 2 && method == 'DELETE') {
        pages.remove(page['id']);
        final nb = notebooks.firstWhere((n) => n['id'] == page['notebookId']);
        nb['pageCount'] = pagesOf(nb['id'] as String).length;
        return http.Response('', 204);
      }
      if (seg[2] == 'duplicate') {
        final nb = notebooks.firstWhere((n) => n['id'] == page['notebookId']);
        final copy = _addPage(nb, elements: (page['elements'] as List).cast<Map<String, dynamic>>(), at: (page['position'] as int) + 1);
        return _json({'data': _pageInfo(copy)}, 201);
      }
    }
    return null;
  }

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
          if (path == '/me/profile' && req.method == 'GET') return _json({'data': myProfile});
          if (path == '/me/settings' && req.method == 'GET') return _json({'data': serverSettings});
          if (path == '/me/settings' && req.method == 'PATCH') {
            for (final e in body.entries) {
              final current = serverSettings[e.key];
              serverSettings[e.key] = current is Map && e.value is Map ? {...current, ...(e.value as Map)} : e.value;
            }
            return _json({'data': serverSettings});
          }
          if (path == '/me/stats') return _json({'data': stats});
          if (path == '/me/blocked') return _json({'data': blocked});
          if (path == '/me/feedback' && req.method == 'POST') {
            feedback.add(body);
            return _json({'data': {'id': 'fb-${_seq++}'}}, 201);
          }
          if (seg.length == 3 && seg.first == 'users' && seg[2] == 'block' && req.method == 'DELETE') {
            blocked.removeWhere((p) => p['id'] == seg[1]);
            return http.Response('', 204);
          }
          if (path == '/me/profile' && req.method == 'PATCH') {
            for (final e in body.entries) {
              switch (e.key) {
                case 'photoAssetId':
                  myProfile['photo'] = e.value == null ? null : '/api/v1/media/${e.value}';
                case 'bannerAssetId':
                  myProfile['banner'] = e.value == null ? null : '/api/v1/media/${e.value}';
                default:
                  myProfile[e.key] = e.value;
              }
            }
            if (myProfile['username'] == 'tomado') {
              return _json({'error': {'code': 'username_taken', 'message': 'Ese nombre de usuario ya está en uso.'}}, 409);
            }
            return _json({'data': myProfile});
          }
          if (path == '/me/export' && req.method == 'GET') {
            return http.Response(jsonEncode({'format': 'naturista-valdivia/export/v1', 'account': {'id': 'u1'}}), 200,
                headers: {'content-type': 'application/json'});
          }
          if (path == '/me' && req.method == 'DELETE') {
            if (req.headers['X-Confirm-Delete'] != 'ELIMINAR' && req.headers['x-confirm-delete'] != 'ELIMINAR') {
              return _json({'error': {'code': 'bad_request', 'message': 'Falta confirmar.'}}, 400);
            }
            accountDeleted = true;
            return http.Response('', 204);
          }
          if (req.method == 'GET' && seg.first == 'media') {
            return http.Response.bytes(const [0xff, 0xd8, 0xff, 0xd9], 200, headers: {'content-type': 'image/jpeg'});
          }
          final observationResponse = _observationsRoute(req.method, seg, body, req.url.queryParameters);
          if (observationResponse != null) return observationResponse;
          final notebookResponse = _notebooksRoute(req.method, seg, body);
          if (notebookResponse != null) return notebookResponse;
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
          if (seg.first == 'users' && seg.length == 3 && seg[2] == 'album') {
            return _json({'data': album});
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
