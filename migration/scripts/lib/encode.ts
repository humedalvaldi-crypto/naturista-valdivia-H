/**
 * Conversión de valores de Firestore a JSON estable para la instantánea local.
 * Marcadores: {"$ts": ISO}, {"$geo": [lat, lng]}, {"$ref": "col/doc"}, {"$bytes": base64}.
 * Se reconocen por su forma (sin importar firebase-admin), así se pueden probar.
 */
export type Encoded = null | boolean | number | string | Encoded[] | { [k: string]: Encoded };

interface TimestampLike {
  toDate(): Date;
}
interface GeoPointLike {
  latitude: number;
  longitude: number;
}
interface RefLike {
  path: string;
  firestore: unknown;
}

const isTimestamp = (v: object): v is TimestampLike => typeof (v as TimestampLike).toDate === 'function';
const isGeoPoint = (v: object): v is GeoPointLike =>
  typeof (v as GeoPointLike).latitude === 'number' && typeof (v as GeoPointLike).longitude === 'number' && Object.keys(v).length <= 2;
const isRef = (v: object): v is RefLike => typeof (v as RefLike).path === 'string' && 'firestore' in v;

export function encodeValue(v: unknown): Encoded {
  if (v === null || v === undefined) return null;
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'bigint') return Number(v);
  if (v instanceof Date) return { $ts: v.toISOString() };
  if (v instanceof Uint8Array) return { $bytes: Buffer.from(v).toString('base64') };
  if (Array.isArray(v)) return v.map(encodeValue);
  if (typeof v === 'object') {
    if (isTimestamp(v)) return { $ts: v.toDate().toISOString() };
    if (isRef(v)) return { $ref: v.path };
    if (isGeoPoint(v)) return { $geo: [v.latitude, v.longitude] };
    const out: Record<string, Encoded> = {};
    for (const [k, inner] of Object.entries(v)) out[k] = encodeValue(inner);
    return out;
  }
  return null;
}

/** Fecha ISO desde un valor codificado (marcador $ts, ISO, milisegundos o segundos). */
export function decodeDate(v: unknown): string | null {
  if (v && typeof v === 'object' && '$ts' in v && typeof (v as { $ts: unknown }).$ts === 'string') return (v as { $ts: string }).$ts;
  if (v && typeof v === 'object' && 'seconds' in v && typeof (v as { seconds: unknown }).seconds === 'number') {
    return new Date((v as { seconds: number }).seconds * 1000).toISOString();
  }
  if (typeof v === 'string') {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : new Date(t).toISOString();
  }
  if (typeof v === 'number' && Number.isFinite(v)) {
    const ms = v < 1e12 ? v * 1000 : v; // segundos o milisegundos
    return new Date(ms).toISOString();
  }
  return null;
}

export function decodeGeo(v: unknown): { lat: number; lng: number } | null {
  if (v && typeof v === 'object' && '$geo' in v) {
    const g = (v as { $geo: unknown }).$geo;
    if (Array.isArray(g) && typeof g[0] === 'number' && typeof g[1] === 'number') return { lat: g[0], lng: g[1] };
  }
  return null;
}
