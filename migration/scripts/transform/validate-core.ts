import type { CopiedMedia } from './media-copy';
import type { PlanReport } from './run';
import { lit } from './sql';

export type Query = (sql: string) => Promise<Record<string, unknown>[]>;

export interface Check {
  name: string;
  ok: boolean;
  expected?: number | string;
  actual?: number | string;
  detail?: string;
}

/** Tablas donde cada fila migrada se reconoce por su ID antiguo: el conteo debe ser exacto. */
const EXACT: Record<string, string> = {
  users: "legacy_source = 'firestore'",
  posts: 'legacy_id IS NOT NULL',
  notebooks: 'legacy_id IS NOT NULL',
  notebook_pages: 'legacy_id IS NOT NULL',
  observations: 'legacy_id IS NOT NULL',
  messages: 'legacy_id IS NOT NULL',
  communities: 'legacy_id IS NOT NULL',
  places: 'legacy_id IS NOT NULL',
  conversations: 'legacy_chat_id IS NOT NULL',
};

const num = (rows: Record<string, unknown>[]) => Number(rows[0]?.['n'] ?? 0);

/** Compara la base de destino con lo que el plan dijo que crearía. */
export async function validate(query: Query, report: PlanReport, copied: CopiedMedia[]): Promise<Check[]> {
  const checks: Check[] = [];

  for (const [table, expected] of Object.entries(report.expected)) {
    const where = EXACT[table];
    const actual = num(await query(`SELECT count(*) AS n FROM ${table}${where ? ` WHERE ${where}` : ''}`));
    // Tablas sin ID antiguo pueden tener además filas nuevas: basta con que estén todas.
    const ok = where ? actual === expected : actual >= expected;
    checks.push({ name: `filas en ${table}`, ok, expected: where ? expected : `≥ ${expected}`, actual });
  }

  const fk = await query('PRAGMA foreign_key_check');
  checks.push({ name: 'claves foráneas', ok: fk.length === 0, expected: 0, actual: fk.length, detail: fk.length ? JSON.stringify(fk.slice(0, 5)) : undefined });

  const exposed = num(
    await query(
      `SELECT count(*) AS n FROM observations o JOIN species s ON s.id = o.species_id
       WHERE s.sensitive = 1 AND (o.obscured = 0 OR (o.public_latitude = o.latitude AND o.public_longitude = o.longitude))`,
    ),
  );
  checks.push({ name: 'especies sensibles con ubicación protegida', ok: exposed === 0, expected: 0, actual: exposed });

  if (copied.length > 0) {
    let present = 0;
    for (let i = 0; i < copied.length; i += 80) {
      const ids = copied.slice(i, i + 80).map((m) => lit(m.assetId)).join(', ');
      present += num(await query(`SELECT count(*) AS n FROM media_assets WHERE id IN (${ids})`));
    }
    checks.push({ name: 'archivos copiados registrados en media_assets', ok: present === copied.length, expected: copied.length, actual: present });
    let badHash = 0;
    for (let i = 0; i < copied.length; i += 80) {
      const chunk = copied.slice(i, i + 80);
      const rows = await query(`SELECT id, sha256, size_bytes FROM media_assets WHERE id IN (${chunk.map((m) => lit(m.assetId)).join(', ')})`);
      const byId = new Map(rows.map((r) => [String(r['id']), r]));
      for (const m of chunk) {
        const r = byId.get(m.assetId);
        if (r && (r['sha256'] !== m.sha256 || Number(r['size_bytes']) !== m.size)) badHash++;
      }
    }
    checks.push({ name: 'hash y tamaño de archivos coinciden con lo subido', ok: badHash === 0, expected: 0, actual: badHash });
  }
  return checks;
}

export function renderChecks(checks: Check[]): string {
  const lines = ['| Comprobación | Esperado | Real | |', '|---|---:|---:|---|'];
  for (const c of checks) lines.push(`| ${c.name} | ${c.expected ?? ''} | ${c.actual ?? ''} | ${c.ok ? '✅' : '❌'} |`);
  const failed = checks.filter((c) => !c.ok);
  for (const c of failed) if (c.detail) lines.push('', `${c.name}: ${c.detail}`);
  lines.push('', failed.length === 0 ? '**Validación correcta.**' : `**${failed.length} comprobaciones fallidas.**`);
  return `${lines.join('\n')}\n`;
}
