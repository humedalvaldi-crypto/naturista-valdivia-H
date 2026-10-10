import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import {
  Context,
  mapAuthUser,
  mapChatMessages,
  mapFileAsset,
  mapFollow,
  mapGroup,
  mapGroupMember,
  mapNotebook,
  mapNotebookPages,
  mapObservation,
  mapPlace,
  mapPost,
  mapProfile,
  mapSettings,
  mapSpecies,
  recountStatements,
  type AuthUser,
  type CatalogSpecies,
  type SnapshotDoc,
} from './mappers';
import { Plan, STAGES } from './plan';
import { lit } from './sql';

/** Colecciones que se leen pero, por decisión, no se migran (quedan en el informe). */
export const NOT_MIGRATED: Record<string, string> = {
  notebook_likes: 'los "me gusta" de cuadernos no existen en la app nueva',
  notifications: 'avisos antiguos y efímeros; la app nueva genera los suyos',
  users__notifications: 'avisos antiguos y efímeros; la app nueva genera los suyos',
  reports: 'mensajes de contacto con correos personales; se revisan a mano, no se migran',
  species_album: 'álbum de especies aún sin equivalente en la app nueva',
  user_collections: 'colecciones desbloqueadas aún sin equivalente en la app nueva',
  profile_views: 'registro de visitas a perfiles: no se conserva (privacidad)',
};

const STATEMENTS_PER_FILE = 400;

function readJsonl<T>(file: string): T[] {
  if (!existsSync(file)) return [];
  return readFileSync(file, 'utf8')
    .split('\n')
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l) as T);
}

/** Especies del catálogo inicial (migración 0005 del Worker), para reconocer nombres. */
export function seedCatalog(migrationsDir: string): CatalogSpecies[] {
  const file = join(migrationsDir, '0005_observations.sql');
  if (!existsSync(file)) return [];
  const out: CatalogSpecies[] = [];
  const re = /^\s*\('([^']+)', '([^']+)', '([^']*)', '[^']*', '[a-z]+', '[A-Z]{2}', '[a-z]+', ([01]),/gm;
  for (const m of readFileSync(file, 'utf8').matchAll(re)) {
    out.push({ id: m[1]!, scientificName: m[2]!, commonNameEs: m[3] || null, sensitive: m[4] === '1' });
  }
  return out;
}

export interface TransformResult {
  plan: Plan;
  files: string[];
}

export function transform(snapshotDir: string, outDir: string, migrationsDir: string): TransformResult {
  const plan = new Plan();
  const ctx = new Context(plan, seedCatalog(migrationsDir));
  const fsDir = join(snapshotDir, 'firestore');
  const col = (name: string) => readJsonl<SnapshotDoc>(join(fsDir, `${name}.jsonl`));

  for (const u of readJsonl<AuthUser>(join(snapshotDir, 'auth-users.jsonl'))) mapAuthUser(ctx, u);
  for (const d of col('settings')) mapSettings(ctx, d);
  for (const d of col('species_catalog')) mapSpecies(ctx, d);
  for (const d of col('user_file_assets')) mapFileAsset(ctx, d);
  for (const d of col('profiles')) mapProfile(ctx, d);
  for (const d of col('groups')) mapGroup(ctx, d);
  for (const d of col('group_members')) mapGroupMember(ctx, d);
  for (const d of col('follows')) mapFollow(ctx, d);
  for (const d of col('posts')) mapPost(ctx, d);
  for (const d of col('notebooks')) mapNotebook(ctx, d);
  mapNotebookPages(ctx, col('notebook_pages'));
  for (const d of col('observations')) mapObservation(ctx, d);
  mapChatMessages(ctx, col('chat_messages'));
  for (const d of col('places')) mapPlace(ctx, d, 'places');
  for (const d of col('wetlands')) mapPlace(ctx, d, 'wetlands');
  for (const s of recountStatements()) plan.statements.get('900-recount')!.push(s);
  // Enlaza archivos copiados después del contenido (solo si la columna sigue vacía y el archivo existe).
  for (const l of plan.relinks) {
    const where = Object.entries(l.where).map(([k, v]) => `${k} = ${lit(v)}`).join(' AND ');
    plan.statements.get('910-relink-media')!.push(
      `UPDATE ${l.table} SET ${l.column} = ${lit(l.assetId)} WHERE ${where} AND ${l.column} IS NULL AND EXISTS (SELECT 1 FROM media_assets WHERE id = ${lit(l.assetId)});`,
    );
  }

  const handled = new Set([
    'settings', 'species_catalog', 'user_file_assets', 'profiles', 'groups', 'group_members', 'follows', 'posts',
    'notebooks', 'notebook_pages', 'observations', 'chat_messages', 'places', 'wetlands',
  ]);
  if (existsSync(fsDir)) {
    for (const file of readdirSync(fsDir).filter((f) => f.endsWith('.jsonl'))) {
      const name = file.replace(/\.jsonl$/, '');
      if (handled.has(name)) continue;
      const stats = plan.collection(name);
      stats.read = col(name).length;
      const reason = NOT_MIGRATED[name] ?? 'colección no prevista en el inventario: revisar antes de migrar';
      if (stats.read > 0) stats.skipped[reason] = stats.read;
    }
  }

  // Salida: SQL por etapas en archivos de hasta 400 sentencias.
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(join(outDir, 'sql'), { recursive: true });
  mkdirSync(join(outDir, 'inline'), { recursive: true });
  const files: string[] = [];
  for (const stage of STAGES) {
    const list = plan.statements.get(stage)!;
    for (let i = 0, part = 1; i < list.length; i += STATEMENTS_PER_FILE, part++) {
      const name = `${stage}-p${String(part).padStart(3, '0')}.sql`;
      writeFileSync(join(outDir, 'sql', name), `-- ${stage} (parte ${part})\n${list.slice(i, i + STATEMENTS_PER_FILE).join('\n')}\n`);
      files.push(name);
    }
  }
  for (const f of plan.inline) writeFileSync(join(outDir, 'inline', f.name), f.bytes);
  writeFileSync(join(outDir, 'media-manifest.jsonl'), [...plan.media.values()].map((m) => JSON.stringify(m)).join('\n') + (plan.media.size ? '\n' : ''));

  const report = buildReport(plan, snapshotDir, files);
  writeFileSync(join(outDir, 'report.json'), JSON.stringify(report, null, 2));
  writeFileSync(join(outDir, 'report.md'), renderReport(report));
  return { plan, files };
}

export interface PlanReport {
  generatedAt: string;
  snapshot: string;
  sqlFiles: string[];
  expected: Record<string, number>;
  media: { total: number; fromStorage: number; inline: number; byPurpose: Record<string, number>; externalHosts: Record<string, number> };
  collections: Record<string, ReturnType<Plan['collection']>>;
}

function buildReport(plan: Plan, snapshotDir: string, files: string[]): PlanReport {
  const expected: Record<string, number> = {};
  for (const s of plan.stats.values()) for (const [t, n] of Object.entries(s.written)) expected[t] = (expected[t] ?? 0) + n;
  const byPurpose: Record<string, number> = {};
  let inline = 0;
  for (const m of plan.media.values()) {
    byPurpose[m.purpose] = (byPurpose[m.purpose] ?? 0) + 1;
    if (m.source.kind === 'inline') inline++;
  }
  return {
    generatedAt: new Date().toISOString(),
    snapshot: resolve(snapshotDir),
    sqlFiles: files,
    expected,
    media: {
      total: plan.media.size,
      fromStorage: plan.media.size - inline,
      inline,
      byPurpose,
      externalHosts: Object.fromEntries(plan.externalUrls),
    },
    collections: Object.fromEntries([...plan.stats.entries()].sort(([a], [b]) => a.localeCompare(b))),
  };
}

export function renderReport(r: PlanReport): string {
  const lines = [
    '# Plan de migración (ensayo, sin escribir nada)',
    '',
    `Generado: ${r.generatedAt}`,
    '',
    '## Filas que se crearán',
    '',
    '| Tabla | Filas |',
    '|---|---:|',
    ...Object.entries(r.expected).sort().map(([t, n]) => `| ${t} | ${n} |`),
    '',
    `## Archivos: ${r.media.total} (${r.media.fromStorage} de Storage, ${r.media.inline} imágenes incrustadas)`,
    '',
    ...Object.entries(r.media.byPurpose).map(([p, n]) => `- ${p}: ${n}`),
    ...(Object.keys(r.media.externalHosts).length
      ? ['', 'URLs fuera de Firebase Storage (no se copian):', ...Object.entries(r.media.externalHosts).map(([h, n]) => `- ${h}: ${n}`)]
      : []),
    '',
    '## Por colección',
  ];
  for (const [name, s] of Object.entries(r.collections)) {
    lines.push('', `### ${name} — ${s.read} leídos`);
    const written = Object.entries(s.written);
    if (written.length) lines.push(`Escritos: ${written.map(([t, n]) => `${t} ${n}`).join(', ')}`);
    for (const [reason, n] of Object.entries(s.skipped)) lines.push(`- ${reason}: ${n}`);
    const personal = Object.entries(s.excludedPersonalFields);
    if (personal.length) lines.push(`- Datos personales NO migrados (D2): ${personal.map(([f, n]) => `${f} (${n})`).join(', ')}`);
    const unmapped = Object.entries(s.unmappedFields).sort((a, b) => b[1] - a[1]);
    if (unmapped.length) lines.push(`- Campos sin mapear (revisar): ${unmapped.map(([f, n]) => `\`${f}\` (${n})`).join(', ')}`);
    for (const note of s.notes) lines.push(`- ${note}`);
  }
  return `${lines.join('\n')}\n`;
}
