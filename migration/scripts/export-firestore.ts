/**
 * Exportación de SOLO LECTURA de Firebase a una instantánea local.
 *
 * Uso (desde migration/):
 *   GOOGLE_APPLICATION_CREDENTIALS=/ruta/fuera/del/repo/sa.json \
 *   npm run export -- --project humedalvaldivia-c7d08 [--out output]
 *
 * Escribe en output/snapshot-<fecha>/ (ignorado por git):
 *   auth-users.jsonl            uid, correo, nombre, proveedores, fechas (DATOS PERSONALES)
 *   firestore/<colección>.jsonl un documento por línea: {id, path, parent?, data}
 *   storage.jsonl               archivos bajo user-files/: ruta, tamaño, tipo, md5
 *   manifest.json               proyecto, fecha y conteos
 *
 * Qué NO hace: no escribe, no modifica ni borra nada en Firebase.
 * La instantánea contiene datos personales: guárdala cifrada y bórrala al terminar.
 */
import { createWriteStream, mkdirSync, writeFileSync, type WriteStream } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldPath, getFirestore } from 'firebase-admin/firestore';
import { BucketUnavailable, resolveBucket } from './lib/bucket';
import { encodeValue } from './lib/encode';
import { LEGACY_SUBCOLLECTIONS } from './lib/legacy-inventory';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    out: { type: 'string', default: process.env['MIGRATION_OUTPUT_DIR'] ?? 'output' },
    bucket: { type: 'string' },
    'page-size': { type: 'string', default: '500' },
  },
});

const projectId = values.project;
if (!projectId) {
  console.error('Falta --project <id>. Se exige explícitamente para no exportar el proyecto equivocado.');
  process.exit(2);
}
const pageSize = Math.min(Math.max(Number.parseInt(values['page-size'] ?? '500', 10) || 500, 50), 1000);
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const dir = resolve(values.out ?? 'output', `snapshot-${stamp}`);
mkdirSync(join(dir, 'firestore'), { recursive: true });

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

function line(stream: WriteStream, value: unknown) {
  return new Promise<void>((ok) => {
    if (stream.write(`${JSON.stringify(value)}\n`)) ok();
    else stream.once('drain', () => ok());
  });
}
const close = (s: WriteStream) => new Promise<void>((ok) => s.end(ok));

async function exportAuth(): Promise<number> {
  const out = createWriteStream(join(dir, 'auth-users.jsonl'));
  let n = 0;
  let pageToken: string | undefined;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const u of page.users) {
      await line(out, {
        uid: u.uid,
        email: u.email ?? null,
        emailVerified: u.emailVerified,
        displayName: u.displayName ?? null,
        providers: u.providerData.map((p) => p.providerId),
        disabled: u.disabled,
        createdAt: u.metadata.creationTime ? new Date(u.metadata.creationTime).toISOString() : null,
        lastSignInAt: u.metadata.lastSignInTime ? new Date(u.metadata.lastSignInTime).toISOString() : null,
      });
      n++;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  await close(out);
  return n;
}

/** Lee una colección completa por páginas ordenadas por ID (reanudable y sin cargarla entera en memoria). */
async function exportQuery(
  query: FirebaseFirestore.Query,
  out: WriteStream,
  parent?: string,
): Promise<number> {
  let n = 0;
  let last: string | undefined;
  for (;;) {
    let q = query.orderBy(FieldPath.documentId()).limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    for (const doc of snap.docs) {
      await line(out, { id: doc.id, path: doc.ref.path, ...(parent ? { parent } : {}), data: encodeValue(doc.data()) });
      n++;
    }
    if (snap.size < pageSize) return n;
    last = snap.docs[snap.docs.length - 1]!.id;
  }
}

async function exportFirestore(): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  for (const col of await db.listCollections()) {
    const out = createWriteStream(join(dir, 'firestore', `${col.id}.jsonl`));
    counts[col.id] = await exportQuery(col, out);
    await close(out);
    console.log(`  ${col.id}: ${counts[col.id]}`);
  }
  for (const sub of LEGACY_SUBCOLLECTIONS) {
    const name = `${sub.parent}__${sub.name}`;
    const out = createWriteStream(join(dir, 'firestore', `${name}.jsonl`));
    let total = 0;
    for (const parentRef of await db.collection(sub.parent).listDocuments()) {
      total += await exportQuery(parentRef.collection(sub.name), out, parentRef.id);
    }
    await close(out);
    counts[name] = total;
    console.log(`  ${name}: ${total}`);
  }
  return counts;
}

async function exportStorage(): Promise<number> {
  const out = createWriteStream(join(dir, 'storage.jsonl'));
  let bucket;
  try {
    bucket = await resolveBucket(projectId!, values.bucket);
  } catch (err) {
    if (!(err instanceof BucketUnavailable)) throw err;
    // Sin Storage se exportan igual los datos; las fotos quedarán contadas como no copiadas.
    console.log(`::warning::${err.message} Se continúa sin fotos de Storage.`);
    await close(out);
    return 0;
  }
  const [files] = await bucket.getFiles({ prefix: 'user-files/', autoPaginate: true });
  for (const f of files) {
    await line(out, {
      path: f.name,
      size: Number(f.metadata.size ?? 0),
      contentType: f.metadata.contentType ?? null,
      md5: f.metadata.md5Hash ?? null,
      updated: f.metadata.updated ?? null,
    });
  }
  await close(out);
  return files.length;
}

console.log(`Exportando ${projectId} (solo lectura) → ${dir}`);
const users = await exportAuth();
console.log(`  usuarios de Auth: ${users}`);
const collections = await exportFirestore();
const storageFiles = await exportStorage();
console.log(`  archivos en Storage: ${storageFiles}`);
writeFileSync(
  join(dir, 'manifest.json'),
  JSON.stringify({ project: projectId, createdAt: new Date().toISOString(), counts: { users, storageFiles, collections } }, null, 2),
);
console.log('Listo. La instantánea contiene datos personales: no la compartas ni la subas al repositorio.');
