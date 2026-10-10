import type { SpeciesRow } from './observations';

export interface AlbumRow extends SpeciesRow {
  first_seen: string | null;
  observation_count: number;
  legacy_unlocked_at: string | null;
}

export interface AlbumCounts {
  observations: number;
  species: number;
  groups: number;
  threatened: number;
  notebooks: number;
  pages: number;
  followers: number;
  legacy: number;
}

/**
 * Álbum y logros de una persona. `self` = la propia persona: cuenta también
 * lo privado. Para terceros solo cuenta lo público (observaciones públicas,
 * cuadernos públicos), así el álbum no revela lo que alguien guardó en privado.
 */
export class AlbumRepository {
  constructor(private readonly db: D1Database) {}

  private obsFilter(self: boolean) {
    return `o.owner_id = ?1 AND o.deleted_at IS NULL${self ? '' : " AND o.visibility = 'public'"}`;
  }

  async album(userId: string, self: boolean): Promise<AlbumRow[]> {
    const rows = await this.db
      .prepare(
        `SELECT s.*,
                (SELECT min(o.observed_at) FROM observations o WHERE o.species_id = s.id AND ${this.obsFilter(self)}) AS first_seen,
                (SELECT count(*) FROM observations o WHERE o.species_id = s.id AND ${this.obsFilter(self)}) AS observation_count,
                (SELECT u.unlocked_at FROM species_unlocks u WHERE u.species_id = s.id AND u.user_id = ?1) AS legacy_unlocked_at
         FROM species s
         ORDER BY s.taxon_group, COALESCE(s.common_name_es, s.scientific_name) COLLATE NOCASE`,
      )
      .bind(userId)
      .all<AlbumRow>();
    return rows.results;
  }

  async counts(userId: string, self: boolean): Promise<AlbumCounts> {
    const nbFilter = `owner_id = ?1 AND deleted_at IS NULL${self ? '' : " AND visibility = 'public'"}`;
    const row = await this.db
      .prepare(
        `SELECT
           (SELECT count(*) FROM observations o WHERE ${this.obsFilter(self)}) AS observations,
           (SELECT count(*) FROM (
              SELECT o.species_id AS sid FROM observations o WHERE ${this.obsFilter(self)} AND o.species_id IS NOT NULL
              UNION SELECT species_id FROM species_unlocks WHERE user_id = ?1)) AS species,
           (SELECT count(DISTINCT s.taxon_group) FROM species s WHERE s.id IN (
              SELECT o.species_id FROM observations o WHERE ${this.obsFilter(self)}
              UNION SELECT species_id FROM species_unlocks WHERE user_id = ?1)) AS groups,
           (SELECT count(DISTINCT o.species_id) FROM observations o JOIN species s ON s.id = o.species_id
              WHERE ${this.obsFilter(self)} AND s.conservation_status IN ('VU', 'EN', 'CR')) AS threatened,
           (SELECT count(*) FROM notebooks WHERE ${nbFilter}) AS notebooks,
           (SELECT count(*) FROM notebook_pages p JOIN notebooks n ON n.id = p.notebook_id
              WHERE n.owner_id = ?1 AND n.deleted_at IS NULL${self ? '' : " AND n.visibility = 'public'"}) AS pages,
           (SELECT count(*) FROM follows WHERE followed_id = ?1) AS followers,
           (SELECT count(*) FROM species_unlocks WHERE user_id = ?1) AS legacy`,
      )
      .bind(userId)
      .first<AlbumCounts>();
    return row!;
  }
}

/** Logros: identificador estable, meta y valor actual. Los textos los pone la app (es/en). */
export const ACHIEVEMENTS: { id: string; target: number; metric: keyof AlbumCounts }[] = [
  { id: 'first-observation', target: 1, metric: 'observations' },
  { id: 'observations-10', target: 10, metric: 'observations' },
  { id: 'species-5', target: 5, metric: 'species' },
  { id: 'species-15', target: 15, metric: 'species' },
  { id: 'groups-3', target: 3, metric: 'groups' },
  { id: 'threatened-species', target: 1, metric: 'threatened' },
  { id: 'first-notebook', target: 1, metric: 'notebooks' },
  { id: 'pages-10', target: 10, metric: 'pages' },
  { id: 'followers-5', target: 5, metric: 'followers' },
  { id: 'pioneer', target: 1, metric: 'legacy' },
];
