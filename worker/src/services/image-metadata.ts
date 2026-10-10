/**
 * Quita de las imágenes los metadatos que pueden revelar la ubicación
 * (coordenadas GPS de la cámara) antes de guardarlas. Importante para
 * especies sensibles: ocultar la ubicación en el mapa no sirve si la foto
 * lleva las coordenadas exactas dentro.
 *
 * - JPEG: se vacía el directorio GPS del EXIF (se conserva la orientación)
 *   y se eliminan los bloques XMP (APP1) e IPTC (APP13).
 * - PNG: se eliminan los fragmentos eXIf, tEXt, iTXt y zTXt.
 * - WebP: se eliminan los fragmentos EXIF y XMP y se corrigen los indicadores.
 * Otros formatos (audio, PDF) se devuelven sin cambios.
 */
export function stripLocationMetadata(bytes: Uint8Array, mime: string): Uint8Array {
  try {
    if (mime === 'image/jpeg') return stripJpeg(bytes);
    if (mime === 'image/png') return stripPng(bytes);
    if (mime === 'image/webp') return stripWebp(bytes);
  } catch {
    // Archivo con estructura inesperada: se rechaza antes que guardar datos sin limpiar.
    throw new MetadataError();
  }
  return bytes;
}

export class MetadataError extends Error {
  constructor() {
    super('No se pudo procesar la imagen.');
  }
}

const u16be = (b: Uint8Array, o: number) => (b[o]! << 8) | b[o + 1]!;
const startsWithAscii = (b: Uint8Array, o: number, s: string) => [...s].every((ch, i) => b[o + i] === ch.charCodeAt(0));

function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

function stripJpeg(src: Uint8Array): Uint8Array {
  if (src[0] !== 0xff || src[1] !== 0xd8) throw new Error('no SOI');
  const parts: Uint8Array[] = [src.subarray(0, 2)];
  let o = 2;
  while (o < src.length) {
    if (src[o] !== 0xff) throw new Error('marcador inválido');
    const marker = src[o + 1]!;
    if (marker === 0xff) {
      o++; // relleno
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) {
      // EOI o inicio de los datos de imagen: el resto se copia tal cual.
      parts.push(src.subarray(o));
      return concat(parts);
    }
    if ((marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
      parts.push(src.subarray(o, o + 2));
      o += 2;
      continue;
    }
    if (o + 4 > src.length) {
      parts.push(src.subarray(o));
      return concat(parts);
    }
    const len = u16be(src, o + 2);
    if (len < 2) throw new Error('segmento inválido');
    if (o + 2 + len > src.length) {
      // Archivo cortado dentro de un segmento: ningún lector ve datos después.
      if (marker === 0xe1 || marker === 0xed) return concat(parts);
      parts.push(src.subarray(o));
      return concat(parts);
    }
    const segment = src.subarray(o, o + 2 + len);
    if (marker === 0xe1 && startsWithAscii(src, o + 4, 'Exif\0\0')) {
      const copy = segment.slice();
      clearExifGps(copy.subarray(10)); // TIFF tras "FFE1 len Exif\0\0"
      parts.push(copy);
    } else if (marker === 0xe1 || marker === 0xed) {
      // XMP / IPTC: fuera.
    } else {
      parts.push(segment);
    }
    o += 2 + len;
  }
  return concat(parts);
}

const TYPE_SIZES: Record<number, number> = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8 };

/** Vacía el directorio GPS de un bloque TIFF (EXIF), borrando también sus datos. */
export function clearExifGps(tiff: Uint8Array): void {
  if (tiff.length < 8) return;
  const little = tiff[0] === 0x49 && tiff[1] === 0x49;
  if (!little && !(tiff[0] === 0x4d && tiff[1] === 0x4d)) throw new Error('TIFF inválido');
  const view = new DataView(tiff.buffer, tiff.byteOffset, tiff.byteLength);
  const u16 = (o: number) => view.getUint16(o, little);
  const u32 = (o: number) => view.getUint32(o, little);

  const ifd0 = u32(4);
  if (ifd0 + 2 > tiff.length) throw new Error('IFD0 fuera de rango');
  const n0 = u16(ifd0);
  for (let i = 0; i < n0; i++) {
    const entry = ifd0 + 2 + i * 12;
    if (entry + 12 > tiff.length) throw new Error('entrada fuera de rango');
    if (u16(entry) !== 0x8825) continue; // GPSInfo
    const gps = u32(entry + 8);
    if (gps + 2 > tiff.length) throw new Error('GPS fuera de rango');
    const n = u16(gps);
    for (let j = 0; j < n; j++) {
      const e = gps + 2 + j * 12;
      if (e + 12 > tiff.length) break;
      const size = (TYPE_SIZES[u16(e + 2)] ?? 1) * u32(e + 4);
      if (size > 4) {
        const off = u32(e + 8);
        if (off + size <= tiff.length) tiff.fill(0, off, off + size);
      }
      tiff.fill(0, e, e + 12);
    }
    view.setUint16(gps, 0, little); // directorio GPS vacío
  }
}

const PNG_DROP = new Set(['eXIf', 'tEXt', 'iTXt', 'zTXt']);

function stripPng(src: Uint8Array): Uint8Array {
  const parts: Uint8Array[] = [src.subarray(0, 8)];
  let o = 8;
  while (o + 12 <= src.length) {
    const len = ((src[o]! << 24) | (src[o + 1]! << 16) | (src[o + 2]! << 8) | src[o + 3]!) >>> 0;
    const type = String.fromCharCode(...src.subarray(o + 4, o + 8));
    const end = o + 12 + len;
    if (end > src.length) throw new Error('fragmento truncado');
    if (!PNG_DROP.has(type)) parts.push(src.subarray(o, end));
    o = end;
    if (type === 'IEND') break;
  }
  return concat(parts);
}

function stripWebp(src: Uint8Array): Uint8Array {
  if (!startsWithAscii(src, 0, 'RIFF') || !startsWithAscii(src, 8, 'WEBP')) throw new Error('no WebP');
  const parts: Uint8Array[] = [];
  let o = 12;
  let vp8x: Uint8Array | null = null;
  while (o + 8 <= src.length) {
    const type = String.fromCharCode(...src.subarray(o, o + 4));
    const len = (src[o + 4]! | (src[o + 5]! << 8) | (src[o + 6]! << 16) | (src[o + 7]! << 24)) >>> 0;
    const end = o + 8 + len + (len % 2);
    if (o + 8 + len > src.length) throw new Error('fragmento truncado');
    const chunk = src.subarray(o, Math.min(end, src.length)).slice();
    if (type === 'VP8X') vp8x = chunk;
    if (type !== 'EXIF' && type !== 'XMP ') parts.push(chunk);
    o = end;
  }
  if (vp8x) vp8x[8] = vp8x[8]! & ~0x0c; // sin indicadores de EXIF (0x08) ni XMP (0x04)
  const body = concat(parts);
  const header = new Uint8Array(12);
  header.set(src.subarray(0, 12));
  new DataView(header.buffer).setUint32(4, body.length + 4, true);
  return concat([header, body]);
}
