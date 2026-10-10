import { createHash } from 'node:crypto';

/**
 * UUID determinista (estilo v5, SHA-1) a partir de un nombre estable como
 * `observations/<idFirestore>`. Repetir la transformación produce los mismos
 * IDs, así una segunda ejecución no duplica nada.
 */
const NAMESPACE = 'naturista-valdivia/firestore-migration/v1';

export function stableId(name: string): string {
  const h = createHash('sha1').update(`${NAMESPACE}:${name}`).digest();
  h[6] = (h[6]! & 0x0f) | 0x50; // versión 5
  h[8] = (h[8]! & 0x3f) | 0x80; // variante RFC 4122
  const hex = h.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}
