import { getStorage } from 'firebase-admin/storage';

export class BucketUnavailable extends Error {
  constructor(readonly attempts: string[]) {
    super(`No se pudo acceder a Firebase Storage (${attempts.join('; ')}).`);
  }
}

/**
 * Bucket de Firebase Storage del proyecto. Los proyectos nuevos usan
 * `<id>.firebasestorage.app` y los antiguos `<id>.appspot.com`: se prueba
 * cuál responde listando un archivo (solo lectura).
 */
export async function resolveBucket(projectId: string, explicit?: string) {
  const candidates = explicit ? [explicit] : [`${projectId}.firebasestorage.app`, `${projectId}.appspot.com`];
  const attempts: string[] = [];
  for (const name of candidates) {
    const bucket = getStorage().bucket(name);
    try {
      await bucket.getFiles({ maxResults: 1, autoPaginate: false });
      return bucket;
    } catch (err) {
      const e = err as { code?: number | string; message?: string };
      const why = e.code === 404 ? 'no existe' : e.code === 403 ? 'sin permiso (falta el rol Storage Object Viewer)' : `error ${e.code ?? '?'}`;
      attempts.push(`${name}: ${why}`);
    }
  }
  throw new BucketUnavailable(attempts);
}
