import type { SavePageInput } from '../validators/notebooks';

export interface NotebookRow {
  id: string;
  owner_id: string;
  title: string;
  description: string | null;
  color: string;
  cover_asset_id: string | null;
  visibility: 'private' | 'public';
  page_count: number;
  created_at: string;
  updated_at: string;
}

export interface PageRow {
  id: string;
  notebook_id: string;
  position: number;
  title: string | null;
  page_date: string | null;
  location_name: string | null;
  latitude: number | null;
  longitude: number | null;
  location_source: 'gps' | 'manual' | null;
  weather: string | null;
  paper: string;
  version: number;
  created_at: string;
  updated_at: string;
  element_count?: number;
}

export interface ElementRow {
  id: string;
  page_id: string;
  type: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  z: number;
  data_json: string;
  media_asset_id: string | null;
}

export class NotebooksRepository {
  constructor(private readonly db: D1Database) {}

  // ── Cuadernos ───────────────────────────────────────────────────────────

  async create(n: { id: string; ownerId: string; title: string; description: string | null; color: string; visibility: string }) {
    await this.db
      .prepare(`INSERT INTO notebooks (id, owner_id, title, description, color, visibility) VALUES (?1, ?2, ?3, ?4, ?5, ?6)`)
      .bind(n.id, n.ownerId, n.title, n.description, n.color, n.visibility)
      .run();
  }

  get(id: string): Promise<NotebookRow | null> {
    return this.db.prepare(`SELECT * FROM notebooks WHERE id = ?1 AND deleted_at IS NULL`).bind(id).first<NotebookRow>();
  }

  /** Cuadernos de una persona: todos si es la dueña, solo públicos si no. */
  async listByOwner(ownerId: string, includePrivate: boolean): Promise<NotebookRow[]> {
    return (
      await this.db
        .prepare(
          `SELECT * FROM notebooks WHERE owner_id = ?1 AND deleted_at IS NULL AND (?2 = 1 OR visibility = 'public')
           ORDER BY updated_at DESC LIMIT 200`,
        )
        .bind(ownerId, includePrivate ? 1 : 0)
        .all<NotebookRow>()
    ).results;
  }

  async update(id: string, fields: Record<string, unknown>): Promise<void> {
    const allowed: Record<string, string> = {
      title: 'title',
      description: 'description',
      color: 'color',
      visibility: 'visibility',
      coverAssetId: 'cover_asset_id',
    };
    const entries = Object.entries(fields).filter(([k, v]) => k in allowed && v !== undefined);
    if (entries.length === 0) return;
    const sets = entries.map(([k], i) => `${allowed[k]} = ?${i + 2}`);
    await this.db
      .prepare(`UPDATE notebooks SET ${sets.join(', ')}, updated_at = ?${entries.length + 2} WHERE id = ?1`)
      .bind(id, ...entries.map(([, v]) => v ?? null), new Date().toISOString())
      .run();
  }

  async softDelete(id: string): Promise<void> {
    await this.db.prepare(`UPDATE notebooks SET deleted_at = ?2 WHERE id = ?1`).bind(id, new Date().toISOString()).run();
  }

  // ── Páginas ─────────────────────────────────────────────────────────────

  async listPages(notebookId: string): Promise<PageRow[]> {
    return (
      await this.db
        .prepare(
          `SELECT p.*, (SELECT COUNT(*) FROM notebook_elements e WHERE e.page_id = p.id) AS element_count
           FROM notebook_pages p WHERE p.notebook_id = ?1 ORDER BY p.position`,
        )
        .bind(notebookId)
        .all<PageRow>()
    ).results;
  }

  /** Página con el cuaderno al que pertenece (para comprobar permisos). */
  getPage(id: string): Promise<(PageRow & { owner_id: string; visibility: string }) | null> {
    return this.db
      .prepare(
        `SELECT p.*, n.owner_id, n.visibility FROM notebook_pages p
         JOIN notebooks n ON n.id = p.notebook_id AND n.deleted_at IS NULL
         WHERE p.id = ?1`,
      )
      .bind(id)
      .first();
  }

  async elements(pageId: string): Promise<ElementRow[]> {
    return (
      await this.db.prepare(`SELECT * FROM notebook_elements WHERE page_id = ?1 ORDER BY z, id`).bind(pageId).all<ElementRow>()
    ).results;
  }

  /** Agrega una página al final y actualiza el contador. */
  async addPage(notebookId: string, id: string, pageDate: string | null): Promise<void> {
    const now = new Date().toISOString();
    await this.db.batch([
      this.db
        .prepare(
          `INSERT INTO notebook_pages (id, notebook_id, position, page_date)
           VALUES (?1, ?2, (SELECT COALESCE(MAX(position) + 1, 0) FROM notebook_pages WHERE notebook_id = ?2), ?3)`,
        )
        .bind(id, notebookId, pageDate),
      this.db.prepare(`UPDATE notebooks SET page_count = page_count + 1, updated_at = ?2 WHERE id = ?1`).bind(notebookId, now),
    ]);
  }

  /**
   * Guarda una página completa de forma ATÓMICA y solo si nadie la cambió
   * desde que se leyó (`version`). Todas las sentencias están condicionadas a
   * la versión; si no coincide, ninguna tiene efecto y se devuelve false.
   */
  async savePage(page: { id: string; notebookId: string }, input: SavePageInput): Promise<number | null> {
    const guard = `EXISTS (SELECT 1 FROM notebook_pages WHERE id = ?1 AND version = ?2)`;
    const now = new Date().toISOString();
    const stmts: D1PreparedStatement[] = [
      this.db.prepare(`DELETE FROM notebook_elements WHERE page_id = ?1 AND ${guard}`).bind(page.id, input.version),
    ];
    for (const e of input.elements) {
      stmts.push(
        this.db
          .prepare(
            `INSERT INTO notebook_elements (id, page_id, type, x, y, width, height, rotation, z, data_json, media_asset_id)
             SELECT ?3, ?1, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12 WHERE ${guard}`,
          )
          .bind(
            page.id,
            input.version,
            e.id,
            e.type,
            e.x,
            e.y,
            e.width,
            e.height,
            e.rotation,
            e.z,
            JSON.stringify(e.data),
            e.mediaAssetId ?? null,
          ),
      );
    }
    const f = (v: unknown) => (v === undefined ? null : v);
    stmts.push(
      this.db
        .prepare(
          `UPDATE notebooks SET updated_at = ?3 WHERE id = (SELECT notebook_id FROM notebook_pages WHERE id = ?1) AND ${guard}`,
        )
        .bind(page.id, input.version, now),
      // Última: sube la versión. Si no coincide, changes = 0.
      this.db
        .prepare(
          `UPDATE notebook_pages SET
             title = CASE WHEN ?4 = 1 THEN ?5 ELSE title END,
             page_date = CASE WHEN ?6 = 1 THEN ?7 ELSE page_date END,
             location_name = CASE WHEN ?8 = 1 THEN ?9 ELSE location_name END,
             latitude = CASE WHEN ?10 = 1 THEN ?11 ELSE latitude END,
             longitude = CASE WHEN ?10 = 1 THEN ?12 ELSE longitude END,
             location_source = CASE WHEN ?13 = 1 THEN ?14 ELSE location_source END,
             weather = CASE WHEN ?15 = 1 THEN ?16 ELSE weather END,
             paper = COALESCE(?17, paper),
             version = version + 1,
             updated_at = ?3
           WHERE id = ?1 AND version = ?2`,
        )
        .bind(
          page.id,
          input.version,
          now,
          input.title !== undefined ? 1 : 0,
          f(input.title),
          input.pageDate !== undefined ? 1 : 0,
          f(input.pageDate),
          input.locationName !== undefined ? 1 : 0,
          f(input.locationName),
          input.latitude !== undefined ? 1 : 0,
          f(input.latitude),
          f(input.longitude),
          input.locationSource !== undefined ? 1 : 0,
          f(input.locationSource),
          input.weather !== undefined ? 1 : 0,
          f(input.weather),
          f(input.paper),
        ),
    );
    const results = await this.db.batch(stmts);
    const last = results[results.length - 1];
    return last && last.meta.changes > 0 ? input.version + 1 : null;
  }

  async deletePage(page: { id: string; notebook_id: string }): Promise<void> {
    await this.db.batch([
      this.db.prepare(`DELETE FROM notebook_pages WHERE id = ?1`).bind(page.id),
      this.db
        .prepare(`UPDATE notebooks SET page_count = MAX(page_count - 1, 0), updated_at = ?2 WHERE id = ?1`)
        .bind(page.notebook_id, new Date().toISOString()),
    ]);
  }

  /** Reordena: `pageIds` debe contener exactamente las páginas del cuaderno. */
  async reorder(notebookId: string, pageIds: string[]): Promise<boolean> {
    const current = (await this.listPages(notebookId)).map((p) => p.id);
    if (current.length !== pageIds.length || new Set(pageIds).size !== pageIds.length || !pageIds.every((id) => current.includes(id))) {
      return false;
    }
    await this.db.batch(
      pageIds.map((id, i) => this.db.prepare(`UPDATE notebook_pages SET position = ?3 WHERE id = ?1 AND notebook_id = ?2`).bind(id, notebookId, i)),
    );
    return true;
  }

  /** Copia una página (con sus elementos) a continuación de la original. */
  async duplicatePage(page: PageRow, newId: string): Promise<void> {
    await this.db.batch([
      this.db.prepare(`UPDATE notebook_pages SET position = position + 1 WHERE notebook_id = ?1 AND position > ?2`).bind(page.notebook_id, page.position),
      this.db
        .prepare(
          `INSERT INTO notebook_pages (id, notebook_id, position, title, page_date, location_name, latitude, longitude, location_source, weather, paper)
           SELECT ?2, notebook_id, position + 1, title, page_date, location_name, latitude, longitude, location_source, weather, paper
           FROM notebook_pages WHERE id = ?1`,
        )
        .bind(page.id, newId),
      this.db
        .prepare(
          `INSERT INTO notebook_elements (id, page_id, type, x, y, width, height, rotation, z, data_json, media_asset_id)
           SELECT id, ?2, type, x, y, width, height, rotation, z, data_json, media_asset_id FROM notebook_elements WHERE page_id = ?1`,
        )
        .bind(page.id, newId),
      this.db.prepare(`UPDATE notebooks SET page_count = page_count + 1, updated_at = ?2 WHERE id = ?1`).bind(page.notebook_id, new Date().toISOString()),
    ]);
  }

  /** Copia un cuaderno completo (privado) para la misma persona. */
  async duplicateNotebook(source: NotebookRow, newId: string, ownerId: string): Promise<void> {
    const pages = await this.listPages(source.id);
    const stmts: D1PreparedStatement[] = [
      this.db
        .prepare(
          `INSERT INTO notebooks (id, owner_id, title, description, color, cover_asset_id, visibility, page_count)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'private', ?7)`,
        )
        .bind(newId, ownerId, `${source.title} (copia)`.slice(0, 120), source.description, source.color, source.cover_asset_id, pages.length),
    ];
    for (const p of pages) {
      const pid = crypto.randomUUID();
      stmts.push(
        this.db
          .prepare(
            `INSERT INTO notebook_pages (id, notebook_id, position, title, page_date, location_name, latitude, longitude, location_source, weather, paper)
             SELECT ?2, ?3, position, title, page_date, location_name, latitude, longitude, location_source, weather, paper FROM notebook_pages WHERE id = ?1`,
          )
          .bind(p.id, pid, newId),
        this.db
          .prepare(
            `INSERT INTO notebook_elements (id, page_id, type, x, y, width, height, rotation, z, data_json, media_asset_id)
             SELECT id, ?2, type, x, y, width, height, rotation, z, data_json, media_asset_id FROM notebook_elements WHERE page_id = ?1`,
          )
          .bind(p.id, pid),
      );
    }
    await this.db.batch(stmts);
  }
}
