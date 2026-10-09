/**
 * Inferencia de esquema a partir de documentos de Firestore.
 *
 * PRIVACIDAD: solo se registran nombres de campo, tipos y conteos.
 * Nunca se copian valores al informe (hay RUT, teléfonos y fechas de
 * nacimiento en `profiles`).
 */

export type FieldType =
  | 'null'
  | 'string'
  | 'number'
  | 'boolean'
  | 'timestamp'
  | 'geopoint'
  | 'reference'
  | 'bytes'
  | 'array'
  | 'map';

export interface FieldStats {
  /** Número de documentos donde el campo aparece. */
  present: number;
  types: Partial<Record<FieldType, number>>;
  /** Cadenas que son URLs de Firebase Storage (requieren migración a R2). */
  storageUrls: number;
  /** Cadenas `data:` en Base64 (imágenes incrustadas: riesgo de tamaño). */
  dataUrls: number;
  /** Longitud máxima de cadena observada (para dimensionar columnas). */
  maxStringLength: number;
}

export interface CollectionSchema {
  sampled: number;
  fields: Record<string, FieldStats>;
}

const STORAGE_URL = /^https:\/\/(firebasestorage\.googleapis\.com|storage\.googleapis\.com)\//;

export function inferFieldType(value: unknown): FieldType {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'string') return 'string';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'boolean') return 'boolean';
  if (Array.isArray(value)) return 'array';
  if (value instanceof Uint8Array || (typeof Buffer !== 'undefined' && Buffer.isBuffer(value))) return 'bytes';
  if (typeof value === 'object') {
    const v = value as Record<string, unknown>;
    if (typeof v['toDate'] === 'function' && typeof v['seconds'] === 'number') return 'timestamp';
    if (value instanceof Date) return 'timestamp';
    if (typeof v['latitude'] === 'number' && typeof v['longitude'] === 'number' && typeof v['isEqual'] === 'function') {
      return 'geopoint';
    }
    if (typeof v['path'] === 'string' && typeof v['id'] === 'string' && 'firestore' in v) return 'reference';
    return 'map';
  }
  return 'map';
}

function emptyStats(): FieldStats {
  return { present: 0, types: {}, storageUrls: 0, dataUrls: 0, maxStringLength: 0 };
}

/**
 * Recorre los campos (los mapas anidados se aplanan con `.`; los arrays no se
 * expanden). `maxDepth` evita recursión ilimitada.
 */
export function inferSchema(docs: Iterable<Record<string, unknown>>, maxDepth = 3): CollectionSchema {
  const fields: Record<string, FieldStats> = {};
  let sampled = 0;

  const visit = (obj: Record<string, unknown>, prefix: string, depth: number) => {
    for (const [key, value] of Object.entries(obj)) {
      const path = prefix ? `${prefix}.${key}` : key;
      const stats = (fields[path] ??= emptyStats());
      const type = inferFieldType(value);
      stats.present += 1;
      stats.types[type] = (stats.types[type] ?? 0) + 1;
      if (type === 'string') {
        const s = value as string;
        stats.maxStringLength = Math.max(stats.maxStringLength, s.length);
        if (STORAGE_URL.test(s)) stats.storageUrls += 1;
        if (s.startsWith('data:')) stats.dataUrls += 1;
      }
      if (type === 'map' && depth < maxDepth) {
        visit(value as Record<string, unknown>, path, depth + 1);
      }
    }
  };

  for (const doc of docs) {
    sampled += 1;
    visit(doc, '', 1);
  }
  return { sampled, fields };
}

/** Campos presentes en menos documentos que los muestreados (opcionales o inconsistentes). */
export function optionalFields(schema: CollectionSchema): string[] {
  return Object.entries(schema.fields)
    .filter(([, s]) => s.present < schema.sampled)
    .map(([k]) => k)
    .sort();
}

/** Campos con más de un tipo (p. ej. `createdAt` como Timestamp y como Date/string). */
export function mixedTypeFields(schema: CollectionSchema): string[] {
  return Object.entries(schema.fields)
    .filter(([, s]) => Object.keys(s.types).filter((t) => t !== 'null').length > 1)
    .map(([k]) => k)
    .sort();
}
