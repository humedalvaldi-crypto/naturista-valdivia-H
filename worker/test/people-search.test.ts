import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

async function person(uid: string, profile?: Record<string, unknown>) {
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
  if (profile) await json('PATCH', '/me/profile', profile);
  return { uid, json };
}

describe('buscar personas', () => {
  it('por nombre o usuario, paginado sin límite fijo, sin privados ni bloqueados', async () => {
    const yo = await person('ps-yo', { fullName: 'Yo Buscadora', username: 'yo.busca' });
    for (let i = 0; i < 7; i++) await person(`ps-garza-${i}`, { fullName: `Garza Observadora ${i}`, username: `garza${i}` });
    await person('ps-priv', { fullName: 'Garza Privada', username: 'garzapriv', visibility: 'private' });
    const bloq = await person('ps-bloq', { fullName: 'Garza Bloqueada', username: 'garzabloq' });
    await yo.json('PUT', `/users/${bloq.uid}/block`);

    const seen: string[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const res = await yo.json('GET', `/users?q=GARZA&limit=3${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(res.status).toBe(200);
      seen.push(...res.body.data.map((p: any) => p.username));
      cursor = res.body.nextCursor;
      pages++;
    } while (cursor && pages < 10);
    expect(seen).toEqual(['garza0', 'garza1', 'garza2', 'garza3', 'garza4', 'garza5', 'garza6']);
    expect(pages).toBe(3);
    expect((await yo.json('GET', '/users?q=g')).status).toBe(400);
    // Caracteres comodín no se interpretan.
    expect((await yo.json('GET', '/users?q=%25%25')).body.data).toEqual([]);
  });

  it('indica "te sigue" y "lo sigues" en ambos sentidos', async () => {
    const ana = await person('ps-ana', { fullName: 'Ana Coipo' });
    const beto = await person('ps-beto', { fullName: 'Beto Coipo' });
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    const found = (await ana.json('GET', '/users?q=coipo')).body.data.find((p: any) => p.id === beto.uid);
    expect(found).toMatchObject({ followsMe: true, followedByMe: false });
    expect((await ana.json('GET', `/users/${beto.uid}`)).body.data).toMatchObject({ followsMe: true, followedByMe: false });
    await ana.json('PUT', `/users/${beto.uid}/follow`);
    expect((await ana.json('GET', `/users/${beto.uid}`)).body.data).toMatchObject({ followsMe: true, followedByMe: true });
    expect((await beto.json('GET', `/users/${ana.uid}`)).body.data).toMatchObject({ followsMe: true, followedByMe: true });
  });

  it('sugerencias desde la propia red, sin inventar', async () => {
    const yo = await person('sg-yo');
    const a = await person('sg-a');
    const b = await person('sg-b');
    const c = await person('sg-c', { fullName: 'Cami Sugerida' });
    expect((await yo.json('GET', '/users/suggestions')).body.data).toEqual([]);
    await yo.json('PUT', `/users/${a.uid}/follow`);
    await yo.json('PUT', `/users/${b.uid}/follow`);
    await a.json('PUT', `/users/${c.uid}/follow`);
    await b.json('PUT', `/users/${c.uid}/follow`);
    await a.json('PUT', `/users/${b.uid}/follow`); // b ya lo sigo: no se sugiere
    const s = (await yo.json('GET', '/users/suggestions')).body.data;
    expect(s.map((p: any) => p.id)).toEqual([c.uid]);
    expect(s[0].mutuals).toBe(2);
    expect((await call('/api/v1/users/suggestions')).status).toBe(401);
  });
});

describe('editar publicaciones', () => {
  it('solo su autor puede editarlas; queda marcada como editada', async () => {
    const ana = await person('ed-ana');
    const beto = await person('ed-beto');
    const post = (await ana.json('POST', '/posts', { body: 'Garza blanca' })).body.data;
    expect(post.editedAt).toBeNull();
    expect((await beto.json('PATCH', `/posts/${post.id}`, { body: 'hackeado' })).status).toBe(404);
    expect((await ana.json('PATCH', `/posts/${post.id}`, {})).status).toBe(400);
    expect((await ana.json('PATCH', `/posts/${post.id}`, { authorId: beto.uid })).status).toBe(400);
    const edited = (await ana.json('PATCH', `/posts/${post.id}`, { body: 'Garza grande', visibility: 'followers' })).body.data;
    expect(edited).toMatchObject({ body: 'Garza grande', visibility: 'followers' });
    expect(edited.editedAt).toBeTruthy();
    const row = await env.DB.prepare('SELECT author_id, body FROM posts WHERE id = ?1').bind(post.id).first();
    expect(row).toEqual({ author_id: ana.uid, body: 'Garza grande' });
  });
});
