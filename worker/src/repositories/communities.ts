export interface CommunityRow {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  wetland: string | null;
  photo_asset_id: string | null;
  created_by: string;
  member_count: number;
  created_at: string;
  my_role: string | null;
}

const SELECT = `
  SELECT c.*, (SELECT m.role FROM community_members m WHERE m.community_id = c.id AND m.user_id = ?1) AS my_role
  FROM communities c`;

export class SlugTakenError extends Error {}

export class CommunitiesRepository {
  constructor(private readonly db: D1Database) {}

  /** Crea la comunidad y deja a su creador como dueño. */
  async create(c: { id: string; slug: string; name: string; description: string | null; wetland: string | null; photoAssetId: string | null; createdBy: string }) {
    try {
      await this.db.batch([
        this.db
          .prepare(
            `INSERT INTO communities (id, slug, name, description, wetland, photo_asset_id, created_by, member_count)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1)`,
          )
          .bind(c.id, c.slug, c.name, c.description, c.wetland, c.photoAssetId, c.createdBy),
        this.db.prepare(`INSERT INTO community_members (community_id, user_id, role) VALUES (?1, ?2, 'owner')`).bind(c.id, c.createdBy),
      ]);
    } catch (err) {
      if (String((err as Error).message).includes('UNIQUE constraint failed: communities.slug')) throw new SlugTakenError();
      throw err;
    }
  }

  getBySlug(slug: string, viewer: string | null): Promise<CommunityRow | null> {
    return this.db.prepare(`${SELECT} WHERE c.slug = ?2`).bind(viewer, slug).first<CommunityRow>();
  }

  /** Listado por nombre; `mine` = solo las comunidades a las que pertenezco. */
  async list(viewer: string | null, opts: { mine: boolean; query: string | null; limit: number; afterName: string | null }) {
    const rows = await this.db
      .prepare(
        `${SELECT}
         WHERE (?2 = 0 OR EXISTS (SELECT 1 FROM community_members m2 WHERE m2.community_id = c.id AND m2.user_id = ?1))
           AND (?3 IS NULL OR c.name LIKE ?3 ESCAPE '\\' OR c.wetland LIKE ?3 ESCAPE '\\')
           AND (?4 IS NULL OR c.name > ?4)
         ORDER BY c.name LIMIT ?5`,
      )
      .bind(viewer, opts.mine ? 1 : 0, opts.query, opts.afterName, opts.limit + 1)
      .all<CommunityRow>();
    return rows.results;
  }

  async isMember(communityId: string, userId: string): Promise<boolean> {
    return (
      (await this.db.prepare(`SELECT 1 AS ok FROM community_members WHERE community_id = ?1 AND user_id = ?2`).bind(communityId, userId).first()) !== null
    );
  }

  async join(communityId: string, userId: string): Promise<boolean> {
    const res = await this.db
      .prepare(`INSERT INTO community_members (community_id, user_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING`)
      .bind(communityId, userId)
      .run();
    if (res.meta.changes > 0) {
      await this.db.prepare(`UPDATE communities SET member_count = member_count + 1 WHERE id = ?1`).bind(communityId).run();
      return true;
    }
    return false;
  }

  /** El dueño no puede salir (debería transferir o borrar la comunidad). */
  async leave(communityId: string, userId: string): Promise<'left' | 'owner' | 'not_member'> {
    const row = await this.db
      .prepare(`SELECT role FROM community_members WHERE community_id = ?1 AND user_id = ?2`)
      .bind(communityId, userId)
      .first<{ role: string }>();
    if (!row) return 'not_member';
    if (row.role === 'owner') return 'owner';
    await this.db.batch([
      this.db.prepare(`DELETE FROM community_members WHERE community_id = ?1 AND user_id = ?2`).bind(communityId, userId),
      this.db.prepare(`UPDATE communities SET member_count = MAX(member_count - 1, 0) WHERE id = ?1`).bind(communityId),
    ]);
    return 'left';
  }
}
