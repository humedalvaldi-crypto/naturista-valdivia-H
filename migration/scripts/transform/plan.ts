import { MAX_STATEMENT_BYTES } from './sql';
import { allowedExternalImage, assetIdForInline, assetIdForStorage, assetIdForUrl, parseDataUrl, storagePathFromUrl, type MediaEntry, type MediaPurpose } from './media';

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
  '125-species-unlocks',
  '130-conversations',
  '140-messages',
  '150-places',
  '890-respect-deletions',
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
  /** Forma (solo nombres de campos y tipos, nunca valores) de campos sin mapear que son objetos o listas. */
  unmappedShapes: Record<string, string[]>;
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
      s = { read: 0, written: {}, skipped: {}, unmappedFields: {}, excludedPersonalFields: {}, unmappedShapes: {}, notes: [] };
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

  /** Registra la forma de un valor sin mapear (tipos y nombres de campos, sin contenido). */
  shape(collection: string, field: string, value: unknown) {
    const sig = shapeOf(value, 0);
    if (!sig.startsWith('{') && !sig.startsWith('[')) return;
    const s = this.collection(collection);
    const list = (s.unmappedShapes[field] ??= []);
    if (!list.includes(sig) && list.length < 5) list.push(sig);
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
        const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'audio/webm': 'webm', 'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a' }[parsed.contentType] ?? 'bin';
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
    if (!path && allowedExternalImage(value)) {
      const assetId = assetIdForUrl(value);
      const prev = this.media.get(assetId);
      if (prev) {
        if (o.visibility === 'public') prev.visibility = 'public';
      } else {
        this.media.set(assetId, {
          assetId, ownerId: o.ownerId, purpose: o.purpose, visibility: o.visibility,
          source: { kind: 'url', url: value }, legacyStoragePath: null, legacyAssetId: null,
        });
      }
      return assetId;
    }
    if (!path) {
      let host: string;
      try {
        const u = new URL(value);
        host = u.hostname || `${u.protocol} (enlace temporal del navegador)`;
      } catch {
        // No es una URL: se clasifica por su forma, sin guardar el contenido.
        host = value.startsWith('/')
          ? 'ruta relativa de la app antigua'
          : /^[\w-]{8,64}$/.test(value)
            ? 'identificador de archivo (proveedor antiguo)'
            : /^[A-Za-z0-9+/=\s]{200,}$/.test(value)
              ? 'imagen en base64 sin encabezado'
              : 'texto que no es URL';
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

/** Firma de tipos de un valor: `{a: texto, b: [ {x: número} ]}`. Nunca incluye valores. */
export function shapeOf(v: unknown, depth: number): string {
  if (v === null || v === undefined) return 'nulo';
  if (typeof v === 'string') return v.startsWith('data:image') ? 'imagen-base64' : /^https?:\/\//.test(v) ? 'url' : 'texto';
  if (typeof v === 'number') return 'número';
  if (typeof v === 'boolean') return 'sí/no';
  if (Array.isArray(v)) {
    if (depth > 3) return '[…]';
    const kinds = [...new Set(v.slice(0, 20).map((x) => shapeOf(x, depth + 1)))].slice(0, 3);
    return `[${kinds.join(' | ')}]`;
  }
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if ('$ts' in o) return 'fecha';
    if ('$geo' in o) return 'geopunto';
    if (depth > 3) return '{…}';
    const keys = Object.keys(o).sort().slice(0, 25);
    return `{${keys.map((k) => `${k}: ${shapeOf(o[k], depth + 1)}`).join(', ')}}`;
  }
  return typeof v;
}
