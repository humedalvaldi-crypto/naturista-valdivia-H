import type { Cursor } from '../services/pagination';

export interface MediaRow {
  id: string;
  owner_id: string;
  purpose: string;
  object_key: string;
  content_type: string;
  size_bytes: number;
  sha256: string;
  visibility: 'private' | 'public';
  status: 'active' | 'deleted';
  created_at: string;
  deleted_at: string | null;
  purged_at: string | null;
}

export interface NewMedia {
  id: string;
  ownerId: string;
  purpose: string;
  objectKey: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  visibility: 'private' | 'public';
}

/** Metadatos de archivos. Consultas parametrizadas; nunca se concatena SQL. */
export class MediaRepository {
  constructor(private readonly db: D1Database) {}

  async insert(m: NewMedia): Promise<MediaRow> {
    const row = await this.db
      .prepare(
        `INSERT INTO media_assets (id, owner_id, purpose, object_key, content_type, size_bytes, sha256, visibility)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         RETURNING *`,
      )
      .bind(m.id, m.ownerId, m.purpose, m.objectKey, m.contentType, m.sizeBytes, m.sha256, m.visibility)
      .first<MediaRow>();
    if (!row) throw new Error('media_insert_failed');
    return row;
  }

  findActive(id: string): Promise<MediaRow | null> {
    return this.db.prepare(`SELECT * FROM media_assets WHERE id = ?1 AND status = 'active'`).bind(id).first<MediaRow>();
  }

  async listByOwner(ownerId: string, limit: number, cursor: Cursor | null): Promise<MediaRow[]> {
    const stmt = cursor
      ? this.db
          .prepare(
            `SELECT * FROM media_assets
             WHERE owner_id = ?1 AND status = 'active' AND (created_at, id) < (?2, ?3)
             ORDER BY created_at DESC, id DESC LIMIT ?4`,
          )
          .bind(ownerId, cursor.createdAt, cursor.id, limit + 1)
      : this.db
          .prepare(
            `SELECT * FROM media_assets WHERE owner_id = ?1 AND status = 'active'
             ORDER BY created_at DESC, id DESC LIMIT ?2`,
          )
          .bind(ownerId, limit + 1);
    return (await stmt.all<MediaRow>()).results;
  }

  /** Marca como borrado solo si pertenece al usuario. Devuelve la fila o null. */
  markDeleted(id: string, ownerId: string): Promise<MediaRow | null> {
    return this.db
      .prepare(
        `UPDATE media_assets SET status = 'deleted', deleted_at = ?3
         WHERE id = ?1 AND owner_id = ?2 AND status = 'active'
         RETURNING *`,
      )
      .bind(id, ownerId, new Date().toISOString())
      .first<MediaRow>();
  }

  async markPurged(id: string): Promise<void> {
    await this.db.prepare(`UPDATE media_assets SET purged_at = ?2 WHERE id = ?1`).bind(id, new Date().toISOString()).run();
  }

  async pendingPurge(limit: number): Promise<MediaRow[]> {
    return (
      await this.db
        .prepare(`SELECT * FROM media_assets WHERE status = 'deleted' AND purged_at IS NULL ORDER BY deleted_at LIMIT ?1`)
        .bind(limit)
        .all<MediaRow>()
    ).results;
  }

  async existingKeys(keys: string[]): Promise<Set<string>> {
    if (keys.length === 0) return new Set();
    const placeholders = keys.map((_, i) => `?${i + 1}`).join(', ');
    const rows = await this.db
      .prepare(`SELECT object_key FROM media_assets WHERE object_key IN (${placeholders})`)
      .bind(...keys)
      .all<{ object_key: string }>();
    return new Set(rows.results.map((r) => r.object_key));
  }
}
