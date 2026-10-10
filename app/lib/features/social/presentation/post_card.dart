import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../data/social_api.dart';
import '../domain/models.dart';
import 'person_avatar.dart';

/// Tarjeta de publicación (lámina, sección 11 "Perfil y comunidad").
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.api,
    required this.onLike,
    required this.onOpen,
    this.onDelete,
  });

  final Post post;
  final SocialApi api;
  final VoidCallback? onLike;
  final VoidCallback onOpen;

  /// Solo se pasa cuando quien mira es el autor.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final image = api.url(post.image);
    final onDelete = this.onDelete;

    return Card(
      key: Key('post-${post.id}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: PersonAvatar(person: post.author, imageUrl: api.url(post.author.photo)),
            title: Text(post.author.name, style: theme.textTheme.titleSmall),
            subtitle: Text(
              [
                formatWhen(context, post.createdAt),
                if (post.locationName != null) post.locationName!,
                if (post.visibility == 'followers') l10n.visibilityFollowers,
              ].join(' · '),
            ),
            trailing: onDelete == null
                ? null
                : PopupMenuButton<String>(
                    onSelected: (_) => onDelete(),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'delete', child: Text(l10n.deletePost)),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(post.body, style: theme.textTheme.bodyLarge),
          ),
          if (image != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => const ColoredBox(color: Colors.black12),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  key: Key('like-${post.id}'),
                  onPressed: onLike,
                  icon: Icon(
                    post.likedByMe ? Icons.favorite : Icons.favorite_border,
                    color: post.likedByMe ? theme.colorScheme.error : null,
                  ),
                  label: Text(l10n.likeCount(post.likeCount)),
                ),
                TextButton.icon(
                  key: Key('comments-${post.id}'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text(l10n.commentCount(post.commentCount)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
