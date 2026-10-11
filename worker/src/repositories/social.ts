/**
 * Relaciones entre personas (seguir, bloquear) y reglas de visibilidad.
 * Todas las rutas sociales usan estas funciones para decidir qué se ve.
 */

/**
 * Fragmento SQL: la publicación `p` (con su perfil de autor `pr`) es visible
 * para el usuario del parámetro `viewerParam` (puede ser NULL = anónimo).
 * - El autor siempre ve lo suyo.
 * - Perfil privado: nadie más ve sus publicaciones.
 * - Perfil "solo seguidores" o publicación "seguidores": hace falta seguirle.
 * - Si cualquiera de los dos bloqueó al otro, no se ve.
 */
export function visiblePostSql(viewerParam: string): string {
  const follows = `EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${viewerParam} AND f.followed_id = p.author_id)`;
  const blocked = `EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ${viewerParam} AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = ${viewerParam}))`;
  return `p.deleted_at IS NULL AND (
    p.author_id = ${viewerParam}
    OR (
      COALESCE(pr.visibility, 'public') <> 'private'
      AND (COALESCE(pr.visibility, 'public') = 'public' OR ${follows})
      AND (p.visibility = 'public' OR ${follows})
      AND NOT ${blocked}
    )
  )`;
}

export class SocialRepository {
  constructor(private readonly db: D1Database) {}

  async userExists(id: string): Promise<boolean> {
    return (await this.db.prepare(`SELECT 1 AS ok FROM users WHERE id = ?1 AND status = 'active'`).bind(id).first()) !== null;
  }

  /** ¿Alguno de los dos bloqueó al otro? */
  async blockedEitherWay(a: string, b: string): Promise<boolean> {
    const row = await this.db
      .prepare(`SELECT 1 AS ok FROM blocks WHERE (blocker_id = ?1 AND blocked_id = ?2) OR (blocker_id = ?2 AND blocked_id = ?1) LIMIT 1`)
      .bind(a, b)
      .first();
    return row !== null;
  }

  async isFollowing(follower: string, followed: string): Promise<boolean> {
    return (
      (await this.db.prepare(`SELECT 1 AS ok FROM follows WHERE follower_id = ?1 AND followed_id = ?2`).bind(follower, followed).first()) !== null
    );
  }

  /** Devuelve true si se creó (false si ya existía). */
  async follow(follower: string, followed: string): Promise<boolean> {
    const res = await this.db
      .prepare(`INSERT INTO follows (follower_id, followed_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING`)
      .bind(follower, followed)
      .run();
    return res.meta.changes > 0;
  }

  async unfollow(follower: string, followed: string): Promise<void> {
    await this.db.prepare(`DELETE FROM follows WHERE follower_id = ?1 AND followed_id = ?2`).bind(follower, followed).run();
  }

  /** Bloquear también deshace el seguimiento en ambos sentidos. */
  async block(blocker: string, blocked: string): Promise<void> {
    await this.db.batch([
      this.db.prepare(`INSERT INTO blocks (blocker_id, blocked_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING`).bind(blocker, blocked),
      this.db
        .prepare(`DELETE FROM follows WHERE (follower_id = ?1 AND followed_id = ?2) OR (follower_id = ?2 AND followed_id = ?1)`)
        .bind(blocker, blocked),
    ]);
  }

  async unblock(blocker: string, blocked: string): Promise<void> {
    await this.db.prepare(`DELETE FROM blocks WHERE blocker_id = ?1 AND blocked_id = ?2`).bind(blocker, blocked).run();
  }

  async counts(userId: string): Promise<{ followers: number; following: number; posts: number }> {
    const row = await this.db
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM follows WHERE followed_id = ?1) AS followers,
           (SELECT COUNT(*) FROM follows WHERE follower_id = ?1) AS following,
           (SELECT COUNT(*) FROM posts WHERE author_id = ?1 AND deleted_at IS NULL) AS posts`,
      )
      .bind(userId)
      .first<{ followers: number; following: number; posts: number }>();
    return row ?? { followers: 0, following: 0, posts: 0 };
  }

  /** Lista seguidores o seguidos, con su perfil público, paginada por fecha. */
  /**
   * Personas por nombre o usuario (sin distinguir mayúsculas). Excluye perfiles
   * privados, cuentas no activas y bloqueos en ambos sentidos. Orden estable por
   * nombre e id para paginar con cursor (sin límite fijo de resultados).
   */
  async search(viewer: string | null, query: string, limit: number, after: { name: string; id: string } | null) {
    const like = `%${query.toLowerCase().replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
    const rows = await this.db
      .prepare(
        `SELECT u.id, pr.username, pr.full_name, pr.photo_asset_id, u.display_name,
                lower(COALESCE(pr.full_name, u.display_name, pr.username, '')) AS sort_name,
                EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ?1 AND f.followed_id = u.id) AS followed_by_me,
                EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = u.id AND f.followed_id = ?1) AS follows_me
         FROM users u
         LEFT JOIN profiles pr ON pr.user_id = u.id
         WHERE u.status = 'active'
           AND COALESCE(pr.visibility, 'public') <> 'private'
           AND (lower(COALESCE(pr.username, '')) LIKE ?2 ESCAPE '\\'
                OR lower(COALESCE(pr.full_name, '')) LIKE ?2 ESCAPE '\\'
                OR lower(COALESCE(u.display_name, '')) LIKE ?2 ESCAPE '\\')
           AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ?1 AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = ?1))
           AND (?3 IS NULL OR (lower(COALESCE(pr.full_name, u.display_name, pr.username, '')), u.id) > (?3, ?4))
         ORDER BY sort_name, u.id
         LIMIT ?5`,
      )
      .bind(viewer ?? '', like, after?.name ?? null, after?.id ?? null, limit + 1)
      .all<PersonSearchRow>();
    return rows.results;
  }

  /**
   * Sugerencias reales: personas que siguen quienes sigo (y cuántas de ellas),
   * excluyendo a quien ya sigo, a mí y bloqueos. Sin datos inventados: si no
   * hay red, la lista queda vacía.
   */
  async suggestions(viewer: string, limit: number) {
    const rows = await this.db
      .prepare(
        `SELECT u.id, pr.username, pr.full_name, pr.photo_asset_id, u.display_name, count(*) AS mutuals,
                0 AS followed_by_me,
                EXISTS (SELECT 1 FROM follows f3 WHERE f3.follower_id = u.id AND f3.followed_id = ?1) AS follows_me
         FROM follows f1
         JOIN follows f2 ON f2.follower_id = f1.followed_id
         JOIN users u ON u.id = f2.followed_id
         LEFT JOIN profiles pr ON pr.user_id = u.id
         WHERE f1.follower_id = ?1
           AND u.id <> ?1 AND u.status = 'active'
           AND COALESCE(pr.visibility, 'public') <> 'private'
           AND NOT EXISTS (SELECT 1 FROM follows f4 WHERE f4.follower_id = ?1 AND f4.followed_id = u.id)
           AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ?1 AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = ?1))
         GROUP BY u.id
         ORDER BY mutuals DESC, u.id
         LIMIT ?2`,
      )
      .bind(viewer, limit)
      .all<PersonSearchRow & { mutuals: number }>();
    return rows.results;
  }

  async listBlocked(userId: string) {
    const rows = await this.db
      .prepare(
        `SELECT b.blocked_id AS id, b.created_at, pr.username, pr.full_name, pr.photo_asset_id, u.display_name
         FROM blocks b
         JOIN users u ON u.id = b.blocked_id
         LEFT JOIN profiles pr ON pr.user_id = b.blocked_id
         WHERE b.blocker_id = ?1
         ORDER BY b.created_at DESC LIMIT 200`,
      )
      .bind(userId)
      .all<{ id: string; created_at: string; username: string | null; full_name: string | null; photo_asset_id: string | null; display_name: string | null }>();
    return rows.results;
  }

  /** Respeta "quién puede escribirme" de quien recibe. */
  async canMessage(sender: string, recipient: string): Promise<boolean> {
    const row = await this.db
      .prepare(
        `SELECT COALESCE(json_extract(s.extra_json, '$.privacy.messages'), 'everyone') AS policy,
                EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ?2 AND f.followed_id = ?1) AS follows_sender
         FROM (SELECT 1) LEFT JOIN user_settings s ON s.user_id = ?2`,
      )
      .bind(sender, recipient)
      .first<{ policy: string; follows_sender: number }>();
    if (!row || row.policy === 'everyone') return true;
    if (row.policy === 'following') return row.follows_sender === 1;
    return false;
  }

  async listConnections(userId: string, direction: 'followers' | 'following', limit: number, before: string | null) {
    const [me, other] = direction === 'followers' ? ['followed_id', 'follower_id'] : ['follower_id', 'followed_id'];
    const rows = await this.db
      .prepare(
        `SELECT f.${other} AS id, f.created_at, pr.username, pr.full_name, pr.photo_asset_id, u.display_name
         FROM follows f
         JOIN users u ON u.id = f.${other}
         LEFT JOIN profiles pr ON pr.user_id = f.${other}
         WHERE f.${me} = ?1 AND (?2 IS NULL OR f.created_at < ?2)
         ORDER BY f.created_at DESC LIMIT ?3`,
      )
      .bind(userId, before, limit + 1)
      .all<{ id: string; created_at: string; username: string | null; full_name: string | null; photo_asset_id: string | null; display_name: string | null }>();
    return rows.results;
  }
}

export interface PersonSearchRow {
  id: string;
  username: string | null;
  full_name: string | null;
  photo_asset_id: string | null;
  display_name: string | null;
  sort_name?: string;
  followed_by_me: number;
  follows_me: number;
}
