import { Hono } from 'hono';
import { CommunitiesRepository } from '../repositories/communities';
import { MediaRepository } from '../repositories/media';
import { NotificationsRepository } from '../repositories/notifications';
import { PostsRepository, type CommentRow, type FeedScope, type PostRow } from '../repositories/posts';
import { UsersRepository } from '../repositories/users';
import { mediaPath, parseBody, personDto } from '../services/dto';
import { badRequest, notFound, unauthorized } from '../services/http-error';
import { decodeCursor, encodeCursor, paginate, parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { createCommentSchema, createPostSchema, updatePostSchema } from '../validators/social';

export const postDto = (p: PostRow) => ({
  id: p.id,
  author: personDto({
    id: p.author_id,
    username: p.author_username,
    full_name: p.author_full_name,
    display_name: p.author_display_name,
    photo_asset_id: p.author_photo_asset_id,
  }),
  body: p.body,
  image: mediaPath(p.media_asset_id),
  community: p.community_slug,
  visibility: p.visibility,
  locationName: p.location_name,
  commentCount: p.comment_count,
  likeCount: p.reaction_count,
  likedByMe: p.liked_by_me === 1,
  bookmarkedByMe: p.bookmarked_by_me === 1,
  createdAt: p.created_at,
  editedAt: p.edited_at ?? null,
});

const commentDto = (c: CommentRow) => ({
  id: c.id,
  postId: c.post_id,
  author: personDto({
    id: c.author_id,
    username: c.author_username,
    full_name: c.author_full_name,
    display_name: c.author_display_name,
    photo_asset_id: c.author_photo_asset_id,
  }),
  body: c.body,
  createdAt: c.created_at,
});

/** Identidad: obligatoria (`user`) u opcional (`maybeUser`). */
const viewerOf = (c: { get: (k: 'maybeUser' | 'user') => { uid: string } | undefined }) => c.get('user')?.uid ?? c.get('maybeUser')?.uid ?? null;

/**
 * /api/v1/posts
 * GET    /?scope=all|following|bookmarks&author=<uid>&community=<slug>&limit=&cursor=
 * POST   /                      crear (sesión)
 * GET    /:id                   ver
 * PATCH  /:id                   editar texto, lugar o visibilidad (autor)
 * DELETE /:id                   borrar (autor)
 * PUT|DELETE /:id/like          me gusta
 * PUT|DELETE /:id/bookmark      guardar
 * GET    /:id/comments          comentarios (cronológico)
 * POST   /:id/comments          comentar (sesión)
 */
export const postsRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const viewer = viewerOf(c);
    const limit = parseLimit(c.req.query('limit'));
    const cursor = decodeCursor(c.req.query('cursor'));
    const author = c.req.query('author');
    const communitySlug = c.req.query('community');
    const scopeName = c.req.query('scope') ?? 'all';

    let scope: FeedScope;
    if (author) scope = { kind: 'author', authorId: author };
    else if (communitySlug) {
      const community = await new CommunitiesRepository(c.env.DB).getBySlug(communitySlug, viewer);
      if (!community) throw notFound('Comunidad no encontrada.');
      scope = { kind: 'community', communityId: community.id };
    } else if (scopeName === 'following' || scopeName === 'bookmarks') {
      if (!viewer) throw unauthorized();
      scope = { kind: scopeName };
    } else if (scopeName === 'all') scope = { kind: 'all' };
    else throw badRequest('`scope` no es válido.');

    const rows = await new PostsRepository(c.env.DB).list(scope, viewer, limit, cursor);
    const { items, nextCursor } = paginate(rows, limit);
    return c.json({ data: items.map(postDto), nextCursor });
  })
  .post('/', async (c) => {
    const input = await parseBody(c, createPostSchema);
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);

    let communityId: string | null = null;
    if (input.communitySlug) {
      const communities = new CommunitiesRepository(c.env.DB);
      const community = await communities.getBySlug(input.communitySlug, user.uid);
      if (!community) throw badRequest('La comunidad no existe.');
      if (!community.my_role) throw badRequest('Únete a la comunidad para publicar en ella.');
      communityId = community.id;
    }

    let mediaAssetId: string | null = null;
    if (input.mediaAssetId) {
      const media = new MediaRepository(c.env.DB);
      const asset = await media.findActive(input.mediaAssetId);
      if (!asset || asset.owner_id !== user.uid || !['post-photo', 'observation-photo'].includes(asset.purpose)) {
        throw badRequest('La imagen indicada no es válida.');
      }
      // Una imagen publicada se puede ver con su enlace (la publicación decide quién la encuentra).
      await media.setVisibility(asset.id, 'public');
      mediaAssetId = asset.id;
    }

    const id = crypto.randomUUID();
    const posts = new PostsRepository(c.env.DB);
    await posts.create({
      id,
      authorId: user.uid,
      body: input.body,
      mediaAssetId,
      communityId,
      visibility: input.visibility,
      locationName: input.locationName ?? null,
    });
    const row = await posts.getVisible(id, user.uid);
    return c.json({ data: row ? postDto(row) : { id } }, 201);
  })
  .get('/:id', async (c) => {
    const row = await new PostsRepository(c.env.DB).getVisible(c.req.param('id'), viewerOf(c));
    if (!row) throw notFound('Publicación no encontrada.');
    return c.json({ data: postDto(row) });
  })
  .patch('/:id', async (c) => {
    const input = await parseBody(c, updatePostSchema);
    const user = c.get('user');
    const posts = new PostsRepository(c.env.DB);
    if (!(await posts.update(c.req.param('id'), user.uid, input))) throw notFound('Publicación no encontrada.');
    const row = await posts.getVisible(c.req.param('id'), user.uid);
    return c.json({ data: postDto(row!) });
  })
  .delete('/:id', async (c) => {
    const ok = await new PostsRepository(c.env.DB).softDelete(c.req.param('id'), c.get('user').uid);
    if (!ok) throw notFound('Publicación no encontrada.');
    return c.body(null, 204);
  })
  .put('/:id/like', async (c) => {
    const user = c.get('user');
    const posts = new PostsRepository(c.env.DB);
    const post = await posts.getVisible(c.req.param('id'), user.uid);
    if (!post) throw notFound('Publicación no encontrada.');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    if (await posts.like(post.id, user.uid)) {
      await new NotificationsRepository(c.env.DB).create({ userId: post.author_id, actorId: user.uid, type: 'reaction', postId: post.id });
    }
    const updated = await posts.getVisible(post.id, user.uid);
    return c.json({ data: postDto(updated ?? post) });
  })
  .delete('/:id/like', async (c) => {
    const user = c.get('user');
    const posts = new PostsRepository(c.env.DB);
    const post = await posts.getVisible(c.req.param('id'), user.uid);
    if (!post) throw notFound('Publicación no encontrada.');
    await posts.unlike(post.id, user.uid);
    const updated = await posts.getVisible(post.id, user.uid);
    return c.json({ data: postDto(updated ?? post) });
  })
  .put('/:id/bookmark', async (c) => {
    const user = c.get('user');
    const posts = new PostsRepository(c.env.DB);
    const post = await posts.getVisible(c.req.param('id'), user.uid);
    if (!post) throw notFound('Publicación no encontrada.');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    await posts.bookmark(post.id, user.uid);
    return c.body(null, 204);
  })
  .delete('/:id/bookmark', async (c) => {
    await new PostsRepository(c.env.DB).unbookmark(c.req.param('id'), c.get('user').uid);
    return c.body(null, 204);
  })
  .get('/:id/comments', async (c) => {
    const viewer = viewerOf(c);
    const posts = new PostsRepository(c.env.DB);
    const post = await posts.getVisible(c.req.param('id'), viewer);
    if (!post) throw notFound('Publicación no encontrada.');
    const limit = parseLimit(c.req.query('limit'));
    const rows = await posts.listComments(post.id, viewer, limit, decodeCursor(c.req.query('cursor')));
    const items = rows.slice(0, limit);
    const last = items[items.length - 1];
    return c.json({
      data: items.map(commentDto),
      nextCursor: rows.length > limit && last ? encodeCursor({ createdAt: last.created_at, id: last.id }) : null,
    });
  })
  .post('/:id/comments', async (c) => {
    const input = await parseBody(c, createCommentSchema);
    const user = c.get('user');
    const posts = new PostsRepository(c.env.DB);
    const post = await posts.getVisible(c.req.param('id'), user.uid);
    if (!post) throw notFound('Publicación no encontrada.');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    const id = crypto.randomUUID();
    await posts.addComment({ id, postId: post.id, authorId: user.uid, body: input.body });
    await new NotificationsRepository(c.env.DB).create({ userId: post.author_id, actorId: user.uid, type: 'comment', postId: post.id });
    const row = await posts.getComment(id);
    return c.json({ data: row ? commentDto(row) : { id } }, 201);
  });

/** DELETE /api/v1/comments/:id — su autor o el autor de la publicación. */
export const commentsRoutes = new Hono<AppBindings>().delete('/:id', async (c) => {
  const ok = await new PostsRepository(c.env.DB).deleteComment(c.req.param('id'), c.get('user').uid);
  if (!ok) throw notFound('Comentario no encontrado.');
  return c.body(null, 204);
});
