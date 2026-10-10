import { stableId } from './ids';

export type MediaPurpose =
  | 'observation-photo'
  | 'notebook-photo'
  | 'notebook-audio'
  | 'profile-photo'
  | 'profile-banner'
  | 'community-photo'
  | 'post-photo'
  | 'map-place-photo';

export type MediaSource = { kind: 'storage'; path: string } | { kind: 'inline'; file: string; contentType: string };

export interface MediaEntry {
  assetId: string;
  ownerId: string;
  purpose: MediaPurpose;
  visibility: 'public' | 'private';
  source: MediaSource;
  legacyStoragePath: string | null;
  legacyAssetId: string | null;
}

/** Ruta en Firebase Storage desde una URL de descarga, una URL gs:// o una ruta directa. */
export function storagePathFromUrl(url: string): string | null {
  try {
    if (url.startsWith('gs://')) return url.replace(/^gs:\/\/[^/]+\//, '') || null;
    if (url.startsWith('user-files/')) return url;
    const u = new URL(url);
    if (u.hostname === 'firebasestorage.googleapis.com') {
      const m = u.pathname.match(/\/v0\/b\/[^/]+\/o\/(.+)$/);
      return m ? decodeURIComponent(m[1]!) : null;
    }
    if (u.hostname === 'storage.googleapis.com') {
      const parts = u.pathname.split('/').filter(Boolean);
      return parts.length > 1 ? decodeURIComponent(parts.slice(1).join('/')) : null;
    }
  } catch {
    return null;
  }
  return null;
}

const DATA_URL = /^data:(image\/(?:png|jpeg|jpg|webp));base64,([A-Za-z0-9+/=\s]+)$/;

export function parseDataUrl(v: string): { contentType: string; bytes: Buffer } | null {
  const m = v.match(DATA_URL);
  if (!m) return null;
  return { contentType: m[1] === 'image/jpg' ? 'image/jpeg' : m[1]!, bytes: Buffer.from(m[2]!.replace(/\s/g, ''), 'base64') };
}

export const assetIdForStorage = (path: string) => stableId(`storage/${path}`);
export const assetIdForInline = (collection: string, docId: string, field: string) => stableId(`inline/${collection}/${docId}/${field}`);
