import { createHash } from 'node:crypto';
import { stripLocationMetadata } from '../../../worker/src/services/image-metadata';
import { PURPOSES, sniff } from '../../../worker/src/services/media-types';
import type { MediaEntry } from './media';
import { insert } from './sql';

export interface CopiedMedia {
  assetId: string;
  ownerId: string;
  purpose: string;
  visibility: 'public' | 'private';
  objectKey: string;
  contentType: string;
  size: number;
  sha256: string;
  legacyStoragePath: string | null;
  legacyAssetId: string | null;
}

export type Prepared = { ok: true; media: CopiedMedia; bytes: Uint8Array } | { ok: false; reason: string };

/**
 * Prepara un archivo para R2 con las mismas reglas que una subida nueva:
 * tipo real por su firma, tipos y tamaños permitidos por uso, y sin
 * metadatos de ubicación (GPS del EXIF, XMP).
 */
export function prepareMedia(entry: MediaEntry, original: Uint8Array): Prepared {
  if (original.byteLength === 0) return { ok: false, reason: 'archivo vacío' };
  const type = sniff(original);
  const rule = PURPOSES[entry.purpose];
  if (!type) return { ok: false, reason: 'tipo de archivo no admitido' };
  if (!(rule.kinds as readonly string[]).includes(type.kind)) return { ok: false, reason: `tipo ${type.mime} no válido para ${entry.purpose}` };
  let bytes: Uint8Array;
  try {
    bytes = stripLocationMetadata(original, type.mime);
  } catch {
    return { ok: false, reason: 'imagen dañada' };
  }
  if (bytes.byteLength > rule.maxBytes) return { ok: false, reason: `supera ${Math.round(rule.maxBytes / 1024 / 1024)} MB` };
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return {
    ok: true,
    bytes,
    media: {
      assetId: entry.assetId,
      ownerId: entry.ownerId,
      purpose: entry.purpose,
      visibility: entry.visibility,
      // Misma forma que las subidas nuevas: u/<dueña>/<uso>/<id>.<ext>
      objectKey: `u/${entry.ownerId}/${entry.purpose}/${entry.assetId}.${type.ext}`,
      contentType: type.mime,
      size: bytes.byteLength,
      sha256,
      legacyStoragePath: entry.legacyStoragePath,
      legacyAssetId: entry.legacyAssetId,
    },
  };
}

export function mediaInsertSql(m: CopiedMedia): string {
  return insert('media_assets', {
    id: m.assetId,
    owner_id: m.ownerId,
    purpose: m.purpose,
    object_key: m.objectKey,
    content_type: m.contentType,
    size_bytes: m.size,
    sha256: m.sha256,
    visibility: m.visibility,
    legacy_storage_path: m.legacyStoragePath,
    legacy_asset_id: m.legacyAssetId,
  });
}

/** Trozo por sentencia al migrar a D1: 32 KB → ~64 KB en hexadecimal (D1 admite ~100 KB por sentencia). */
export const MIGRATION_CHUNK_BYTES = 32 * 1024;

/** SQL para guardar los bytes en D1 (tabla media_chunks) cuando no hay R2. */
export function mediaChunkSql(objectKey: string, bytes: Uint8Array): string[] {
  const out: string[] = [];
  for (let i = 0, part = 0; i < bytes.byteLength; i += MIGRATION_CHUNK_BYTES, part++) {
    const hex = Buffer.from(bytes.subarray(i, i + MIGRATION_CHUNK_BYTES)).toString('hex');
    out.push(`INSERT INTO media_chunks (object_key, part, bytes) VALUES (${insertKey(objectKey)}, ${part}, X'${hex}') ON CONFLICT DO NOTHING;`);
  }
  return out;
}
const insertKey = (k: string) => `'${k.replace(/'/g, "''")}'`;
