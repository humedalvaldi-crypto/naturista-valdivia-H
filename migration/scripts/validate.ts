/**
 * Paso 5: valida la base de destino contra el plan (conteos, claves
 * foráneas, ubicaciones protegidas, archivos y hashes). Solo lee.
 *
 * Uso: npm run validate -- --plan output/plan [--remote] [--database <nombre>]
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { databaseName, query, type Target } from './lib/d1';
import type { CopiedMedia } from './transform/media-copy';
import type { PlanReport } from './transform/run';
import { renderChecks, validate } from './transform/validate-core';

const { values } = parseArgs({
  options: { plan: { type: 'string', default: 'output/plan' }, database: { type: 'string' }, remote: { type: 'boolean', default: false } },
});
const planDir = resolve(values.plan ?? 'output/plan');
const report = JSON.parse(readFileSync(join(planDir, 'report.json'), 'utf8')) as PlanReport;
const doneFile = join(planDir, 'media-done.jsonl');
const copied = existsSync(doneFile)
  ? readFileSync(doneFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l) as CopiedMedia)
  : [];
const db = values.database ?? databaseName();
const target: Target = values.remote ? { kind: 'remote' } : { kind: 'local' };

const checks = await validate(async (sql) => query(db, target, sql), report, copied);
const md = renderChecks(checks);
writeFileSync(join(planDir, `validation-${target.kind}.md`), md);
console.log(md);
process.exit(checks.every((c) => c.ok) ? 0 : 1);
