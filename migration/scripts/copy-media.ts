/**
 * Paso 3: copia los archivos del plan desde Firebase Storage (SOLO LECTURA)
 * a Cloudflare R2, limpiando metadatos de ubicación, y genera el SQL de
 * `media_assets` solo para lo que se copió y verificó.
 *
 * Uso (desde migration/):
 *   # Ensayo: descarga y valida, NO sube nada.
 *   npm run copy-media -- --plan output/plan --project humedalvaldivia-c7d08
 *   # Sin R2 (plan gratuito): los bytes se guardan en D1. Genera SQL en el plan;
 *   # se escribe en D1 solo al aplicar el plan (paso 4).
 *   npm run copy-media -- --plan output/plan --project humedalvaldivia-c7d08 --store d1 --confirm
 *   # Copia real a R2 (requiere tu autorización):
 *   R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... \
 *   npm run copy-media -- --plan output/plan --project humedalvaldivia-c7d08 --r2-bucket naturista-valdivia-media --confirm
 *
 * Reanudable: lo ya copiado queda en <plan>/media-done.jsonl y se salta.
 * Firebase Storage no se modifica.
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { AwsClient } from 'aws4fetch';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { BucketUnavailable, resolveBucket } from './lib/bucket';
import { redact } from './lib/redact';
import { allowedExternalImage, type MediaEntry } from './transform/media';
import { mediaChunkSql, mediaInsertSql, prepareMedia, type CopiedMedia } from './transform/media-copy';

const { values } = parseArgs({
  options: {
    plan: { type: 'string', default: 'output/plan' },
    project: { type: 'string' },
    bucket: { type: 'string' },
    'r2-bucket': { type: 'string' },
    concurrency: { type: 'string', default: '4' },
    confirm: { type: 'boolean', default: false },
    store: { type: 'string', default: 'r2' },
  },
});
const store = values.store === 'd1' ? 'd1' : 'r2';

const planDir = resolve(values.plan ?? 'output/plan');
const manifestFile = join(planDir, 'media-manifest.jsonl');
if (!existsSync(manifestFile)) {
  console.error(`No hay manifiesto en ${planDir}. Ejecuta antes: npm run plan`);
  process.exit(2);
}
const entries = readFileSync(manifestFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l) as MediaEntry);
const doneFile = join(planDir, 'media-done.jsonl');
// Registro de lo ya copiado (objeto simple: este archivo no usa métodos de escritura de Firebase).
const done: Record<string, CopiedMedia> = Object.fromEntries(
  existsSync(doneFile)
    ? readFileSync(doneFile, 'utf8').split('\n').filter(Boolean).map((l) => {
        const m = JSON.parse(l) as CopiedMedia;
        return [m.assetId, m] as const;
      })
    : [],
);
const isDone = (id: string) => Object.hasOwn(done, id);

const needsStorage = entries.some((e) => e.source.kind === 'storage' && !isDone(e.assetId));
if (needsStorage && !values.project) {
  console.error('Falta --project <id> para leer Firebase Storage.');
  process.exit(2);
}
if (values.project) initializeApp({ credential: applicationDefault(), projectId: values.project });
let storageBucket: Awaited<ReturnType<typeof resolveBucket>> | null = null;
if (values.project && needsStorage) {
  try {
    storageBucket = await resolveBucket(values.project, values.bucket);
  } catch (err) {
    if (!(err instanceof BucketUnavailable)) throw err;
    console.log(`::warning::${err.message} Las fotos de Storage no se copian; las imágenes incrustadas sí.`);
  }
}

const confirm = values.confirm === true;
let r2: { client: AwsClient; base: string } | null = null;
if (confirm && store === 'r2') {
  const account = process.env['R2_ACCOUNT_ID'];
  const key = process.env['R2_ACCESS_KEY_ID'];
  const secret = process.env['R2_SECRET_ACCESS_KEY'];
  const bucket = values['r2-bucket'];
  if (!account || !key || !secret || !bucket) {
    console.error('Para copiar de verdad faltan R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY y --r2-bucket.');
    process.exit(2);
  }
  r2 = { client: new AwsClient({ accessKeyId: key, secretAccessKey: secret, service: 's3', region: 'auto' }), base: `https://${account}.r2.cloudflarestorage.com/${bucket}` };
}

/** Imagen de un servidor permitido (fotos de perfil de Google, Unsplash), con tope de tamaño y tiempo. */
async function download(url: string): Promise<Uint8Array> {
  if (!allowedExternalImage(url)) throw new Error('servidor externo no permitido');
  const res = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(20_000) });
  if (!res.ok) throw new Error(`servidor externo respondió ${res.status}`);
  const len = Number(res.headers.get('content-length') ?? 0);
  if (len > 10 * 1024 * 1024) throw new Error('imagen externa demasiado grande');
  const buf = new Uint8Array(await res.arrayBuffer());
  if (buf.byteLength > 10 * 1024 * 1024) throw new Error('imagen externa demasiado grande');
  return buf;
}

async function readSource(e: MediaEntry): Promise<Uint8Array> {
  if (e.source.kind === 'inline') return new Uint8Array(readFileSync(join(planDir, 'inline', e.source.file)));
  if (e.source.kind === 'url') return download(e.source.url);
  if (!storageBucket) throw new Error('Firebase Storage no accesible');
  const [buf] = await storageBucket.file(e.source.path).download(); // solo lectura
  return new Uint8Array(buf);
}

async function putObject(m: CopiedMedia, bytes: Uint8Array) {
  const url = `${r2!.base}/${m.objectKey.split('/').map(encodeURIComponent).join('/')}`;
  const res = await r2!.client.fetch(url, {
    method: 'PUT',
    body: Buffer.from(bytes),
    headers: {
      'Content-Type': m.contentType,
      'x-amz-meta-owner': m.ownerId,
      'x-amz-meta-assetid': m.assetId,
      'x-amz-meta-sha256': m.sha256,
    },
  });
  if (!res.ok) throw new Error(`R2 respondió ${res.status}`);
  // Verificación: el objeto existe con el tamaño esperado.
  const head = await r2!.client.fetch(url, { method: 'HEAD' });
  if (!head.ok || Number(head.headers.get('content-length')) !== m.size) throw new Error('verificación fallida tras subir');
}

const d1Dir = join(planDir, 'media-d1');
if (confirm && store === 'd1') mkdirSync(d1Dir, { recursive: true });

const failures: Record<string, number> = {};
const fail = (reason: string) => (failures[reason] = (failures[reason] ?? 0) + 1);
let copied = 0;
let checked = 0;

const pending = entries.filter((e) => !isDone(e.assetId));
console.log(`${entries.length} archivos en el plan, ${Object.keys(done).length} ya copiados, ${pending.length} pendientes. Modo: ${confirm ? (store === 'r2' ? 'COPIA REAL a R2' : 'SQL para guardar en D1 (se escribe al aplicar)') : 'ensayo (no sube nada)'}`);

const queue = [...pending];
async function worker() {
  for (let e = queue.shift(); e; e = queue.shift()) {
    try {
      const prepared = prepareMedia(e, await readSource(e));
      if (!prepared.ok) {
        fail(prepared.reason);
        continue;
      }
      checked++;
      if (!confirm) continue;
      if (store === 'r2') await putObject(prepared.media, prepared.bytes);
      else writeFileSync(join(d1Dir, `${e.assetId}.sql`), `${mediaChunkSql(prepared.media.objectKey, prepared.bytes).join('\n')}\n`);
      appendFileSync(doneFile, `${JSON.stringify(prepared.media)}\n`);
      done[e.assetId] = prepared.media;
      copied++;
      if (copied % 50 === 0) console.log(`  ${copied} copiados…`);
    } catch (err) {
      fail(err instanceof Error ? redact(err.message).slice(0, 120) : 'error desconocido');
    }
  }
}
await Promise.all(Array.from({ length: Math.min(Math.max(Number(values.concurrency) || 4, 1), 16) }, worker));

// SQL de media_assets solo con lo copiado y verificado.
mkdirSync(join(planDir, 'sql'), { recursive: true });
const rows = Object.values(done).map(mediaInsertSql);
for (let i = 0, part = 1; i < Math.max(rows.length, 1); i += 400, part++) {
  if (rows.length === 0) break;
  writeFileSync(join(planDir, 'sql', `035-media-assets-p${String(part).padStart(3, '0')}.sql`), `-- 035-media-assets (parte ${part})\n${rows.slice(i, i + 400).join('\n')}\n`);
}
// Sin R2: los bytes van en SQL (media_chunks) antes de las filas de media_assets.
if (store === 'd1' && existsSync(d1Dir)) {
  const chunkFiles = Object.keys(done).map((id) => join(d1Dir, `${id}.sql`)).filter((f) => existsSync(f));
  const statements = chunkFiles.flatMap((f) => readFileSync(f, 'utf8').split('\n').filter(Boolean));
  for (let i = 0, part = 1; i < statements.length; i += 40, part++) {
    writeFileSync(join(planDir, 'sql', `034-media-chunks-p${String(part).padStart(3, '0')}.sql`), `-- 034-media-chunks (parte ${part})\n${statements.slice(i, i + 40).join('\n')}\n`);
  }
}
const summary = { at: new Date().toISOString(), mode: confirm ? `copy-${store}` : 'dry-run', store, planned: entries.length, valid: checked, copiedNow: copied, copiedTotal: Object.keys(done).length, failures };
writeFileSync(join(planDir, `media-report-${confirm ? 'copy' : 'dry-run'}.json`), JSON.stringify(summary, null, 2));
console.log(JSON.stringify(summary, null, 2));
