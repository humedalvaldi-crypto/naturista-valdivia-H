/** Exportación y eliminación de la cuenta (derechos sobre los propios datos). */
export class AccountRepository {
  constructor(private readonly db: D1Database) {}

  private all(sql: string, ...binds: unknown[]) {
    return this.db.prepare(sql).bind(...binds).all<Record<string, unknown>>().then((r) => r.results);
  }

  /** Todo lo de la persona, tal como está guardado (ubicaciones exactas incluidas: son suyas). */
  async export(uid: string) {
    const [user] = await this.all('SELECT id, email, email_verified, display_name, auth_provider, created_at FROM users WHERE id = ?1', uid);
    const parseJson = (rows: Record<string, unknown>[], field: string) =>
      rows.map((r) => ({ ...r, [field]: typeof r[field] === 'string' ? JSON.parse(r[field] as string) : r[field] }));
    return {
      exportedAt: new Date().toISOString(),
      format: 'naturista-valdivia/export/v1',
      account: user ?? null,
      settings: parseJson(await this.all('SELECT language, theme, extra_json, updated_at FROM user_settings WHERE user_id = ?1', uid), 'extra_json')[0] ?? null,
      profile: (await this.all('SELECT username, full_name, bio, location, visibility, photo_asset_id, banner_asset_id, created_at, updated_at FROM profiles WHERE user_id = ?1', uid))[0] ?? null,
      posts: await this.all('SELECT id, body, media_asset_id, community_id, visibility, location_name, created_at, deleted_at FROM posts WHERE author_id = ?1 ORDER BY created_at', uid),
      comments: await this.all('SELECT id, post_id, body, created_at, deleted_at FROM comments WHERE author_id = ?1 ORDER BY created_at', uid),
      likes: await this.all('SELECT post_id, created_at FROM reactions WHERE user_id = ?1', uid),
      bookmarks: await this.all('SELECT post_id, created_at FROM bookmarks WHERE user_id = ?1', uid),
      following: await this.all('SELECT followed_id AS user_id, created_at FROM follows WHERE follower_id = ?1', uid),
      followers: await this.all('SELECT follower_id AS user_id, created_at FROM follows WHERE followed_id = ?1', uid),
      blocked: await this.all('SELECT blocked_id AS user_id, created_at FROM blocks WHERE blocker_id = ?1', uid),
      communities: await this.all(
        `SELECT c.id, c.slug, c.name, m.role, m.joined_at FROM community_members m JOIN communities c ON c.id = m.community_id WHERE m.user_id = ?1`,
        uid,
      ),
      conversations: await Promise.all(
        (await this.all('SELECT id, user_a, user_b, created_at FROM conversations WHERE user_a = ?1 OR user_b = ?1', uid)).map(async (c) => ({
          ...c,
          messages: await this.all('SELECT id, sender_id, body, created_at, read_at FROM messages WHERE conversation_id = ?1 ORDER BY created_at', c['id']),
        })),
      ),
      observations: await this.all(
        `SELECT id, species_id, taxon_name, individual_count, observed_at, latitude, longitude, accuracy_m, location_source, location_name,
                geoprivacy, notes, photo_asset_id, visibility, created_at, updated_at, deleted_at FROM observations WHERE owner_id = ?1 ORDER BY observed_at`,
        uid,
      ),
      notebooks: await Promise.all(
        (await this.all('SELECT id, title, description, color, visibility, created_at, updated_at, deleted_at FROM notebooks WHERE owner_id = ?1 ORDER BY created_at', uid)).map(
          async (n) => ({
            ...n,
            pages: await Promise.all(
              (await this.all(
                'SELECT id, position, title, page_date, location_name, latitude, longitude, weather, paper, created_at, updated_at FROM notebook_pages WHERE notebook_id = ?1 ORDER BY position',
                n['id'],
              )).map(async (p) => ({
                ...p,
                elements: parseJson(
                  await this.all('SELECT id, type, x, y, width, height, rotation, z, data_json, media_asset_id FROM notebook_elements WHERE page_id = ?1 ORDER BY z', p['id']),
                  'data_json',
                ),
              })),
            ),
          }),
        ),
      ),
      feedback: await this.all('SELECT id, kind, message, status, created_at FROM feedback WHERE user_id = ?1 ORDER BY created_at', uid),
      notebookLikes: await this.all('SELECT notebook_id, created_at FROM notebook_likes WHERE user_id = ?1', uid),
      speciesUnlocks: await this.all('SELECT species_id, source, unlocked_at FROM species_unlocks WHERE user_id = ?1', uid),
      files: (await this.all('SELECT id, purpose, content_type, size_bytes, sha256, visibility, status, created_at FROM media_assets WHERE owner_id = ?1', uid)).map(
        (m) => ({ ...m, url: `/api/v1/media/${m['id']}` }),
      ),
    };
  }

  /**
   * Elimina la cuenta y todo su contenido (en cascada). Las publicaciones de
   * OTRAS personas en comunidades creadas por esta cuenta se conservan, sin
   * comunidad. Los archivos quedan sin dueño y el barrido diario los borra.
   */
  async delete(uid: string): Promise<void> {
    await this.db.batch([
      this.db
        .prepare(
          `UPDATE posts SET community_id = NULL
           WHERE community_id IN (SELECT id FROM communities WHERE created_by = ?1) AND author_id <> ?1`,
        )
        .bind(uid),
      this.db.prepare(`INSERT INTO deleted_accounts (uid) VALUES (?1) ON CONFLICT (uid) DO UPDATE SET deleted_at = excluded.deleted_at`).bind(uid),
      this.db.prepare(`DELETE FROM users WHERE id = ?1`).bind(uid),
    ]);
  }
}
