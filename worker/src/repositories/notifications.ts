import type { Cursor } from '../services/pagination';

export type NotificationType = 'follow' | 'comment' | 'reaction' | 'message' | 'community_join' | 'system';

export interface NotificationRow {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: NotificationType;
  post_id: string | null;
  conversation_id: string | null;
  /** Solo en avisos copiados de la app antigua: su texto original. */
  body: string | null;
  notebook_id: string | null;
  created_at: string;
  read_at: string | null;
  actor_username: string | null;
  actor_full_name: string | null;
  actor_display_name: string | null;
  actor_photo_asset_id: string | null;
}

export class NotificationsRepository {
  constructor(private readonly db: D1Database) {}

  /** No se notifica a uno mismo. */
  async create(n: { userId: string; actorId: string; type: NotificationType; postId?: string; conversationId?: string }) {
    if (n.userId === n.actorId) return;
    await this.db
      .prepare(`INSERT INTO notifications (id, user_id, actor_id, type, post_id, conversation_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6)`)
      .bind(crypto.randomUUID(), n.userId, n.actorId, n.type, n.postId ?? null, n.conversationId ?? null)
      .run();
  }

  async list(userId: string, limit: number, cursor: Cursor | null): Promise<NotificationRow[]> {
    const rows = await this.db
      .prepare(
        `SELECT n.*, pr.username AS actor_username, pr.full_name AS actor_full_name, u.display_name AS actor_display_name,
                pr.photo_asset_id AS actor_photo_asset_id
         FROM notifications n
         LEFT JOIN users u ON u.id = n.actor_id
         LEFT JOIN profiles pr ON pr.user_id = n.actor_id
         WHERE n.user_id = ?1
           AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = ?1 AND b.blocked_id = n.actor_id)
           AND (?2 IS NULL OR (n.created_at, n.id) < (?2, ?3))
         ORDER BY n.created_at DESC, n.id DESC LIMIT ?4`,
      )
      .bind(userId, cursor?.createdAt ?? null, cursor?.id ?? null, limit + 1)
      .all<NotificationRow>();
    return rows.results;
  }

  async unreadCount(userId: string): Promise<number> {
    const row = await this.db
      .prepare(`SELECT COUNT(*) AS n FROM notifications WHERE user_id = ?1 AND read_at IS NULL`)
      .bind(userId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  }

  /** Marca como leídas todas, o solo las indicadas (siempre del propio usuario). */
  async markRead(userId: string, ids: string[] | null): Promise<void> {
    const now = new Date().toISOString();
    if (!ids) {
      await this.db.prepare(`UPDATE notifications SET read_at = ?2 WHERE user_id = ?1 AND read_at IS NULL`).bind(userId, now).run();
      return;
    }
    if (ids.length === 0) return;
    const ph = ids.map((_, i) => `?${i + 3}`).join(', ');
    await this.db
      .prepare(`UPDATE notifications SET read_at = ?2 WHERE user_id = ?1 AND read_at IS NULL AND id IN (${ph})`)
      .bind(userId, now, ...ids)
      .run();
  }
}
