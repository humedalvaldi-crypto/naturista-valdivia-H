import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import type { MediaEntry } from '../scripts/transform/media';
import { mediaInsertSql, prepareMedia, type CopiedMedia } from '../scripts/transform/media-copy';
import { transform, type PlanReport } from '../scripts/transform/run';
import { validate } from '../scripts/transform/validate-core';
import { PNG_1x1, writeFixtureSnapshot } from './support/fixture';
import { count, freshDb, WORKER_MIGRATIONS } from './support/sqlite';

const png = () => new Uint8Array(Buffer.from(PNG_1x1, 'base64'));
const entry = (over: Partial<MediaEntry> = {}): MediaEntry => ({
  assetId: '11111111-1111-5111-8111-111111111111',
  ownerId: 'uidAna',
  purpose: 'post-photo',
  visibility: 'public',
  source: { kind: 'inline', file: 'x.png', contentType: 'image/png' },
  legacyStoragePath: null,
  legacyAssetId: null,
  ...over,
});

describe('preparar archivos', () => {
  it('acepta una imagen válida con la misma forma de clave que la API', () => {
    const r = prepareMedia(entry(), png());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.media).toMatchObject({ objectKey: 'u/uidAna/post-photo/11111111-1111-5111-8111-111111111111.png', contentType: 'image/png' });
    expect(r.media.sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it('rechaza tipos que no corresponden o archivos que no son imágenes', () => {
    expect(prepareMedia(entry(), new Uint8Array(Buffer.from('<html>hola</html>')))).toEqual({ ok: false, reason: 'tipo de archivo no admitido' });
    expect(prepareMedia(entry({ purpose: 'notebook-audio' }), png())).toMatchObject({ ok: false });
    expect(prepareMedia(entry(), new Uint8Array())).toEqual({ ok: false, reason: 'archivo vacío' });
  });
});

describe('aplicar, copiar archivos después y validar', () => {
  let out: string;
  let files: string[];
  let report: PlanReport;
  let copied: CopiedMedia[];

  beforeAll(() => {
    out = mkdtempSync(join(tmpdir(), 'nv-plan-'));
    files = transform(writeFixtureSnapshot(), out, WORKER_MIGRATIONS).files;
    report = JSON.parse(readFileSync(join(out, 'report.json'), 'utf8')) as PlanReport;
    // "Copia" solo de las imágenes incrustadas (las de Storage necesitarían Firebase).
    const manifest = readFileSync(join(out, 'media-manifest.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l) as MediaEntry);
    copied = manifest
      .filter((m) => m.source.kind === 'inline')
      .map((m) => {
        const r = prepareMedia(m, new Uint8Array(readFileSync(join(out, 'inline', (m.source as { file: string }).file))));
        if (!r.ok) throw new Error(r.reason);
        return r.media;
      });
    writeFileSync(join(out, 'sql', '035-media-assets-p001.sql'), copied.map(mediaInsertSql).join('\n'));
  });

  const sqlFiles = () => readdirSync(join(out, 'sql')).filter((f) => f.endsWith('.sql')).sort();
  const q = (db: ReturnType<typeof freshDb>) => async (sql: string) => db.prepare(sql).all() as Record<string, unknown>[];

  it('si el contenido se aplicó antes que los archivos, al repetir quedan enlazados', async () => {
    const db = freshDb();
    // 1) Contenido sin archivos.
    for (const f of files) db.exec(readFileSync(join(out, 'sql', f), 'utf8'));
    expect(count(db, "SELECT count(*) n FROM posts WHERE legacy_id = 'p2' AND media_asset_id IS NOT NULL")).toBe(0);
    // 2) Todo de nuevo, ahora con archivos (idempotente + enlace).
    for (const f of sqlFiles()) db.exec(readFileSync(join(out, 'sql', f), 'utf8'));
    expect(count(db, "SELECT count(*) n FROM posts WHERE legacy_id = 'p2' AND media_asset_id IS NOT NULL")).toBe(1);
    expect(count(db, "SELECT count(*) n FROM notebook_elements WHERE id = 'dibujo' AND media_asset_id IS NOT NULL")).toBe(1);

    const checks = await validate(q(db), report, copied);
    expect(checks.filter((c) => !c.ok)).toEqual([]);
  });

  it('la validación detecta filas faltantes, ubicaciones expuestas y hashes distintos', async () => {
    const db = freshDb();
    for (const f of sqlFiles()) db.exec(readFileSync(join(out, 'sql', f), 'utf8'));
    db.exec("DELETE FROM messages WHERE legacy_id = 'm2'");
    db.exec("UPDATE observations SET obscured = 0, public_latitude = latitude, public_longitude = longitude WHERE legacy_id = 'o1'");
    db.exec(`UPDATE media_assets SET sha256 = '${'0'.repeat(64)}' WHERE id = '${copied[0]!.assetId}'`);
    const failed = (await validate(q(db), report, copied)).filter((c) => !c.ok).map((c) => c.name);
    expect(failed).toEqual(['filas en messages', 'especies sensibles con ubicación protegida', 'hash y tamaño de archivos coinciden con lo subido']);
  });
});
