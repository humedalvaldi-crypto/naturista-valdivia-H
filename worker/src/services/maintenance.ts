import { MediaRepository } from '../repositories/media';
import type { Env } from '../types/env';
import { deleteMedia, mediaStore } from './media-store';

export interface PurgeReport {
  purgedDeleted: number;
  orphansRemoved: number;
  orphanScanTruncated: boolean;
}

/** Objetos sin fila en D1 más antiguos que esto se consideran huérfanos. */
export const ORPHAN_GRACE_MS = 24 * 60 * 60 * 1000;

/**
 * Barrido programado (cron diario):
 * 1. Elimina los bytes (R2 o D1) de archivos marcados como borrados.
 * 2. Elimina objetos bajo `u/` que no tienen fila en `media_assets` y
 *    llevan más de 24 h (p. ej. una subida que falló a medias).
 */
export async function purgeMedia(env: Env, now = Date.now(), batch = 200): Promise<PurgeReport> {
  const repo = new MediaRepository(env.DB);
  let purgedDeleted = 0;
  for (const row of await repo.pendingPurge(batch)) {
    await deleteMedia(env, row.object_key);
    await repo.markPurged(row.id);
    purgedDeleted++;
  }

  const store = mediaStore(env);
  const { keys, truncated } = await store.orphans(new Date(now - ORPHAN_GRACE_MS), batch);
  for (const key of keys) await store.delete(key);
  return { purgedDeleted, orphansRemoved: keys.length, orphanScanTruncated: truncated };
}
