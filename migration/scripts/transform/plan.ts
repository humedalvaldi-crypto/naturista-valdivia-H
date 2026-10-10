import { MAX_STATEMENT_BYTES } from './sql';
import { assetIdForInline, assetIdForStorage, parseDataUrl, storagePathFromUrl, type MediaEntry, type MediaPurpose } from './media';

/** Etapas en orden de aplicación (respetan las claves foráneas). */
export const STAGES = [
  '010-users',
  '020-user-settings',
  '030-species',
  '040-profiles',
  '050-communities',
  '060-community-members',
  '070-follows',
  '080-posts',
  '090-notebooks',
  '100-notebook-pages',
  '110-notebook-elements',
  '120-observations',
  '130-conversations',
  '140-messages',
  '150-places',
  '900-recount',
  '910-relink-media',
] as const;
export type Stage = (typeof STAGES)[number];

export interface CollectionStats {
  read: number;
  written: Record<string, number>;
  skipped: Record<string, number>;
  unmappedFields: Record<string, number>;
  excludedPersonalFields: Record<string, number>;
  notes: string[];
}

export interface InlineFile {
  name: string;
  bytes: Buffer;
}

/** Resultado de la transformación: SQL por etapa, manifiesto de archivos e informe. */
export class Plan {
  readonly statements = new Map<Stage, string[]>(STAGES.map((s) => [s, []]));
  readonly media = new Map<string, MediaEntry>();
  readonly inline: InlineFile[] = [];
  readonly stats = new Map<string, CollectionStats>();
  readonly externalUrls = new Map<string, number>();
  /** (tabla, clave, columna, archivo): para enlazar archivos copiados después del contenido. */
  readonly relinks: { table: string; where: Record<string, string>; column: string; assetId: string }[] = [];

  collection(name: string): CollectionStats {
    let s = this.stats.get(name);
    if (!s) {
      s = { read: 0, written: {}, skipped: {}, unmappedFields: {}, excludedPersonalFields: {}, notes: [] };
      this.stats.set(name, s);
    }
    return s;
  }

  add(stage: Stage, collection: string, table: string, sql: string): boolean {
    const s = this.collection(collection);
    if (Buffer.byteLength(sql) > MAX_STATEMENT_BYTES) {
      this.skip(collection, `fila demasiado grande para D1 (${table})`);
      return false;
    }
    this.statements.get(stage)!.push(sql);
    s.written[table] = (s.written[table] ?? 0) + 1;
    return true;
  }

  skip(collection: string, reason: string) {
    const s = this.collection(collection);
    s.skipped[reason] = (s.skipped[reason] ?? 0) + 1;
  }

  unmapped(collection: string, fields: string[]) {
    const s = this.collection(collection);
    for (const f of fields) s.unmappedFields[f] = (s.unmappedFields[f] ?? 0) + 1;
  }

  excluded(collection: string, field: string) {
    const s = this.collection(collection);
    s.excludedPersonalFields[field] = (s.excludedPersonalFields[field] ?? 0) + 1;
  }

  /**
   * Registra un archivo referenciado (URL de Storage o imagen Base64 incrustada)
   * y devuelve el ID del futuro `media_assets`, o null si no se puede migrar.
   */
  mediaFrom(
    value: string | null,
    o: { ownerId: string; purpose: MediaPurpose; visibility: 'public' | 'private'; collection: string; docId: string; field: string },
  ): string | null {
    if (!value) return null;
    if (value.startsWith('data:')) {
      const parsed = parseDataUrl(value);
      if (!parsed || parsed.bytes.length === 0) {
        this.skip(o.collection, `imagen incrustada no válida (${o.field})`);
        return null;
      }
      const assetId = assetIdForInline(o.collection, o.docId, o.field);
      if (!this.media.has(assetId)) {
        const ext = parsed.contentType.split('/')[1]!.replace('jpeg', 'jpg');
        const name = `${assetId}.${ext}`;
        this.inline.push({ name, bytes: parsed.bytes });
        this.media.set(assetId, {
          assetId,
          ownerId: o.ownerId,
          purpose: o.purpose,
          visibility: o.visibility,
          source: { kind: 'inline', file: name, contentType: parsed.contentType },
          legacyStoragePath: null,
          legacyAssetId: null,
        });
      }
      return assetId;
    }
    const path = storagePathFromUrl(value);
    if (!path) {
      let host = 'desconocido';
      try {
        host = new URL(value).hostname;
      } catch {
        /* no es URL */
      }
      this.externalUrls.set(host, (this.externalUrls.get(host) ?? 0) + 1);
      this.skip(o.collection, `archivo fuera de Firebase Storage (${o.field})`);
      return null;
    }
    return this.mediaFromStoragePath(path, o.ownerId, o.purpose, o.visibility, null);
  }

  mediaFromStoragePath(path: string, ownerId: string, purpose: MediaPurpose, visibility: 'public' | 'private', legacyAssetId: string | null) {
    const assetId = assetIdForStorage(path);
    const prev = this.media.get(assetId);
    if (prev) {
      // Si alguien lo usa en algo público, el archivo es público.
      if (visibility === 'public') prev.visibility = 'public';
      if (legacyAssetId && !prev.legacyAssetId) prev.legacyAssetId = legacyAssetId;
      return assetId;
    }
    this.media.set(assetId, {
      assetId,
      ownerId,
      purpose,
      visibility,
      source: { kind: 'storage', path },
      legacyStoragePath: path,
      legacyAssetId,
    });
    return assetId;
  }
}
