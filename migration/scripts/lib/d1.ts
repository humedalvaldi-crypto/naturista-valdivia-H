import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { redact } from './redact';

export const WORKER_DIR = join(import.meta.dirname, '../../../worker');

/** Nombre de la base D1 declarado en worker/wrangler.toml. */
export function databaseName(): string {
  const toml = readFileSync(join(WORKER_DIR, 'wrangler.toml'), 'utf8');
  const m = toml.match(/database_name\s*=\s*"([^"]+)"/);
  if (!m) throw new Error('No se encontró database_name en worker/wrangler.toml');
  return m[1]!;
}

export type Target = { kind: 'local' } | { kind: 'remote' };

function wrangler(args: string[]): string {
  const res = spawnSync('npx', ['wrangler', ...args], { cwd: WORKER_DIR, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (res.status !== 0) throw new Error(`wrangler ${args.slice(0, 3).join(' ')} falló:\n${redact((res.stderr || res.stdout).slice(-2000))}`);
  return res.stdout;
}

const flag = (t: Target) => (t.kind === 'remote' ? '--remote' : '--local');

export function executeFile(db: string, target: Target, file: string) {
  wrangler(['d1', 'execute', db, flag(target), '--file', file, '--yes']);
}

export function query(db: string, target: Target, sql: string): Record<string, unknown>[] {
  const out = wrangler(['d1', 'execute', db, flag(target), '--command', sql, '--json']);
  const parsed = JSON.parse(out.slice(out.indexOf('['))) as { results?: Record<string, unknown>[] }[];
  return parsed.flatMap((p) => p.results ?? []);
}

export function exportBackup(db: string, file: string) {
  wrangler(['d1', 'export', db, '--remote', '--output', file]);
}
