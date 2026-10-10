/**
 * Auditoría de seguridad (sección 19 del prompt maestro): cada bloque prueba
 * un tipo de ataque contra la API real (D1 local, tokens firmados en la prueba).
 */
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner, PROJECT_ID } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
let callConsent: ReturnType<typeof makeApp>;
const VERSION = '2026-10';

beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
  callConsent = makeApp(signer.jwks, { CONSENT_VERSION: VERSION, MIN_AGE: '14' });
});

const jpeg = () => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0xff, 0xd9]);

async function person(uid: string, opts: { app?: ReturnType<typeof makeApp>; claims?: Record<string, unknown>; iatSec?: number } = {}) {
  const app = opts.app ?? call;
  const token = await signer.sign({ sub: uid, email: `${uid}@example.test`, ...opts.claims }, { iatSec: opts.iatSec });
  const req = (method: string, path: string, body?: unknown, headers: Record<string, string> = {}) =>
    app(`/api/v1${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body !== undefined && !(body instanceof Uint8Array) ? { 'Content-Type': 'application/json' } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : body instanceof Uint8Array ? body : JSON.stringify(body),
    });
  const json = async (method: string, path: string, body?: unknown, headers?: Record<string, string>) => {
    const res = await req(method, path, body, headers);
    const text = await res.text();
    return { status: res.status, body: (text ? JSON.parse(text) : null) as any, text };
  };
  await json('GET', '/me');
  return { uid, token, json, req };
}

const OBS = { observedAt: '2026-10-01T08:00:00Z', latitude: -39.8612, longitude: -73.2345 };

describe('acceso no autorizado', () => {
  it('toda escritura sin token responde 401 y no toca la base', async () => {
    const before = await env.DB.prepare('SELECT count(*) AS n FROM posts').first<{ n: number }>();
    for (const [method, path] of [
      ['POST', '/posts'], ['POST', '/notebooks'], ['POST', '/observations'], ['POST', '/conversations'],
      ['POST', '/media?purpose=post-photo'], ['PATCH', '/me/profile'], ['DELETE', '/me'], ['GET', '/me/export'],
      ['PUT', '/users/x/follow'], ['POST', '/me/sessions/revoke'], ['POST', '/me/consent'],
    ] as const) {
      const res = await call(`/api/v1${path}`, { method, headers: { 'Content-Type': 'application/json' }, body: method === 'GET' ? undefined : '{}' });
      expect(res.status, `${method} ${path}`).toBe(401);
    }
    const after = await env.DB.prepare('SELECT count(*) AS n FROM posts').first<{ n: number }>();
    expect(after!.n).toBe(before!.n);
  });

  it('un token de otro proyecto de Firebase no sirve', async () => {
    const token = await signer.sign({ sub: 'intruso', aud: 'otro-proyecto', iss: 'https://securetoken.google.com/otro-proyecto' });
    const res = await call('/api/v1/me', { headers: { Authorization: `Bearer ${token}` } });
    expect(res.status).toBe(401);
    expect(PROJECT_ID).toBe('test-project');
  });
});

describe('escalada de privilegios y datos de otra persona', () => {
  it('no se puede editar ni borrar lo ajeno, ni cambiar el dueño por parámetros', async () => {
    const ana = await person('sec-esc-ana');
    const beto = await person('sec-esc-beto');
    const nb = (await ana.json('POST', '/notebooks', { title: 'De Ana' })).body.data;
    const obs = (await ana.json('POST', '/observations', { ...OBS, taxonName: 'Coipo' })).body.data;
    const post = (await ana.json('POST', '/posts', { body: 'Hola' })).body.data;

    expect((await beto.json('PATCH', `/notebooks/${nb.id}`, { title: 'Mío' })).status).toBe(404);
    expect((await beto.json('DELETE', `/notebooks/${nb.id}`)).status).toBe(404);
    expect((await beto.json('PATCH', `/observations/${obs.id}`, { notes: 'x' })).status).toBe(404);
    expect((await beto.json('DELETE', `/observations/${obs.id}`)).status).toBe(404);
    expect([403, 404]).toContain((await beto.json('DELETE', `/posts/${post.id}`)).status);
    expect((await beto.json('POST', `/notebooks/${nb.id}/restore`)).status).toBe(404);

    // Campos de identidad en el cuerpo se rechazan (esquemas estrictos).
    expect((await beto.json('POST', '/notebooks', { title: 'x', ownerId: ana.uid })).status).toBe(400);
    expect((await beto.json('POST', '/observations', { ...OBS, taxonName: 'x', ownerId: ana.uid })).status).toBe(400);
    expect((await beto.json('PATCH', '/me/profile', { userId: ana.uid, bio: 'x' })).status).toBe(400);
    expect((await beto.json('PATCH', '/me/settings', { role: 'admin' })).status).toBe(400);

    const still = await env.DB.prepare('SELECT title, owner_id FROM notebooks WHERE id = ?1').bind(nb.id).first();
    expect(still).toEqual({ title: 'De Ana', owner_id: ana.uid });
  });

  it('lo privado de otra persona no existe para mí', async () => {
    const ana = await person('sec-priv-ana');
    const beto = await person('sec-priv-beto');
    const nb = (await ana.json('POST', '/notebooks', { title: 'Privado' })).body.data;
    const obs = (await ana.json('POST', '/observations', { ...OBS, taxonName: 'Coipo', visibility: 'private' })).body.data;
    const conv = (await ana.json('POST', '/conversations', { userId: (await person('sec-priv-cami')).uid })).body.data;

    expect((await beto.json('GET', `/notebooks/${nb.id}`)).status).toBe(404);
    expect((await beto.json('GET', `/notebooks/${nb.id}/pages`)).status).toBe(404);
    expect((await beto.json('GET', `/observations/${obs.id}`)).status).toBe(404);
    expect((await beto.json('GET', `/conversations/${conv.id}/messages`)).status).toBe(404);
    expect((await beto.json('GET', `/notebooks?owner=${ana.uid}`)).body.data).toEqual([]);
    expect((await beto.json('GET', `/observations?user=${ana.uid}`)).body.data).toEqual([]);

    // La exportación solo trae lo propio.
    const exported = (await beto.json('GET', '/me/export')).body;
    expect(JSON.stringify(exported)).not.toContain(ana.uid);
  });

  it('archivos privados: solo su dueña o con enlace firmado', async () => {
    const ana = await person('sec-file-ana');
    const beto = await person('sec-file-beto');
    const up = await ana.req('POST', '/media?purpose=notebook-photo', jpeg(), { 'Content-Type': 'image/jpeg' });
    expect(up.status).toBe(201);
    const id = ((await up.json()) as any).data.id;
    expect((await ana.req('GET', `/media/${id}`)).status).toBe(200);
    expect((await beto.req('GET', `/media/${id}`)).status).toBe(404);
    expect((await call(`/api/v1/media/${id}`)).status).toBe(404);
    // Firma manipulada o vencida: rechazada.
    const link = (await ana.json('POST', `/media/${id}/link`)).body.data.url as string;
    const tampered = link.replace(/sig=[^&]+/, 'sig=AAAA');
    expect((await call(tampered.replace(/^https?:\/\/[^/]+/, ''))).status).toBe(404);
    expect((await beto.json('POST', `/media/${id}/link`)).status).toBe(404);
  });
});

describe('sesiones revocadas y reutilización de tokens', () => {
  it('cerrar sesión en todos los dispositivos invalida los tokens anteriores', async () => {
    const ana = await person('sec-rev-ana');
    expect((await ana.json('POST', '/me/sessions/revoke')).status).toBe(204);
    const res = await ana.json('GET', '/me');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('session_revoked');
    // Un token renovado conserva el auth_time original: sigue rechazado.
    const refreshed = await signer.sign({ sub: ana.uid }, { iatSec: Math.floor(Date.now() / 1000) - 5 });
    expect((await call('/api/v1/notebooks', { method: 'POST', headers: { Authorization: `Bearer ${refreshed}`, 'Content-Type': 'application/json' }, body: '{"title":"x"}' })).status).toBe(401);
    // Un inicio de sesión nuevo (auth_time posterior) funciona.
    await new Promise((r) => setTimeout(r, 1100));
    const fresh = await person(ana.uid, { iatSec: Math.floor(Date.now() / 1000) + 1 });
    expect((await fresh.json('GET', '/me')).status).toBe(200);
  });

  it('un token anterior a la eliminación de la cuenta no revive la cuenta', async () => {
    const ana = await person('sec-del-ana', { iatSec: Math.floor(Date.now() / 1000) - 60 });
    expect((await ana.json('DELETE', '/me', undefined, { 'X-Confirm-Delete': 'ELIMINAR' })).status).toBe(204);
    const again = await ana.json('GET', '/me');
    expect(again.status).toBe(401);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM users WHERE id = ?1').bind(ana.uid).first('n')).toBe(0);
  });

  it('una cuenta suspendida solo puede leer, exportar o eliminar', async () => {
    const ana = await person('sec-susp-ana');
    await env.DB.prepare("UPDATE users SET status = 'suspended' WHERE id = ?1").bind(ana.uid).run();
    expect((await ana.json('POST', '/posts', { body: 'spam' })).status).toBe(403);
    expect((await ana.json('PATCH', '/me/profile', { bio: 'x' })).status).toBe(403);
    expect((await ana.json('GET', '/me/export')).status).toBe(200);
    expect((await ana.json('DELETE', '/me', undefined, { 'X-Confirm-Delete': 'ELIMINAR' })).status).toBe(204);
  });
});

describe('reintentos y operaciones duplicadas', () => {
  it('repetir me gusta, seguir, consentir o borrar no duplica nada', async () => {
    const ana = await person('sec-dup-ana');
    const beto = await person('sec-dup-beto');
    const post = (await ana.json('POST', '/posts', { body: 'Hola' })).body.data;
    await Promise.all([beto.json('PUT', `/posts/${post.id}/like`), beto.json('PUT', `/posts/${post.id}/like`)]);
    await Promise.all([beto.json('PUT', `/users/${ana.uid}/follow`), beto.json('PUT', `/users/${ana.uid}/follow`)]);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM reactions WHERE post_id = ?1').bind(post.id).first('n')).toBe(1);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM follows WHERE followed_id = ?1').bind(ana.uid).first('n')).toBe(1);
    const nb = (await ana.json('POST', '/notebooks', { title: 'x' })).body.data;
    expect((await ana.json('DELETE', `/notebooks/${nb.id}`)).status).toBe(204);
    expect((await ana.json('DELETE', `/notebooks/${nb.id}`)).status).toBe(404);
  });

  it('guardar una página con una versión vieja no pisa otro guardado', async () => {
    const ana = await person('sec-ver-ana');
    const nb = (await ana.json('POST', '/notebooks', { title: 'x' })).body.data;
    const page = (await ana.json('GET', `/notebooks/${nb.id}/pages`)).body.data[0];
    const el = { id: 't', type: 'text', x: 1, y: 1, width: 10, height: 10, data: { text: 'a' } };
    expect((await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [el] })).status).toBe(200);
    expect((await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [] })).status).toBe(409);
  });
});

describe('manipulación de parámetros y validación', () => {
  it('parámetros extraños no rompen ni inyectan SQL', async () => {
    const ana = await person('sec-param-ana');
    for (const q of ["?limit=-5", '?limit=999999', "?cursor=' OR 1=1 --", '?bbox=1,2,3', "?user=' OR '1'='1"]) {
      const res = await ana.json('GET', `/observations${q}`);
      expect([200, 400], q).toContain(res.status);
      expect(res.text).not.toMatch(/SQLITE|stack|at \w+ \(/i);
    }
    expect((await ana.json('GET', '/notebooks/%27%20OR%201%3D1')).status).toBe(404);
    // Cuerpo gigante: 413.
    const big = 'x'.repeat(70 * 1024);
    expect((await ana.req('POST', '/posts', { body: big })).status).toBe(413);
    // Tipo de archivo falso (texto con extensión de imagen): rechazado por la firma.
    const fake = await ana.req('POST', '/media?purpose=post-photo', new TextEncoder().encode('<script>'), { 'Content-Type': 'image/jpeg' });
    expect([400, 415]).toContain(fake.status);
  });
});

describe('filtración de datos sensibles', () => {
  it('los perfiles y listas públicas no muestran correos ni ubicación exacta de especies sensibles', async () => {
    const ana = await person('sec-leak-ana');
    const beto = await person('sec-leak-beto');
    await ana.json('POST', '/posts', { body: 'Hola' });
    const obs = (await ana.json('POST', '/observations', { ...OBS, speciesId: 'sp-lontra-provocax' })).body.data;
    const texts = [
      (await beto.json('GET', `/users/${ana.uid}`)).text,
      (await beto.json('GET', '/posts')).text,
      (await beto.json('GET', `/observations/${obs.id}`)).text,
      await (await call('/api/v1/observations?bbox=-74,-40,-73,-39')).text(),
    ];
    for (const t of texts) expect(t).not.toContain(`${ana.uid}@example.test`);
    const seen = (await beto.json('GET', `/observations/${obs.id}`)).body.data;
    expect(seen.latitude).not.toBe(OBS.latitude);
    expect(seen.obscured).toBe(true);
  });

  it('los errores no exponen detalles internos', async () => {
    const res = await call('/api/v1/me', { headers: { Authorization: 'Bearer abc.def.ghi' } });
    const text = await res.text();
    expect(res.status).toBe(401);
    expect(text).not.toMatch(/abc\.def\.ghi|stack|Error:/);
  });
});

describe('consentimiento y edad mínima', () => {
  it('sin aceptar los términos no se puede publicar; aceptarlos exige ambas casillas y la versión vigente', async () => {
    const ana = await person('sec-consent-ana', { app: callConsent });
    const me = (await ana.json('GET', '/me')).body.data.consent;
    expect(me).toMatchObject({ requiredVersion: VERSION, upToDate: false, minAge: 14 });

    const blocked = await ana.json('POST', '/posts', { body: 'Hola' });
    expect(blocked.status).toBe(428);
    expect(blocked.body.error.code).toBe('consent_required');
    expect((await ana.req('POST', '/media?purpose=post-photo', jpeg(), { 'Content-Type': 'image/jpeg' })).status).toBe(428);
    expect((await ana.json('PATCH', '/me/profile', { bio: 'x' })).status).toBe(428);

    // Intentos de saltarse la confirmación.
    expect((await ana.json('POST', '/me/consent', { version: VERSION, termsAccepted: true, ageConfirmed: false })).status).toBe(400);
    expect((await ana.json('POST', '/me/consent', { version: VERSION, termsAccepted: true })).status).toBe(400);
    expect((await ana.json('POST', '/me/consent', { version: '2020-01', termsAccepted: true, ageConfirmed: true })).status).toBe(400);
    expect((await ana.json('POST', '/me/consent', { version: VERSION, termsAccepted: 'true', ageConfirmed: 1 })).status).toBe(400);
    expect((await ana.json('POST', '/posts', { body: 'Hola' })).status).toBe(428);

    expect((await ana.json('POST', '/me/consent', { version: VERSION, termsAccepted: true, ageConfirmed: true })).status).toBe(204);
    expect((await ana.json('GET', '/me')).body.data.consent.upToDate).toBe(true);
    expect((await ana.json('POST', '/posts', { body: 'Hola' })).status).toBe(201);
    // No se guarda fecha de nacimiento, solo la confirmación.
    const row = await env.DB.prepare('SELECT age_confirmed, consent_version FROM users WHERE id = ?1').bind(ana.uid).first();
    expect(row).toEqual({ age_confirmed: 1, consent_version: VERSION });
  });

  it('una versión nueva de los términos vuelve a pedirlos; leer, denunciar y bloquear no los exige', async () => {
    const ana = await person('sec-consent2-ana', { app: callConsent });
    const beto = await person('sec-consent2-beto', { app: callConsent });
    await ana.json('POST', '/me/consent', { version: VERSION, termsAccepted: true, ageConfirmed: true });
    const newer = makeApp(signer.jwks, { CONSENT_VERSION: '2027-01' });
    const token = await signer.sign({ sub: ana.uid });
    const res = await newer('/api/v1/posts', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"body":"x"}' });
    expect(res.status).toBe(428);

    expect((await beto.json('GET', '/posts')).status).toBe(200);
    expect((await beto.json('PUT', `/users/${ana.uid}/block`)).status).toBe(204);
    expect((await beto.json('POST', '/reports', { targetType: 'user', targetId: ana.uid, reason: 'spam' })).status).toBe(202);
  });
});
