import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/media/api_image.dart';
import '../../drawing_editor/presentation/painters.dart';
import '../../social/domain/models.dart';
import '../../social/presentation/person_avatar.dart';
import '../../social/presentation/post_actions.dart';
import '../domain/notebook_models.dart';

/// Ícono según la categoría (no se inventan fotos: sin portada se dibuja esto).
IconData categoryIcon(String? category) {
  final c = (category ?? '').toLowerCase();
  if (c.contains('ave')) return Icons.flutter_dash;
  if (c.contains('flor') || c.contains('flora') || c.contains('planta')) return Icons.local_florist_outlined;
  if (c.contains('hongo') || c.contains('funga')) return Icons.forest_outlined;
  if (c.contains('agua') || c.contains('humedal') || c.contains('río')) return Icons.water_outlined;
  if (c.contains('biodiv')) return Icons.eco_outlined;
  return Icons.menu_book_outlined;
}

/// Tarjeta de cuaderno de la comunidad: portada (o color y categoría), autora,
/// título, descripción, fecha, páginas y «me gusta» reales, abrir y compartir.
class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.notebook, required this.onOpen, required this.onLike, this.showOwner = true, this.liking = false});

  final Notebook notebook;
  final VoidCallback onOpen;
  final VoidCallback? onLike;
  final bool showOwner;
  final bool liking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final api = ApiScope.of(context);
    final nb = notebook;
    final color = parseHex(nb.color);
    final owner = nb.owner;
    final cover = nb.cover;

    final coverArea = SizedBox(
      height: 132,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            ApiImage(api: api, path: cover)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                ),
              ),
              child: Center(child: Icon(categoryIcon(nb.category), size: 48, color: Colors.white.withValues(alpha: 0.75))),
            ),
          if (nb.category != null)
            Positioned(
              left: 12,
              bottom: 10,
              child: _Badge(text: nb.category!.toUpperCase(), light: true),
            ),
          Positioned(
            right: 12,
            bottom: 10,
            child: _Badge(text: l10n.pagesCount(nb.pageCount), icon: Icons.description_outlined),
          ),
          if (nb.visibility != 'public')
            Positioned(right: 12, top: 10, child: _Badge(text: l10n.visibilityPrivate, icon: Icons.lock_outline)),
        ],
      ),
    );

    return Card(
      key: Key('nb-card-${nb.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            coverArea,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showOwner && owner != null)
                    InkWell(
                      key: Key('nb-owner-${nb.id}'),
                      onTap: () => context.push('/people/${owner.id}'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            PersonAvatar(
                              person: Person(id: owner.id, name: owner.name, username: owner.username, photo: owner.photo),
                              imageUrl: api.absolute(owner.photo),
                              radius: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(owner.name, style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  Text(nb.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (nb.description != null && nb.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(nb.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l10n.notebookUpdated(formatWhen(context, nb.updatedAt)), style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    key: Key('nb-like-${nb.id}'),
                    onPressed: nb.visibility == 'public' && !liking ? onLike : null,
                    icon: Icon(nb.likedByMe ? Icons.favorite : Icons.favorite_border, color: nb.likedByMe ? theme.colorScheme.error : null),
                    label: Text(l10n.likeCount(nb.likeCount)),
                  ),
                  if (nb.visibility == 'public')
                    TextButton.icon(
                      key: Key('nb-share-${nb.id}'),
                      onPressed: () => shareLink(context, notebookLink(nb.id), nb.title),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(l10n.sharePost),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.icon, this.light = false});

  final String text;
  final IconData? icon;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final bg = light ? const Color(0xFFF3EFE2) : Colors.black.withValues(alpha: 0.55);
    final fg = light ? const Color(0xFF1C3320) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}
