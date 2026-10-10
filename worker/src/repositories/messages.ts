import type { Cursor } from '../services/pagination';

export interface ConversationRow {
  id: string;
  user_a: string;
  user_b: string;
  last_message_at: string | null;
  created_at: string;
  other_id: string;
  other_username: string | null;
  other_full_name: string | null;
  other_display_name: string | null;
  other_photo_asset_id: string | null;
  last_body: string | null;
  unread: number;
}

export interface MessageRow {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string;
  created_at: string;
  read_at: string | null;
}

/** Ordena el par para que (a, b) sea único. */
export const pair = (x: string, y: string): [string, string] => (x < y ? [x, y] : [y, x]);

export class MessagesRepository {
  constructor(private readonly db: D1Database) {}

  /** Devuelve la conversación existente entre ambos o la crea. */
  async findBetween(me: string, other: string): Promise<string | null> {
    const [a, b] = pair(me, other);
    const row = await this.db.prepare(`SELECT id FROM conversations WHERE user_a = ?1 AND user_b = ?2`).bind(a, b).first<{ id: string }>();
    return row?.id ?? null;
  }

  async openConversation(me: string, other: string): Promise<string> {
    const [a, b] = pair(me, other);
    await this.db
      .prepare(`INSERT INTO conversations (id, user_a, user_b) VALUES (?1, ?2, ?3) ON CONFLICT (user_a, user_b) DO NOTHING`)
      .bind(crypto.randomUUID(), a, b)
      .run();
    const row = await this.db.prepare(`SELECT id FROM conversations WHERE user_a = ?1 AND user_b = ?2`).bind(a, b).first<{ id: string }>();
    if (!row) throw new Error('conversation_open_failed');
    return row.id;
  }

  /** La conversación solo existe para sus dos participantes. */
  getForMember(id: string, me: string): Promise<{ id: string; user_a: string; user_b: string } | null> {
    return this.db
      .prepare(`SELECT id, user_a, user_b FROM conversations WHERE id = ?1 AND (user_a = ?2 OR user_b = ?2)`)
      .bind(id, me)
      .first();
  }

  async listConversations(me: string, limit: number): Promise<ConversationRow[]> {
    const rows = await this.db
      .prepare(
        `SELECT c.*, o.id AS other_id, pr.username AS other_username, pr.full_name AS other_full_name,
                o.display_name AS other_display_name, pr.photo_asset_id AS other_photo_asset_id,
                (SELECT m.body FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body,
                (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id AND m.sender_id <> ?1 AND m.read_at IS NULL) AS unread
         FROM conversations c
         JOIN users o ON o.id = CASE WHEN c.user_a = ?1 THEN c.user_b ELSE c.user_a END
         LEFT JOIN profiles pr ON pr.user_id = o.id
         WHERE (c.user_a = ?1 OR c.user_b = ?1) AND c.last_message_at IS NOT NULL
         ORDER BY c.last_message_at DESC LIMIT ?2`,
      )
      .bind(me, limit)
      .all<ConversationRow>();
    return rows.results;
  }

  async send(m: { id: string; conversationId: string; senderId: string; body: string }): Promise<MessageRow> {
    const now = new Date().toISOString();
    const [, row] = await this.db.batch<MessageRow>([
      this.db.prepare(`UPDATE conversations SET last_message_at = ?2 WHERE id = ?1`).bind(m.conversationId, now),
      this.db
        .prepare(`INSERT INTO messages (id, conversation_id, sender_id, body, created_at) VALUES (?1, ?2, ?3, ?4, ?5) RETURNING *`)
        .bind(m.id, m.conversationId, m.senderId, m.body, now),
    ]);
    const msg = row?.results[0];
    if (!msg) throw new Error('message_send_failed');
    return msg;
  }

  /** Mensajes más recientes primero (la app los invierte para mostrarlos). */
  async list(conversationId: string, limit: number, cursor: Cursor | null): Promise<MessageRow[]> {
    const rows = await this.db
      .prepare(
        `SELECT * FROM messages WHERE conversation_id = ?1 AND (?2 IS NULL OR (created_at, id) < (?2, ?3))
         ORDER BY created_at DESC, id DESC LIMIT ?4`,
      )
      .bind(conversationId, cursor?.createdAt ?? null, cursor?.id ?? null, limit + 1)
      .all<MessageRow>();
    return rows.results;
  }

  async markRead(conversationId: string, reader: string): Promise<void> {
    await this.db
      .prepare(`UPDATE messages SET read_at = ?3 WHERE conversation_id = ?1 AND sender_id <> ?2 AND read_at IS NULL`)
      .bind(conversationId, reader, new Date().toISOString())
      .run();
  }
}
