import type { Env } from '../types/env';

/**
 * Dónde viven los bytes de los archivos. Con R2 (si la cuenta lo tiene
 * activado) o, sin R2, en la propia base D1 en trozos: así la app funciona
 * en el plan gratuito de Cloudflare sin registrar un medio de pago.
 */
export interface MediaStore {
  readonly kind: 'r2' | 'd1';
  put(key: string, bytes: Uint8Array, meta: { contentType: string; owner: string; assetId: string; sha256: string }): Promise<void>;
  get(key: string): Promise<ReadableStream | Uint8Array | null>;
  delete(key: string): Promise<void>;
  /** Claves bajo `u/` sin fila en media_assets y anteriores a `before` (huérfanas). */
  orphans(before: Date, limit: number): Promise<{ keys: string[]; truncated: boolean }>;
}

/** Tamaño de cada trozo en D1 (por debajo del máximo de ~2 MB por valor). */
export const D1_CHUNK_BYTES = 1024 * 1024;

class R2Store implements MediaStore {
  readonly kind = 'r2' as const;
  constructor(
    private readonly bucket: R2Bucket,
    private readonly db: D1Database,
  ) {}

  async put(key: string, bytes: Uint8Array, meta: { contentType: string; owner: string; assetId: string; sha256: string }) {
    await this.bucket.put(key, bytes, {
      httpMetadata: { contentType: meta.contentType },
      customMetadata: { owner: meta.owner, assetId: meta.assetId },
      sha256: meta.sha256,
    });
  }

  async get(key: string) {
    const o = await this.bucket.get(key);
    return o ? o.body : null;
  }

  async delete(key: string) {
    await this.bucket.delete(key);
  }

  async orphans(before: Date, limit: number) {
    const listing = await this.bucket.list({ prefix: 'u/', limit });
    const old = listing.objects.filter((o) => o.uploaded.getTime() < before.getTime()).map((o) => o.key);
    if (old.length === 0) return { keys: [], truncated: listing.truncated };
    const ph = old.map((_, i) => `?${i + 1}`).join(', ');
    const known = await this.db.prepare(`SELECT object_key FROM media_assets WHERE object_key IN (${ph})`).bind(...old).all<{ object_key: string }>();
    const set = new Set(known.results.map((r) => r.object_key));
    return { keys: old.filter((k) => !set.has(k)), truncated: listing.truncated };
  }
}

class D1Store implements MediaStore {
  readonly kind = 'd1' as const;
  constructor(private readonly db: D1Database) {}

  async put(key: string, bytes: Uint8Array) {
    const statements: D1PreparedStatement[] = [this.db.prepare('DELETE FROM media_chunks WHERE object_key = ?1').bind(key)];
    for (let i = 0, part = 0; i < bytes.byteLength; i += D1_CHUNK_BYTES, part++) {
      statements.push(
        this.db.prepare('INSERT INTO media_chunks (object_key, part, bytes) VALUES (?1, ?2, ?3)').bind(key, part, bytes.slice(i, i + D1_CHUNK_BYTES)),
      );
    }
    await this.db.batch(statements); // atómico: o se guardan todos los trozos o ninguno
  }

  async get(key: string) {
    const rows = await this.db
      .prepare('SELECT bytes FROM media_chunks WHERE object_key = ?1 ORDER BY part')
      .bind(key)
      .all<{ bytes: ArrayBuffer | number[] }>();
    if (rows.results.length === 0) return null;
    const parts = rows.results.map((r) => (r.bytes instanceof ArrayBuffer ? new Uint8Array(r.bytes) : Uint8Array.from(r.bytes)));
    const out = new Uint8Array(parts.reduce((n, p) => n + p.byteLength, 0));
    let o = 0;
    for (const p of parts) {
      out.set(p, o);
      o += p.byteLength;
    }
    return out;
  }

  async delete(key: string) {
    await this.db.prepare('DELETE FROM media_chunks WHERE object_key = ?1').bind(key).run();
  }

  async orphans(before: Date, limit: number) {
    const rows = await this.db
      .prepare(
        `SELECT DISTINCT c.object_key FROM media_chunks c
         WHERE c.object_key LIKE 'u/%' AND c.created_at < ?1
           AND NOT EXISTS (SELECT 1 FROM media_assets m WHERE m.object_key = c.object_key)
         LIMIT ?2`,
      )
      .bind(before.toISOString(), limit + 1)
      .all<{ object_key: string }>();
    const keys = rows.results.map((r) => r.object_key);
    return { keys: keys.slice(0, limit), truncated: keys.length > limit };
  }
}

/** R2 si está configurado; si no, D1. */
export function mediaStore(env: Env): MediaStore {
  return env.MEDIA ? new R2Store(env.MEDIA, env.DB) : new D1Store(env.DB);
}

/** Lectura que prueba ambos: un archivo guardado en D1 sigue sirviéndose aunque después se active R2. */
export async function readMedia(env: Env, key: string): Promise<ReadableStream | Uint8Array | null> {
  const primary = await mediaStore(env).get(key);
  if (primary || !env.MEDIA) return primary;
  return new D1Store(env.DB).get(key);
}

/** Borrado en ambos almacenes (idempotente). */
export async function deleteMedia(env: Env, key: string): Promise<void> {
  if (env.MEDIA) await env.MEDIA.delete(key);
  await new D1Store(env.DB).delete(key);
}
