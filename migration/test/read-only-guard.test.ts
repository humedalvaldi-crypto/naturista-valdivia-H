import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Salvaguarda: los scripts de auditoría no deben contener operaciones de
 * escritura sobre Firebase. Si en la Fase 8 se añaden escritores, deben vivir
 * en archivos separados y no ejecutarse sin autorización explícita.
 */
const AUDIT_FILES = ['scripts/audit-firestore.ts', ...readdirSync('scripts/lib').map((f) => join('scripts/lib', f))];

const FORBIDDEN = [
  /\.set\(/,
  /\.update\(/,
  /\.delete\(/,
  /\.add\(\s*\{/, // Firestore add({...}); Set.add(uid) está permitido
  /\.batch\(/,
  /\.bulkWriter\(/,
  /runTransaction\(/,
  /recursiveDelete\(/,
  /deleteUser/,
  /updateUser/,
  /createUser/,
  /\.save\(/,
  /\.upload\(/,
  /\.makePublic\(/,
  /setMetadata\(/,
];

describe('auditoría de solo lectura', () => {
  for (const file of AUDIT_FILES) {
    it(`${file} no contiene escrituras a Firebase`, () => {
      const source = readFileSync(file, 'utf8');
      for (const pattern of FORBIDDEN) expect(source, String(pattern)).not.toMatch(pattern);
    });
  }
});
