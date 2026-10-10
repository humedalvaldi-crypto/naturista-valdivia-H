import type { Cursor } from '../services/pagination';
import { visiblePostSql } from './social';

export interface PostRow {
  id: string;
  author_id: string;
  body: string;
  media_asset_id: string | null;
  community_id: string | null;
  visibility: 'public' | 'followers';
  location_name: string | null;
  comment_count: number;
  reaction_count: number;
  created_at: string;
  updated_at: string;
  // Datos del autor (JOIN).
  author_username: string | null;
  author_full_name: string | null;
  author_display_name: string | null;
  author_photo_asset_id: string | null;
  community_slug: string | null;
  liked_by_me: number;
  bookmarked_by_me: number;
}

export interface CommentRow {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  author_username: string | null;
  author_full_name: string | null;
  author_display_name: string | null;
  author_photo_asset_id: string | null;
}

export type FeedScope =
  | { kind: 'all' }
  | { kind: 'following' }
  | { kind: 'author'; authorId: string }
  | { kind: 'community'; communityId: string }
  | { kind: 'bookmarks' };

/** SELECT común: ?1 = espectador (o NULL). */
const POST_SELECT = `
  SELECT p.*, pr.username AS author_username, pr.full_name AS author_full_name, u.display_name AS author_display_name,
         pr.photo_asset_id AS author_photo_asset_id, c.slug AS community_slug,
         EXISTS (SELECT 1 FROM reactions r WHERE r.post_id = p.id AND r.user_id = ?1) AS liked_by_me,
         EXISTS (SELECT 1 FROM bookmarks bm WHERE bm.post_id = p.id AND bm.user_id = ?1) AS bookmarked_by_me
  FROM posts p
  JOIN users u ON u.id = p.author_id
  LEFT JOIN profiles pr ON pr.user_id = p.author_id
  LEFT JOIN communities c ON c.id = p.community_id`;

const COMMENT_SELECT = `
  SELECT cm.id, cm.post_id, cm.author_id, cm.body, cm.created_at,
         pr.username AS author_username, pr.full_name AS author_full_name, u.display_name AS author_display_name,
         pr.photo_asset_id AS author_photo_asset_id
  FROM comments cm
  JOIN users u ON u.id = cm.author_id
  LEFT JOIN profiles pr ON pr.user_id = cm.author_id`;

export class PostsRepository {
  constructor(private readonly db: D1Database) {}

  async create(p: {
    id: string;
    authorId: string;
    body: string;
    mediaAssetId: string | null;
    communityId: string | null;
    visibility: 'public' | 'followers';
    locationName: string | null;
  }): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO posts (id, author_id, body, media_asset_id, community_id, visibility, location_name)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
      )
      .bind(p.id, p.authorId, p.body, p.mediaAssetId, p.communityId, p.visibility, p.locationName)
      .run();
  }

  /** Una publicación, solo si el espectador puede verla. */
  getVisible(id: string, viewer: string | null): Promise<PostRow | null> {
    return this.db
      .prepare(`${POST_SELECT} WHERE p.id = ?2 AND ${visiblePostSql('?1')}`)
      .bind(viewer, id)
      .first<PostRow>();
  }

  /** Lista paginada (más recientes primero) según el alcance. */
  async list(scope: FeedScope, viewer: string | null, limit: number, cursor: Cursor | null): Promise<PostRow[]> {
    const where: string[] = [visiblePostSql('?1')];
    const params: unknown[] = [viewer];
    const add = (sql: string, ...values: unknown[]) => {
      let s = sql;
      for (const v of values) {
        params.push(v);
        s = s.replace(/\?(?!\d)/, `?${params.length}`); // solo marcadores aún sin número
      }
      where.push(s);
    };
    switch (scope.kind) {
      case 'following':
        where.push(`(p.author_id = ?1 OR EXISTS (SELECT 1 FROM follows f2 WHERE f2.follower_id = ?1 AND f2.followed_id = p.author_id))`);
        break;
      case 'author':
        add('p.author_id = ?', scope.authorId);
        break;
      case 'community':
        add('p.community_id = ?', scope.communityId);
        break;
      case 'bookmarks':
        where.push(`EXISTS (SELECT 1 FROM bookmarks b2 WHERE b2.user_id = ?1 AND b2.post_id = p.id)`);
        break;
      case 'all':
        break;
    }
    if (cursor) add('(p.created_at, p.id) < (?, ?)', cursor.createdAt, cursor.id);
    params.push(limit + 1);
    const sql = `${POST_SELECT} WHERE ${where.join(' AND ')} ORDER BY p.created_at DESC, p.id DESC LIMIT ?${params.length}`;
    return (await this.db.prepare(sql).bind(...params).all<PostRow>()).results;
  }

  /** Borrado lógico, solo por su autor. */
  async softDelete(id: string, authorId: string): Promise<boolean> {
    const res = await this.db
      .prepare(`UPDATE posts SET deleted_at = ?3 WHERE id = ?1 AND author_id = ?2 AND deleted_at IS NULL`)
      .bind(id, authorId, new Date().toISOString())
      .run();
    return res.meta.changes > 0;
  }

  /** Me gusta idempotente; devuelve true si se creó. Mantiene el contador. */
  async like(postId: string, userId: string): Promise<boolean> {
    const res = await this.db
      .prepare(`INSERT INTO reactions (post_id, user_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING`)
      .bind(postId, userId)
      .run();
    if (res.meta.changes > 0) {
      await this.db.prepare(`UPDATE posts SET reaction_count = reaction_count + 1 WHERE id = ?1`).bind(postId).run();
      return true;
    }
    return false;
  }

  async unlike(postId: string, userId: string): Promise<void> {
    const res = await this.db.prepare(`DELETE FROM reactions WHERE post_id = ?1 AND user_id = ?2`).bind(postId, userId).run();
    if (res.meta.changes > 0) {
      await this.db
        .prepare(`UPDATE posts SET reaction_count = MAX(reaction_count - 1, 0) WHERE id = ?1`)
        .bind(postId)
        .run();
    }
  }

  async bookmark(postId: string, userId: string): Promise<void> {
    await this.db.prepare(`INSERT INTO bookmarks (user_id, post_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING`).bind(userId, postId).run();
  }

  async unbookmark(postId: string, userId: string): Promise<void> {
    await this.db.prepare(`DELETE FROM bookmarks WHERE user_id = ?1 AND post_id = ?2`).bind(userId, postId).run();
  }

  async addComment(c: { id: string; postId: string; authorId: string; body: string }): Promise<void> {
    await this.db.batch([
      this.db.prepare(`INSERT INTO comments (id, post_id, author_id, body) VALUES (?1, ?2, ?3, ?4)`).bind(c.id, c.postId, c.authorId, c.body),
      this.db.prepare(`UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?1`).bind(c.postId),
    ]);
  }

  getComment(id: string): Promise<CommentRow | null> {
    return this.db.prepare(`${COMMENT_SELECT} WHERE cm.id = ?1 AND cm.deleted_at IS NULL`).bind(id).first<CommentRow>();
  }

  /** Comentarios en orden cronológico, sin los de personas bloqueadas por el espectador. */
  async listComments(postId: string, viewer: string | null, limit: number, after: Cursor | null): Promise<CommentRow[]> {
    const rows = await this.db
      .prepare(
        `${COMMENT_SELECT}
         WHERE cm.post_id = ?1 AND cm.deleted_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ?2 AND b.blocked_id = cm.author_id) OR (b.blocker_id = cm.author_id AND b.blocked_id = ?2))
           AND (?3 IS NULL OR (cm.created_at, cm.id) > (?3, ?4))
         ORDER BY cm.created_at, cm.id LIMIT ?5`,
      )
      .bind(postId, viewer, after?.createdAt ?? null, after?.id ?? null, limit + 1)
      .all<CommentRow>();
    return rows.results;
  }

  /** Borra un comentario si quien pide es su autor o el autor de la publicación. */
  async deleteComment(commentId: string, requester: string): Promise<boolean> {
    const row = await this.db
      .prepare(
        `SELECT cm.post_id FROM comments cm JOIN posts p ON p.id = cm.post_id
         WHERE cm.id = ?1 AND cm.deleted_at IS NULL AND (cm.author_id = ?2 OR p.author_id = ?2)`,
      )
      .bind(commentId, requester)
      .first<{ post_id: string }>();
    if (!row) return false;
    await this.db.batch([
      this.db.prepare(`UPDATE comments SET deleted_at = ?2 WHERE id = ?1`).bind(commentId, new Date().toISOString()),
      this.db.prepare(`UPDATE posts SET comment_count = MAX(comment_count - 1, 0) WHERE id = ?1`).bind(row.post_id),
    ]);
    return true;
  }
}
