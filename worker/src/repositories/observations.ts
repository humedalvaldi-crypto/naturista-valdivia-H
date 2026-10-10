import type { Cursor } from '../services/pagination';

export interface SpeciesRow {
  id: string;
  scientific_name: string;
  common_name_es: string | null;
  common_name_en: string | null;
  taxon_group: string;
  conservation_status: string;
  origin: string;
  sensitive: number;
  illustration: string | null;
}

export interface ObservationRow {
  id: string;
  owner_id: string;
  species_id: string | null;
  taxon_name: string | null;
  individual_count: number | null;
  observed_at: string;
  latitude: number;
  longitude: number;
  accuracy_m: number | null;
  location_source: 'gps' | 'manual';
  location_name: string | null;
  public_latitude: number;
  public_longitude: number;
  obscured: number;
  geoprivacy: 'open' | 'obscured';
  notes: string | null;
  photo_asset_id: string | null;
  visibility: 'public' | 'private';
  created_at: string;
  updated_at: string;
  // JOIN
  owner_username: string | null;
  owner_full_name: string | null;
  owner_display_name: string | null;
  owner_photo_asset_id: string | null;
  sp_scientific_name: string | null;
  sp_common_name_es: string | null;
  sp_common_name_en: string | null;
  sp_taxon_group: string | null;
  sp_conservation_status: string | null;
  sp_sensitive: number | null;
  sp_illustration: string | null;
}

export interface PlaceRow {
  id: string;
  kind: string;
  name: string;
  description: string | null;
  latitude: number;
  longitude: number;
  geojson: string | null;
}

/**
 * Visibilidad de la observación `o` para `?1` (o NULL): la dueña siempre;
 * el resto solo si es pública, el perfil no es privado (o "solo seguidores"
 * y se le sigue) y no hay bloqueo en ningún sentido.
 */
const VISIBLE = `o.deleted_at IS NULL AND (
  o.owner_id = ?1
  OR (
    o.visibility = 'public'
    AND COALESCE(pr.visibility, 'public') <> 'private'
    AND (COALESCE(pr.visibility, 'public') = 'public'
         OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ?1 AND f.followed_id = o.owner_id))
    AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ?1 AND b.blocked_id = o.owner_id) OR (b.blocker_id = o.owner_id AND b.blocked_id = ?1))
  )
)`;

const SELECT = `
  SELECT o.*, pr.username AS owner_username, pr.full_name AS owner_full_name, u.display_name AS owner_display_name,
         pr.photo_asset_id AS owner_photo_asset_id,
         s.scientific_name AS sp_scientific_name, s.common_name_es AS sp_common_name_es, s.common_name_en AS sp_common_name_en,
         s.taxon_group AS sp_taxon_group, s.conservation_status AS sp_conservation_status, s.sensitive AS sp_sensitive,
         s.illustration AS sp_illustration
  FROM observations o
  JOIN users u ON u.id = o.owner_id
  LEFT JOIN profiles pr ON pr.user_id = o.owner_id
  LEFT JOIN species s ON s.id = o.species_id`;

export interface ObservationFilter {
  viewer: string | null;
  bbox?: { w: number; s: number; e: number; n: number } | null;
  ownerId?: string | null;
  speciesId?: string | null;
  group?: string | null;
  limit: number;
  cursor?: Cursor | null;
}

export interface ObservationWrite {
  id: string;
  ownerId: string;
  speciesId: string | null;
  taxonName: string | null;
  count: number | null;
  observedAt: string;
  latitude: number;
  longitude: number;
  accuracyM: number | null;
  locationSource: 'gps' | 'manual';
  locationName: string | null;
  publicLatitude: number;
  publicLongitude: number;
  obscured: boolean;
  geoprivacy: 'open' | 'obscured';
  notes: string | null;
  photoAssetId: string | null;
  visibility: 'public' | 'private';
}

export class ObservationsRepository {
  constructor(private readonly db: D1Database) {}

  // ── Especies ──────────────────────────────────────────────────────────
  async getSpecies(id: string): Promise<SpeciesRow | null> {
    return this.db.prepare(`SELECT * FROM species WHERE id = ?1`).bind(id).first<SpeciesRow>();
  }

  async searchSpecies(q: string | null, group: string | null, limit: number): Promise<SpeciesRow[]> {
    const where: string[] = [];
    const binds: unknown[] = [];
    if (q) {
      // Comodines escapados: la búsqueda es literal.
      const like = `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
      binds.push(like);
      const p = `?${binds.length}`;
      where.push(`(scientific_name LIKE ${p} ESCAPE '\\' OR common_name_es LIKE ${p} ESCAPE '\\' OR common_name_en LIKE ${p} ESCAPE '\\')`);
    }
    if (group) {
      binds.push(group);
      where.push(`taxon_group = ?${binds.length}`);
    }
    binds.push(limit);
    const sql = `SELECT * FROM species ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
                 ORDER BY COALESCE(common_name_es, scientific_name) COLLATE NOCASE LIMIT ?${binds.length}`;
    return (await this.db.prepare(sql).bind(...binds).all<SpeciesRow>()).results;
  }

  // ── Observaciones ─────────────────────────────────────────────────────
  async get(id: string, viewer: string | null): Promise<ObservationRow | null> {
    return this.db.prepare(`${SELECT} WHERE o.id = ?2 AND ${VISIBLE}`).bind(viewer, id).first<ObservationRow>();
  }

  async getOwned(id: string, ownerId: string): Promise<ObservationRow | null> {
    return this.db
      .prepare(`${SELECT} WHERE o.id = ?2 AND o.owner_id = ?1 AND o.deleted_at IS NULL`)
      .bind(ownerId, id)
      .first<ObservationRow>();
  }

  async list(f: ObservationFilter): Promise<ObservationRow[]> {
    const binds: unknown[] = [f.viewer];
    const where = [VISIBLE];
    const add = (sql: (p: string) => string, value: unknown) => {
      binds.push(value);
      where.push(sql(`?${binds.length}`));
    };
    if (f.bbox) {
      // Terceros: se filtra por la ubicación pública (no revela la exacta).
      // Lo propio: por la exacta.
      binds.push(f.bbox.s, f.bbox.n, f.bbox.w, f.bbox.e);
      const [s, n, w, e] = [binds.length - 3, binds.length - 2, binds.length - 1, binds.length].map((i) => `?${i}`);
      where.push(`(CASE WHEN o.owner_id = ?1
                     THEN (o.latitude BETWEEN ${s} AND ${n} AND o.longitude BETWEEN ${w} AND ${e})
                     ELSE (o.public_latitude BETWEEN ${s} AND ${n} AND o.public_longitude BETWEEN ${w} AND ${e}) END)`);
    }
    if (f.ownerId) add((p) => `o.owner_id = ${p}`, f.ownerId);
    if (f.speciesId) add((p) => `o.species_id = ${p}`, f.speciesId);
    if (f.group) add((p) => `s.taxon_group = ${p}`, f.group);
    if (f.cursor) {
      binds.push(f.cursor.createdAt, f.cursor.id);
      const a = `?${binds.length - 1}`;
      const b = `?${binds.length}`;
      where.push(`(o.created_at < ${a} OR (o.created_at = ${a} AND o.id < ${b}))`);
    }
    binds.push(f.limit + 1);
    const sql = `${SELECT} WHERE ${where.join(' AND ')} ORDER BY o.created_at DESC, o.id DESC LIMIT ?${binds.length}`;
    return (await this.db.prepare(sql).bind(...binds).all<ObservationRow>()).results;
  }

  async insert(o: ObservationWrite): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO observations (id, owner_id, species_id, taxon_name, individual_count, observed_at, latitude, longitude,
           accuracy_m, location_source, location_name, public_latitude, public_longitude, obscured, geoprivacy, notes,
           photo_asset_id, visibility)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)`,
      )
      .bind(
        o.id, o.ownerId, o.speciesId, o.taxonName, o.count, o.observedAt, o.latitude, o.longitude,
        o.accuracyM, o.locationSource, o.locationName, o.publicLatitude, o.publicLongitude, o.obscured ? 1 : 0, o.geoprivacy, o.notes,
        o.photoAssetId, o.visibility,
      )
      .run();
  }

  async update(o: ObservationWrite): Promise<void> {
    await this.db
      .prepare(
        `UPDATE observations SET species_id = ?3, taxon_name = ?4, individual_count = ?5, observed_at = ?6, latitude = ?7,
           longitude = ?8, accuracy_m = ?9, location_source = ?10, location_name = ?11, public_latitude = ?12,
           public_longitude = ?13, obscured = ?14, geoprivacy = ?15, notes = ?16, photo_asset_id = ?17, visibility = ?18,
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?1 AND owner_id = ?2 AND deleted_at IS NULL`,
      )
      .bind(
        o.id, o.ownerId, o.speciesId, o.taxonName, o.count, o.observedAt, o.latitude, o.longitude,
        o.accuracyM, o.locationSource, o.locationName, o.publicLatitude, o.publicLongitude, o.obscured ? 1 : 0, o.geoprivacy, o.notes,
        o.photoAssetId, o.visibility,
      )
      .run();
  }

  async softDelete(id: string, ownerId: string): Promise<boolean> {
    const res = await this.db
      .prepare(`UPDATE observations SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?1 AND owner_id = ?2 AND deleted_at IS NULL`)
      .bind(id, ownerId)
      .run();
    return res.meta.changes > 0;
  }

  // ── Lugares ───────────────────────────────────────────────────────────
  async places(bbox: { w: number; s: number; e: number; n: number } | null, limit: number): Promise<PlaceRow[]> {
    if (!bbox) return (await this.db.prepare(`SELECT * FROM places ORDER BY name LIMIT ?1`).bind(limit).all<PlaceRow>()).results;
    return (
      await this.db
        .prepare(`SELECT * FROM places WHERE latitude BETWEEN ?1 AND ?2 AND longitude BETWEEN ?3 AND ?4 ORDER BY name LIMIT ?5`)
        .bind(bbox.s, bbox.n, bbox.w, bbox.e, limit)
        .all<PlaceRow>()
    ).results;
  }
}
