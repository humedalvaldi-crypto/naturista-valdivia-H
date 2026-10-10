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

export type MediaSource =
  | { kind: 'storage'; path: string }
  | { kind: 'inline'; file: string; contentType: string }
  | { kind: 'url'; url: string };

/** Servidores externos desde los que se copian imágenes (fotos de perfil de Google, Unsplash). */
export const ALLOWED_IMAGE_HOSTS = [/(^|\.)googleusercontent\.com$/, /(^|\.)unsplash\.com$/];

export function allowedExternalImage(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && ALLOWED_IMAGE_HOSTS.some((re) => re.test(u.hostname));
  } catch {
    return false;
  }
}

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

const DATA_URL = /^data:(image\/(?:png|jpeg|jpg|webp)|audio\/(?:webm|ogg|mpeg|mp4|x-m4a|mp3)(?:;codecs=[\w.]+)?);base64,([A-Za-z0-9+/=\s]+)$/;

export function parseDataUrl(v: string): { contentType: string; bytes: Buffer } | null {
  const m = v.match(DATA_URL);
  if (!m) return null;
  const declared = m[1]!.split(';')[0]!;
  const contentType = declared === 'image/jpg' ? 'image/jpeg' : declared === 'audio/x-m4a' ? 'audio/mp4' : declared === 'audio/mp3' ? 'audio/mpeg' : declared;
  return { contentType, bytes: Buffer.from(m[2]!.replace(/\s/g, ''), 'base64') };
}

export const assetIdForStorage = (path: string) => stableId(`storage/${path}`);
export const assetIdForUrl = (url: string) => stableId(`url/${url}`);
export const assetIdForInline = (collection: string, docId: string, field: string) => stableId(`inline/${collection}/${docId}/${field}`);
