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
