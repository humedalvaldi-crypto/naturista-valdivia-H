import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner, PROJECT_ID } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;

beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

describe('GET /api/v1/health', () => {
  it('responde ok y comprueba D1', async () => {
    const res = await call('/api/v1/health');
    expect(res.status).toBe(200);
    const body = await res.json<{ status: string; checks: { database: string } }>();
    expect(body.status).toBe('ok');
    expect(body.checks.database).toBe('ok');
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(res.headers.get('X-Request-Id')).toBeTruthy();
  });
});

describe('errores uniformes', () => {
  it('404 en JSON para rutas inexistentes', async () => {
    const res = await call('/api/v1/no-existe');
    expect(res.status).toBe(404);
    const body = await res.json<{ error: { code: string } }>();
    expect(body.error.code).toBe('not_found');
  });
});

describe('verificación de identidad (Firebase ID token)', () => {
  it('rechaza peticiones sin token', async () => {
    const res = await call('/api/v1/me');
    expect(res.status).toBe(401);
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe('unauthorized');
  });

  it('rechaza un token malformado', async () => {
    const res = await call('/api/v1/me', { headers: bearer('no.es.un-token') });
    expect(res.status).toBe(401);
  });

  it('rechaza un token firmado con otra clave', async () => {
    const other = await makeSigner('test-kid'); // mismo kid, otra clave
    const res = await call('/api/v1/me', { headers: bearer(await other.sign()) });
    expect(res.status).toBe(401);
  });

  it('rechaza un token con kid desconocido', async () => {
    const res = await call('/api/v1/me', { headers: bearer(await signer.sign({}, { kid: 'otro' })) });
    expect(res.status).toBe(401);
  });

  it('rechaza audiencia incorrecta', async () => {
    const res = await call('/api/v1/me', { headers: bearer(await signer.sign({ aud: 'otro-proyecto' })) });
    expect(res.status).toBe(401);
  });

  it('rechaza emisor incorrecto', async () => {
    const res = await call('/api/v1/me', {
      headers: bearer(await signer.sign({ iss: 'https://securetoken.google.com/otro' })),
    });
    expect(res.status).toBe(401);
  });

  it('rechaza un token expirado con mensaje de sesión expirada', async () => {
    const now = Math.floor(Date.now() / 1000);
    const token = await signer.sign({}, { iatSec: now - 7200, expSec: now - 3600 });
    const res = await call('/api/v1/me', { headers: bearer(token) });
    expect(res.status).toBe(401);
    expect((await res.json<{ error: { message: string } }>()).error.message).toMatch(/expiró/);
  });

  it('rechaza auth_time en el futuro', async () => {
    const future = Math.floor(Date.now() / 1000) + 3600;
    const res = await call('/api/v1/me', { headers: bearer(await signer.sign({ auth_time: future })) });
    expect(res.status).toBe(401);
  });

  it('acepta un token válido y crea el usuario con el UID de Firebase', async () => {
    const token = await signer.sign({ sub: 'uid-bob', email: 'bob@example.test', email_verified: true, name: 'Bob' });
    const res = await call('/api/v1/me', { headers: bearer(token) });
    expect(res.status).toBe(200);
    const body = await res.json<{ data: { user: { id: string; email: string; authProvider: string }; settings: { language: string } } }>();
    expect(body.data.user.id).toBe('uid-bob');
    expect(body.data.user.authProvider).toBe('google.com');
    expect(body.data.settings.language).toBe('es');

    const row = await env.DB.prepare('SELECT id, email FROM users WHERE id = ?1').bind('uid-bob').first();
    expect(row).toMatchObject({ id: 'uid-bob', email: 'bob@example.test' });
  });

  it('es idempotente: llamadas repetidas no duplican al usuario', async () => {
    const token = await signer.sign({ sub: 'uid-carla', name: 'Carla' });
    await call('/api/v1/me', { headers: bearer(token) });
    await call('/api/v1/me', { headers: bearer(token) });
    const { n } = (await env.DB.prepare('SELECT COUNT(*) AS n FROM users WHERE id = ?1').bind('uid-carla').first<{ n: number }>())!;
    expect(n).toBe(1);
  });
});

describe('PATCH /api/v1/me/settings', () => {
  it('valida la entrada', async () => {
    const token = await signer.sign({ sub: 'uid-dani' });
    for (const body of [{}, { language: 'fr' }, { theme: 'neon' }, { language: 'es', isAdmin: true }]) {
      const res = await call('/api/v1/me/settings', {
        method: 'PATCH',
        headers: { ...bearer(token), 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
    const bad = await call('/api/v1/me/settings', {
      method: 'PATCH',
      headers: { ...bearer(token), 'Content-Type': 'application/json' },
      body: '{no json',
    });
    expect(bad.status).toBe(400);
  });

  it('guarda solo las preferencias del usuario del token', async () => {
    const alice = await signer.sign({ sub: 'uid-alice2' });
    const eve = await signer.sign({ sub: 'uid-eve' });
    await call('/api/v1/me', { headers: bearer(alice) });

    const res = await call('/api/v1/me/settings', {
      method: 'PATCH',
      headers: { ...bearer(eve), 'Content-Type': 'application/json' },
      body: JSON.stringify({ language: 'en', theme: 'dark' }),
    });
    expect(res.status).toBe(200);
    expect((await res.json<{ data: { language: string; theme: string } }>()).data).toMatchObject({ language: 'en', theme: 'dark' });

    const aliceSettings = await env.DB.prepare('SELECT language, theme FROM user_settings WHERE user_id = ?1').bind('uid-alice2').first();
    expect(aliceSettings).toMatchObject({ language: 'es', theme: 'system' });
  });

  it('rechaza cuerpos demasiado grandes', async () => {
    const token = await signer.sign({ sub: 'uid-big' });
    const res = await call('/api/v1/me/settings', {
      method: 'PATCH',
      headers: { ...bearer(token), 'Content-Type': 'application/json' },
      body: JSON.stringify({ language: 'es', pad: 'x'.repeat(70 * 1024) }),
    });
    expect(res.status).toBe(413);
  });
});

describe('CORS', () => {
  it('permite solo orígenes de la lista blanca', async () => {
    const ok = await call('/api/v1/health', { headers: { Origin: 'https://app.example.test' } });
    expect(ok.headers.get('Access-Control-Allow-Origin')).toBe('https://app.example.test');

    const denied = await call('/api/v1/health', { headers: { Origin: 'https://malicioso.example' } });
    expect(denied.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('responde al preflight', async () => {
    const res = await call('/api/v1/me', {
      method: 'OPTIONS',
      headers: { Origin: 'http://localhost:8080', 'Access-Control-Request-Method': 'GET', 'Access-Control-Request-Headers': 'authorization' },
    });
    expect(res.status).toBe(204);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:8080');
  });
});

describe('configuración', () => {
  it('usa el proyecto de prueba', () => {
    expect(env.FIREBASE_PROJECT_ID).toBe(PROJECT_ID);
  });
});
