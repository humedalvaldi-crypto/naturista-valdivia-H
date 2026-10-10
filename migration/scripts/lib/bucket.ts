import { getStorage } from 'firebase-admin/storage';

/**
 * Bucket de Firebase Storage del proyecto. Los proyectos nuevos usan
 * `<id>.firebasestorage.app` y los antiguos `<id>.appspot.com`: se prueba
 * cuál existe listando un archivo (solo lectura).
 */
export async function resolveBucket(projectId: string, explicit?: string) {
  const candidates = explicit ? [explicit] : [`${projectId}.firebasestorage.app`, `${projectId}.appspot.com`];
  for (const name of candidates) {
    const bucket = getStorage().bucket(name);
    try {
      await bucket.getFiles({ maxResults: 1, autoPaginate: false });
      return bucket;
    } catch (err) {
      const code = (err as { code?: number }).code;
      if (code !== 404 && candidates.length === 1) throw err;
    }
  }
  throw new Error(`No se encontró el bucket de Storage (${candidates.join(' ni ')}). Indícalo con --bucket.`);
}
