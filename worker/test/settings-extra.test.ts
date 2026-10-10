import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

async function person(uid: string) {
  const token = await signer.sign({ sub: uid });
  const json = async (method: string, path: string, body?: unknown) => {
    const res = await call(`/api/v1${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: (res.status === 204 ? null : await res.json()) as any };
  };
  await json('GET', '/me');
  return { uid, json };
}

describe('preferencias del servidor', () => {
  it('por defecto todos los avisos y mensajes de cualquiera; se guardan por partes', async () => {
    const ana = await person('set-ana');
    expect((await ana.json('GET', '/me/settings')).body.data).toMatchObject({
      notifications: { follow: true, comment: true, reaction: true, message: true },
      privacy: { messages: 'everyone' },
    });
    await ana.json('PATCH', '/me/settings', { notifications: { follow: false } });
    await ana.json('PATCH', '/me/settings', { privacy: { messages: 'following' }, theme: 'dark' });
    const s = (await ana.json('GET', '/me/settings')).body.data;
    expect(s).toMatchObject({ theme: 'dark', notifications: { follow: false, comment: true }, privacy: { messages: 'following' } });
    expect((await ana.json('PATCH', '/me/settings', { notifications: { spam: true } })).status).toBe(400);
  });

  it('un aviso desactivado no se crea', async () => {
    const ana = await person('set-notif-ana');
    const beto = await person('set-notif-beto');
    await ana.json('PATCH', '/me/settings', { notifications: { follow: false } });
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    expect((await ana.json('GET', '/me/notifications')).body.data).toEqual([]);
    await ana.json('PATCH', '/me/settings', { notifications: { follow: true } });
    await beto.json('DELETE', `/users/${ana.uid}/follow`);
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    expect((await ana.json('GET', '/me/notifications')).body.data).toHaveLength(1);
  });

  it('quién puede escribirme: nadie, solo a quienes sigo, todos', async () => {
    const ana = await person('set-msg-ana');
    const beto = await person('set-msg-beto');
    await ana.json('PATCH', '/me/settings', { privacy: { messages: 'nobody' } });
    expect((await beto.json('POST', '/conversations', { userId: ana.uid })).status).toBe(403);

    await ana.json('PATCH', '/me/settings', { privacy: { messages: 'following' } });
    expect((await beto.json('POST', '/conversations', { userId: ana.uid })).status).toBe(403);
    await ana.json('PUT', `/users/${beto.uid}/follow`);
    const conv = (await beto.json('POST', '/conversations', { userId: ana.uid })).body.data;
    expect((await beto.json('POST', `/conversations/${conv.id}/messages`, { body: 'Hola' })).status).toBe(201);

    // Si deja de seguirlo, la conversación existe pero no se pueden enviar más.
    await ana.json('DELETE', `/users/${beto.uid}/follow`);
    expect((await beto.json('POST', `/conversations/${conv.id}/messages`, { body: 'Hola otra vez' })).status).toBe(403);
    // Ana sí puede escribirle a Beto (la regla es de quien recibe).
    expect((await ana.json('POST', `/conversations/${conv.id}/messages`, { body: 'Hola Beto' })).status).toBe(201);
  });
});

describe('estadísticas, bloqueos y contacto', () => {
  it('estadísticas propias', async () => {
    const ana = await person('stats-ana');
    await ana.json('POST', '/observations', { speciesId: 'sp-lontra-provocax', observedAt: '2026-10-01T08:00:00Z', latitude: -39.86, longitude: -73.23 });
    await ana.json('POST', '/observations', { taxonName: 'Coipo', observedAt: '2026-09-01T08:00:00Z', latitude: -39.8, longitude: -73.2 });
    await ana.json('POST', '/notebooks', { title: 'Uno' });
    const s = (await ana.json('GET', '/me/stats')).body.data;
    expect(s).toMatchObject({ observations: 2, speciesObserved: 1, notebooks: 1, pages: 1, posts: 0, followers: 0, storageBytes: 0 });
    expect(s.firstObservationAt).toContain('2026-09-01');
  });

  it('lista de bloqueados', async () => {
    const ana = await person('blk-ana');
    const beto = await person('blk-beto');
    await ana.json('PUT', `/users/${beto.uid}/block`);
    expect((await ana.json('GET', '/me/blocked')).body.data.map((p: any) => p.id)).toEqual([beto.uid]);
    await ana.json('DELETE', `/users/${beto.uid}/block`);
    expect((await ana.json('GET', '/me/blocked')).body.data).toEqual([]);
  });

  it('mensaje al equipo', async () => {
    const ana = await person('fb-ana');
    expect((await ana.json('POST', '/me/feedback', { kind: 'bug', message: 'El mapa no carga', appVersion: '0.1.0', platform: 'web' })).status).toBe(201);
    expect((await ana.json('POST', '/me/feedback', { kind: 'bug', message: '' })).status).toBe(400);
    const row = await env.DB.prepare('SELECT kind, message, status FROM feedback WHERE user_id = ?1').bind(ana.uid).first();
    expect(row).toEqual({ kind: 'bug', message: 'El mapa no carga', status: 'open' });
    expect((await call('/api/v1/me/feedback', { method: 'POST' })).status).toBe(401);
  });
});
