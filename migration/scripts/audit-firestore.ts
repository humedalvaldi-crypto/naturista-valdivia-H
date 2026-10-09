/**
 * Auditoría de SOLO LECTURA de Firebase (Auth, Firestore, Storage).
 *
 * Uso (desde migration/):
 *   GOOGLE_APPLICATION_CREDENTIALS=/ruta/fuera/del/repo/sa.json \
 *   npm run audit -- --project humedalvaldivia-c7d08 [--sample 500] [--out output]
 *
 * Qué hace:
 *   - Cuenta usuarios de Auth por proveedor (google.com, password, ...).
 *   - Lista colecciones raíz, cuenta documentos e infiere el esquema
 *     sobre una muestra (solo nombres de campo y tipos, nunca valores).
 *   - Verifica que los campos de UID apunten a usuarios existentes.
 *   - Cuenta archivos y bytes en Firebase Storage bajo `user-files/`.
 *   - Escribe `audit-<fecha>.json` y `audit-<fecha>.md` en la carpeta de salida.
 *
 * Qué NO hace: no escribe, no modifica ni borra nada en Firebase.
 * La cuenta de servicio debería tener solo roles de lectura
 * (ver migration/README.md).
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { LEGACY_COLLECTIONS, LEGACY_SUBCOLLECTIONS } from './lib/legacy-inventory';
import { addToReport, compositeIdMatches, emptyReferenceReport, type ReferenceReport } from './lib/reference-check';
import { inferSchema, mixedTypeFields, optionalFields } from './lib/schema-inference';
import { renderMarkdown } from './lib/report';
import type { AuditReport } from './lib/types';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    sample: { type: 'string', default: '500' },
    out: { type: 'string', default: process.env['MIGRATION_OUTPUT_DIR'] ?? 'output' },
    bucket: { type: 'string' },
  },
});

const projectId = values.project;
if (!projectId) {
  console.error('Falta --project <id>. Se exige explícitamente para no auditar el proyecto equivocado.');
  process.exit(2);
}
const sampleSize = Math.min(Math.max(Number.parseInt(values.sample ?? '500', 10) || 500, 1), 5000);
const outDir = resolve(values.out ?? 'output');
const bucketName = values.bucket ?? `${projectId}.firebasestorage.app`;

initializeApp({ credential: applicationDefault(), projectId, storageBucket: bucketName });
const db = getFirestore();
const auth = getAuth();

async function auditAuth(): Promise<{ uids: Set<string>; summary: AuditReport['auth'] }> {
  const uids = new Set<string>();
  const byProvider: Record<string, number> = {};
  let disabled = 0;
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) {
      uids.add(u.uid);
      if (u.disabled) disabled += 1;
      const providers = u.providerData.map((p) => p.providerId);
      for (const p of providers.length ? providers : ['(sin proveedor)']) byProvider[p] = (byProvider[p] ?? 0) + 1;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return { uids, summary: { users: uids.size, byProvider, disabled } };
}

async function auditCollections(uids: Set<string>) {
  const rootCollections = await db.listCollections();
  const names = rootCollections.map((c) => c.id).sort();
  const expected = new Map(LEGACY_COLLECTIONS.map((c) => [c.name, c]));
  const results: AuditReport['collections'] = [];

  for (const name of names) {
    const ref = db.collection(name);
    const count = (await ref.count().get()).data().count;
    const snap = await ref.orderBy('__name__').limit(sampleSize).get();
    const schema = inferSchema(snap.docs.map((d) => d.data()));
    const legacy = expected.get(name);

    const uidReferences: Record<string, ReferenceReport> = {};
    let compositeIdMismatches: number | undefined;
    if (legacy) {
      for (const field of legacy.uidFields) uidReferences[field] = emptyReferenceReport();
      if (legacy.docId === 'uid') uidReferences['(docId)'] = emptyReferenceReport();
      if (legacy.name === 'follows') compositeIdMismatches = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        for (const field of legacy.uidFields) addToReport(uidReferences[field]!, data[field], uids);
        if (legacy.docId === 'uid') addToReport(uidReferences['(docId)']!, doc.id, uids);
        if (compositeIdMismatches !== undefined && !compositeIdMatches(doc.id, [data['followerId'], data['followedId']])) {
          compositeIdMismatches += 1;
        }
      }
    }

    results.push({
      name,
      expected: Boolean(legacy),
      count,
      schema,
      optionalFields: optionalFields(schema),
      mixedTypeFields: mixedTypeFields(schema),
      uidReferences,
      compositeIdMismatches,
    });
    console.log(`  ${name}: ${count} documentos (muestra ${snap.size})`);
  }

  return {
    results,
    unexpected: names.filter((n) => !expected.has(n)),
    missing: [...expected.keys()].filter((n) => !names.includes(n)).sort(),
  };
}

async function auditSubcollections(): Promise<AuditReport['subcollections']> {
  const out: AuditReport['subcollections'] = [];
  for (const sub of LEGACY_SUBCOLLECTIONS) {
    // listDocuments incluye padres "fantasma" (sin datos) que solo tienen subcolecciones.
    const parents = (await db.collection(sub.parent).listDocuments()).slice(0, sampleSize);
    let docs = 0;
    for (const parent of parents) {
      docs += (await parent.collection(sub.name).count().get()).data().count;
    }
    out.push({ path: `${sub.parent}/{id}/${sub.name}`, parentsSampled: parents.length, docs });
  }
  return out;
}

async function auditStorage(): Promise<AuditReport['storage']> {
  try {
    const bucket = getStorage().bucket();
    const [files] = await bucket.getFiles({ prefix: 'user-files/', autoPaginate: true });
    let bytes = 0;
    const byPurpose: Record<string, number> = {};
    for (const f of files) {
      bytes += Number(f.metadata.size ?? 0);
      const purpose = f.name.split('/')[2] ?? '(desconocido)';
      byPurpose[purpose] = (byPurpose[purpose] ?? 0) + 1;
    }
    return { bucket: bucket.name, files: files.length, bytes, byPurpose };
  } catch (err) {
    return { error: (err as Error).message };
  }
}

async function main() {
  console.log(`Auditoría de solo lectura del proyecto ${projectId} (muestra ${sampleSize})`);
  console.log('→ Firebase Auth');
  const { uids, summary } = await auditAuth();
  console.log(`  ${summary.users} usuarios`);
  console.log('→ Firestore');
  const { results, unexpected, missing } = await auditCollections(uids);
  const subcollections = await auditSubcollections();
  console.log('→ Storage');
  const storage = await auditStorage();

  const report: AuditReport = {
    projectId: projectId!,
    generatedAt: new Date().toISOString(),
    sampleSize,
    auth: summary,
    collections: results,
    unexpectedCollections: unexpected,
    missingCollections: missing,
    subcollections,
    storage,
  };

  mkdirSync(outDir, { recursive: true });
  const stamp = report.generatedAt.replace(/[:.]/g, '-');
  writeFileSync(join(outDir, `audit-${stamp}.json`), JSON.stringify(report, null, 2));
  writeFileSync(join(outDir, `audit-${stamp}.md`), renderMarkdown(report));
  console.log(`Informe escrito en ${outDir}`);
}

main().catch((err) => {
  console.error('La auditoría falló:', (err as Error).message);
  process.exit(1);
});
