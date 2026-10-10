import { decodeDate, decodeGeo } from '../lib/encode';

export type Doc = Record<string, unknown>;

/** Lectura tolerante de campos: acepta varios nombres posibles y registra cuáles se usaron. */
export class FieldReader {
  readonly used = new Set<string>();

  constructor(readonly data: Doc) {}

  private raw(names: string[]): unknown {
    for (const n of names) {
      const v = this.data[n];
      this.used.add(n);
      if (v !== undefined && v !== null && v !== '') return v;
    }
    return undefined;
  }

  /** Marca campos como conocidos aunque no se lean (p. ej. contadores que se recalculan). */
  known(...names: string[]) {
    for (const n of names) this.used.add(n);
  }

  str(...names: string[]): string | null {
    const v = this.raw(names);
    if (typeof v === 'string') return v.trim() || null;
    if (typeof v === 'number') return String(v);
    return null;
  }

  num(...names: string[]): number | null {
    const v = this.raw(names);
    if (typeof v === 'number' && Number.isFinite(v)) return v;
    if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
    return null;
  }

  bool(...names: string[]): boolean | null {
    const v = this.raw(names);
    if (typeof v === 'boolean') return v;
    if (v === 'true' || v === 1) return true;
    if (v === 'false' || v === 0) return false;
    return null;
  }

  date(...names: string[]): string | null {
    return decodeDate(this.raw(names));
  }

  obj(...names: string[]): Doc | null {
    const v = this.raw(names);
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Doc) : null;
  }

  /** Coordenadas: campos lat/lng separados o un GeoPoint/objeto {lat,lng}. */
  coords(latNames: string[], lngNames: string[], pointNames: string[]): { lat: number; lng: number } | null {
    const lat = this.num(...latNames);
    const lng = this.num(...lngNames);
    if (lat !== null && lng !== null) return valid(lat, lng);
    const p = this.raw(pointNames);
    const geo = decodeGeo(p);
    if (geo) return valid(geo.lat, geo.lng);
    if (p && typeof p === 'object') {
      const o = p as Doc;
      const a = typeof o['lat'] === 'number' ? o['lat'] : o['latitude'];
      const b = typeof o['lng'] === 'number' ? o['lng'] : typeof o['lon'] === 'number' ? o['lon'] : o['longitude'];
      if (typeof a === 'number' && typeof b === 'number') return valid(a, b);
    }
    return null;
  }

  /** Campos del documento que ningún mapeo leyó. */
  unused(): string[] {
    return Object.keys(this.data).filter((k) => !this.used.has(k));
  }
}

function valid(lat: number, lng: number) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  if (lat === 0 && lng === 0) return null; // "sin ubicación" en muchos formularios
  return { lat, lng };
}

export const truncate = (s: string | null, max: number): string | null => (s === null ? null : [...s].slice(0, max).join(''));

export function slugify(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');
}

/** Nombre de usuario válido según la API (3–30, minúsculas, números, punto, guion bajo), o null. */
export function cleanUsername(v: string | null): string | null {
  if (!v) return null;
  const u = v
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/^@/, '')
    .replace(/[^a-z0-9._]/g, '');
  return /^[a-z0-9](?:[a-z0-9._]{1,28})[a-z0-9]$/.test(u) && !/[._]{2}/.test(u) ? u : null;
}

export const isHexColor = (v: string | null): v is string => !!v && /^#[0-9A-Fa-f]{6}$/.test(v);
