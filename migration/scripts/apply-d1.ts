/**
 * Paso 4: aplica el plan a D1, archivo por archivo, con puntos de control.
 *
 * Uso (desde migration/):
 *   # Ensayo en la base LOCAL de wrangler (no toca Cloudflare):
 *   npm run apply -- --plan output/plan
 *
 *   # Base REMOTA (staging o producción). Exige escribir el nombre de la base
 *   # en --confirm y hace antes un respaldo completo con `wrangler d1 export`:
 *   npm run apply -- --plan output/plan --remote --mode staging --confirm <nombre-de-la-base>
 *
 * El SQL es idempotente (ON CONFLICT DO NOTHING): repetir o reanudar no duplica.
 * Los archivos ya aplicados en este destino se saltan (ver <plan>/applied-*.json).
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { databaseName, executeFile, exportBackup, query, type Target } from './lib/d1';
import { lit } from './transform/sql';

const { values } = parseArgs({
  options: {
    plan: { type: 'string', default: 'output/plan' },
    database: { type: 'string' },
    remote: { type: 'boolean', default: false },
    mode: { type: 'string', default: 'dry-run' },
    confirm: { type: 'string' },
    'skip-backup': { type: 'boolean', default: false },
  },
});

const planDir = resolve(values.plan ?? 'output/plan');
const sqlDir = join(planDir, 'sql');
if (!existsSync(sqlDir)) {
  console.error(`No hay SQL en ${sqlDir}. Ejecuta antes: npm run plan`);
  process.exit(2);
}
const db = values.database ?? databaseName();
const target: Target = values.remote ? { kind: 'remote' } : { kind: 'local' };
const mode = values.mode ?? 'dry-run';

if (target.kind === 'remote') {
  if (mode !== 'staging' && mode !== 'production') {
    console.error('En una base remota indica --mode staging o --mode production.');
    process.exit(2);
  }
  if (values.confirm !== db) {
    console.error(`Para escribir en la base remota "${db}" repite su nombre: --confirm ${db}`);
    process.exit(2);
  }
} else if (mode !== 'dry-run') {
  console.error('En la base local el modo es siempre dry-run.');
  process.exit(2);
}

const files = readdirSync(sqlDir).filter((f) => f.endsWith('.sql')).sort();
const stateFile = join(planDir, `applied-${target.kind === 'remote' ? `remote-${db}` : 'local'}.json`);
const state = existsSync(stateFile) ? (JSON.parse(readFileSync(stateFile, 'utf8')) as { runId: string; applied: string[] }) : null;
const applied = new Set(state?.applied ?? []);
const runId = state?.runId ?? crypto.randomUUID();

if (target.kind === 'remote' && !values['skip-backup']) {
  const backups = resolve('backups');
  mkdirSync(backups, { recursive: true });
  const file = join(backups, `${db}-${new Date().toISOString().replace(/[:.]/g, '-')}.sql`);
  console.log(`Respaldo previo de ${db} → ${file}`);
  exportBackup(db, file);
}

console.log(`Aplicando ${files.length - applied.size} de ${files.length} archivos a ${db} (${target.kind}, ${mode}). Ejecución ${runId}`);
const save = () => writeFileSync(stateFile, JSON.stringify({ runId, applied: [...applied] }, null, 2));

query(db, target, `INSERT INTO migration_runs (id, mode) VALUES (${lit(runId)}, ${lit(mode)}) ON CONFLICT (id) DO UPDATE SET status = 'running', finished_at = NULL`);
try {
  for (const f of files) {
    if (applied.has(f)) continue;
    const statements = readFileSync(join(sqlDir, f), 'utf8').split('\n').filter((l) => /^(INSERT|UPDATE)\b/.test(l)).length;
    process.stdout.write(`  ${f} (${statements} sentencias)… `);
    executeFile(db, target, join(sqlDir, f));
    applied.add(f);
    save();
    query(
      db,
      target,
      `INSERT INTO migration_checkpoints (run_id, collection, last_doc_id, processed) VALUES (${lit(runId)}, ${lit(f)}, NULL, ${statements})
       ON CONFLICT (run_id, collection) DO UPDATE SET processed = excluded.processed, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
    );
    console.log('ok');
  }
  query(db, target, `UPDATE migration_runs SET status = 'completed', finished_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ${lit(runId)}`);
  console.log('Listo. Ahora: npm run validate');
} catch (err) {
  query(db, target, `UPDATE migration_runs SET status = 'failed', finished_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ${lit(runId)}`);
  console.error(err instanceof Error ? err.message : err);
  console.error('Se detuvo. Corrige y vuelve a ejecutar: continuará desde el archivo que falló.');
  process.exit(1);
}
