import { MediaRepository } from '../repositories/media';
import type { Env } from '../types/env';

export interface PurgeReport {
  purgedDeleted: number;
  orphansRemoved: number;
  orphanScanTruncated: boolean;
}

/** Objetos sin fila en D1 más antiguos que esto se consideran huérfanos. */
export const ORPHAN_GRACE_MS = 24 * 60 * 60 * 1000;

/**
 * Barrido programado (cron diario):
 * 1. Elimina de R2 los objetos de archivos marcados como borrados.
 * 2. Elimina objetos bajo `u/` que no tienen fila en `media_assets` y
 *    llevan más de 24 h (p. ej. una subida que falló a medias).
 */
export async function purgeMedia(env: Env, now = Date.now(), batch = 200): Promise<PurgeReport> {
  const repo = new MediaRepository(env.DB);
  let purgedDeleted = 0;
  for (const row of await repo.pendingPurge(batch)) {
    await env.MEDIA.delete(row.object_key);
    await repo.markPurged(row.id);
    purgedDeleted++;
  }

  let orphansRemoved = 0;
  const listing = await env.MEDIA.list({ prefix: 'u/', limit: batch });
  const old = listing.objects.filter((o) => now - o.uploaded.getTime() > ORPHAN_GRACE_MS);
  const known = await repo.existingKeys(old.map((o) => o.key));
  for (const o of old) {
    if (!known.has(o.key)) {
      await env.MEDIA.delete(o.key);
      orphansRemoved++;
    }
  }
  return { purgedDeleted, orphansRemoved, orphanScanTruncated: listing.truncated };
}
