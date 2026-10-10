import { describe, expect, it } from 'vitest';
import { redact } from '../scripts/lib/redact';

describe('censura de mensajes para registros públicos', () => {
  it('oculta textos de SQL, correos, rutas, UIDs y bytes', () => {
    const msg =
      "SQLITE_CONSTRAINT: INSERT INTO posts (id, body) VALUES ('p1', 'Hola, soy Ana Rojas, mi fono es 9 1111 1111') " +
      "ana.rojas@example.cl user-files/AbCdEfGhIjKlMnOpQrStUvWxYz12/avatar/a.jpg AbCdEfGhIjKlMnOpQrStUvWxYz12 X'ffd8ffe0'";
    const out = redact(msg);
    expect(out).not.toContain('Ana Rojas');
    expect(out).not.toContain('example.cl');
    expect(out).not.toContain('AbCdEfGhIjKlMnOpQrStUvWxYz12');
    expect(out).not.toContain('ffd8');
    expect(out).toContain('SQLITE_CONSTRAINT');
    expect(out).toContain('INSERT INTO posts');
  });
});
