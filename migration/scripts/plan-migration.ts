/**
 * Paso 2: transforma una instantánea local en un PLAN de migración, sin
 * conectarse a nada (ni a Firebase ni a Cloudflare).
 *
 * Uso (desde migration/):
 *   npm run plan -- --snapshot output/snapshot-<fecha> [--out output/plan]
 *
 * Genera: sql/*.sql (idempotentes), media-manifest.jsonl, inline/ (imágenes
 * incrustadas), report.md y report.json con lo que se migrará y lo que no.
 */
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { transform } from './transform/run';

const { values } = parseArgs({
  options: {
    snapshot: { type: 'string' },
    out: { type: 'string', default: 'output/plan' },
    migrations: { type: 'string', default: '../worker/migrations' },
  },
});
if (!values.snapshot || !existsSync(values.snapshot)) {
  console.error('Indica una instantánea existente: --snapshot output/snapshot-<fecha>');
  process.exit(2);
}
const out = resolve(values.out ?? 'output/plan');
const { plan, files } = transform(values.snapshot, out, resolve(values.migrations ?? '../worker/migrations'));
console.log(`Plan listo en ${out}`);
console.log(`  ${files.length} archivos SQL, ${plan.media.size} archivos a copiar`);
console.log('  Revisa report.md antes de seguir.');
