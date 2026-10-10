import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const WORKER_MIGRATIONS = join(import.meta.dirname, '../../../worker/migrations');

/** Base SQLite en memoria con las mismas migraciones que D1 y claves foráneas activas (como D1). */
export function freshDb(): DatabaseSync {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON;');
  for (const f of readdirSync(WORKER_MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    db.exec(readFileSync(join(WORKER_MIGRATIONS, f), 'utf8'));
  }
  return db;
}

export function applyFiles(db: DatabaseSync, dir: string, files: string[]) {
  for (const f of files) db.exec(readFileSync(join(dir, f), 'utf8'));
}

export const count = (db: DatabaseSync, sql: string) => Number((db.prepare(sql).get() as { n: number }).n);
