/**
 * Tipos de archivo admitidos. El tipo se comprueba por la FIRMA del archivo
 * (primeros bytes), no solo por la cabecera Content-Type que envía el cliente.
 */

export type MediaKind = 'image' | 'audio' | 'pdf';

export interface SniffedType {
  mime: string;
  ext: string;
  kind: MediaKind;
}

const MB = 1024 * 1024;

export const PURPOSES = {
  'observation-photo': { kinds: ['image'], maxBytes: 10 * MB },
  'notebook-photo': { kinds: ['image'], maxBytes: 10 * MB },
  'notebook-audio': { kinds: ['audio'], maxBytes: 20 * MB },
  'notebook-export': { kinds: ['pdf', 'image'], maxBytes: 25 * MB },
  'profile-photo': { kinds: ['image'], maxBytes: 5 * MB },
  'profile-banner': { kinds: ['image'], maxBytes: 8 * MB },
  'community-photo': { kinds: ['image'], maxBytes: 8 * MB },
  'post-photo': { kinds: ['image'], maxBytes: 10 * MB },
  'map-place-photo': { kinds: ['image'], maxBytes: 10 * MB },
} as const satisfies Record<string, { kinds: readonly MediaKind[]; maxBytes: number }>;

export type MediaPurpose = keyof typeof PURPOSES;

export const isPurpose = (v: unknown): v is MediaPurpose => typeof v === 'string' && Object.hasOwn(PURPOSES, v);

/** Mayor límite de todos los propósitos: corta la lectura del cuerpo antes. */
export const MAX_UPLOAD_BYTES = Math.max(...Object.values(PURPOSES).map((p) => p.maxBytes));

const ascii = (b: Uint8Array, start: number, text: string) =>
  b.length >= start + text.length && [...text].every((ch, i) => b[start + i] === ch.charCodeAt(0));

/** Identifica el tipo real por sus bytes iniciales. `null` si no es admitido. */
export function sniff(bytes: Uint8Array): SniffedType | null {
  const b = bytes;
  if (b.length < 12) return null;
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg', kind: 'image' };
  if (b[0] === 0x89 && ascii(b, 1, 'PNG') && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) {
    return { mime: 'image/png', ext: 'png', kind: 'image' };
  }
  if (ascii(b, 0, 'RIFF') && ascii(b, 8, 'WEBP')) return { mime: 'image/webp', ext: 'webp', kind: 'image' };
  if (ascii(b, 0, '%PDF-')) return { mime: 'application/pdf', ext: 'pdf', kind: 'pdf' };
  if (ascii(b, 0, 'OggS')) return { mime: 'audio/ogg', ext: 'ogg', kind: 'audio' };
  if (ascii(b, 0, 'ID3') || (b[0] === 0xff && ((b[1] ?? 0) & 0xe0) === 0xe0)) {
    return { mime: 'audio/mpeg', ext: 'mp3', kind: 'audio' };
  }
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return { mime: 'audio/webm', ext: 'webm', kind: 'audio' };
  if (ascii(b, 4, 'ftyp')) {
    // Contenedor MP4: se admite solo como audio (notas de voz .m4a).
    const brand = String.fromCharCode(...b.slice(8, 12));
    if (['M4A ', 'mp42', 'isom', 'iso2', 'mp41', 'dash'].includes(brand)) return { mime: 'audio/mp4', ext: 'm4a', kind: 'audio' };
  }
  return null;
}

/** El tipo declarado por el cliente debe coincidir con el real. */
export function declaredMatches(declared: string | undefined, sniffed: SniffedType): boolean {
  const d = (declared ?? '').split(';')[0]!.trim().toLowerCase();
  if (d === sniffed.mime) return true;
  const aliases: Record<string, string[]> = {
    'image/jpeg': ['image/jpg', 'image/pjpeg'],
    'audio/mp4': ['audio/m4a', 'audio/x-m4a', 'audio/aac'],
    'audio/mpeg': ['audio/mp3'],
    'audio/webm': ['video/webm'],
  };
  return aliases[sniffed.mime]?.includes(d) ?? false;
}
