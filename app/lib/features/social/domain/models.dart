// Modelos de la red social, tal como los devuelve la API `/api/v1`.

DateTime _date(Object? v) => DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

class Person {
  const Person({required this.id, required this.name, this.username, this.photo});

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Naturalista',
        username: j['username'] as String?,
        photo: j['photo'] as String?,
      );

  final String id;
  final String name;
  final String? username;
  final String? photo;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
  }
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.image,
    this.community,
    this.visibility = 'public',
    this.locationName,
    this.commentCount = 0,
    this.likeCount = 0,
    this.likedByMe = false,
    this.bookmarkedByMe = false,
  });

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        author: Person.fromJson(j['author'] as Map<String, dynamic>),
        body: j['body'] as String? ?? '',
        image: j['image'] as String?,
        community: j['community'] as String?,
        visibility: j['visibility'] as String? ?? 'public',
        locationName: j['locationName'] as String?,
        commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
        likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: j['likedByMe'] as bool? ?? false,
        bookmarkedByMe: j['bookmarkedByMe'] as bool? ?? false,
        createdAt: _date(j['createdAt']),
      );

  final String id;
  final Person author;
  final String body;
  final String? image;
  final String? community;
  final String visibility;
  final String? locationName;
  final int commentCount;
  final int likeCount;
  final bool likedByMe;
  final bool bookmarkedByMe;
  final DateTime createdAt;

  Post copyWith({int? likeCount, bool? likedByMe, int? commentCount, bool? bookmarkedByMe}) => Post(
        id: id,
        author: author,
        body: body,
        image: image,
        community: community,
        visibility: visibility,
        locationName: locationName,
        commentCount: commentCount ?? this.commentCount,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        bookmarkedByMe: bookmarkedByMe ?? this.bookmarkedByMe,
        createdAt: createdAt,
      );
}

class Comment {
  const Comment({required this.id, required this.author, required this.body, required this.createdAt});

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] as String,
        author: Person.fromJson(j['author'] as Map<String, dynamic>),
        body: j['body'] as String? ?? '',
        createdAt: _date(j['createdAt']),
      );

  final String id;
  final Person author;
  final String body;
  final DateTime createdAt;
}

class Community {
  const Community({
    required this.slug,
    required this.name,
    this.description,
    this.wetland,
    this.photo,
    this.memberCount = 0,
    this.myRole,
  });

  factory Community.fromJson(Map<String, dynamic> j) => Community(
        slug: j['slug'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        wetland: j['wetland'] as String?,
        photo: j['photo'] as String?,
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        myRole: j['myRole'] as String?,
      );

  final String slug;
  final String name;
  final String? description;
  final String? wetland;
  final String? photo;
  final int memberCount;
  final String? myRole;

  bool get isMember => myRole != null;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.read,
    this.actor,
    this.postId,
    this.conversationId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String,
        actor: j['actor'] == null ? null : Person.fromJson(j['actor'] as Map<String, dynamic>),
        postId: j['postId'] as String?,
        conversationId: j['conversationId'] as String?,
        createdAt: _date(j['createdAt']),
        read: j['read'] as bool? ?? false,
      );

  final String id;
  final String type;
  final Person? actor;
  final String? postId;
  final String? conversationId;
  final DateTime createdAt;
  final bool read;
}

/// Página de resultados con cursor para la siguiente.
class ResultPage<T> {
  const ResultPage(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

class PersonSummary {
  const PersonSummary({
    required this.person,
    required this.restricted,
    required this.followers,
    required this.following,
    required this.posts,
    required this.followedByMe,
    required this.isMe,
    this.bio,
    this.location,
  });

  factory PersonSummary.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>?;
    final counts = j['counts'] as Map<String, dynamic>? ?? const {};
    return PersonSummary(
      person: Person(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Naturalista',
        username: j['username'] as String?,
        photo: profile?['photo'] as String?,
      ),
      restricted: j['restricted'] as bool? ?? false,
      followers: (counts['followers'] as num?)?.toInt() ?? 0,
      following: (counts['following'] as num?)?.toInt() ?? 0,
      posts: (counts['posts'] as num?)?.toInt() ?? 0,
      followedByMe: j['followedByMe'] as bool? ?? false,
      isMe: j['isMe'] as bool? ?? false,
      bio: profile?['bio'] as String?,
      location: profile?['location'] as String?,
    );
  }

  final Person person;
  final bool restricted;
  final int followers;
  final int following;
  final int posts;
  final bool followedByMe;
  final bool isMe;
  final String? bio;
  final String? location;
}

class Conversation {
  const Conversation({required this.id, required this.withPerson, this.lastMessage, this.lastMessageAt, this.unread = 0});

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        withPerson: Person.fromJson(j['with'] as Map<String, dynamic>),
        lastMessage: j['lastMessage'] as String?,
        lastMessageAt: j['lastMessageAt'] == null ? null : _date(j['lastMessageAt']),
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final Person withPerson;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unread;
}

class ChatMessage {
  const ChatMessage({required this.id, required this.body, required this.mine, required this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        body: j['body'] as String? ?? '',
        mine: j['mine'] as bool? ?? false,
        createdAt: _date(j['createdAt']),
      );

  final String id;
  final String body;
  final bool mine;
  final DateTime createdAt;
}
