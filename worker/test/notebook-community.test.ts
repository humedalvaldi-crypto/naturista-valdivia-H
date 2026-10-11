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

const anon = async (path: string) => {
  const res = await call(`/api/v1${path}`);
  return { status: res.status, body: (await res.json()) as any };
};

describe('comunidad de cuadernos', () => {
  it('Explorar: solo públicos, con autora, categoría, páginas y «me gusta» reales; paginado', async () => {
    const marce = await person('nc-marce', { fullName: 'Marcela Prueba', username: 'marce.prueba' });
    const lector = await person('nc-lector');
    const ids: string[] = [];
    for (let i = 0; i < 5; i++) {
      const res = await marce.json('POST', '/notebooks', { title: `Salida ${i}`, visibility: 'public', category: 'Biodiversidad' });
      expect(res.status).toBe(201);
      ids.push(res.body.data.id);
    }
    const priv = (await marce.json('POST', '/notebooks', { title: 'Secreto', visibility: 'private' })).body.data.id;
    await lector.json('PUT', `/notebooks/${ids[4]}/like`);
    await lector.json('PUT', `/notebooks/${ids[4]}/like`); // idempotente

    const seen: any[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const res = await lector.json('GET', `/notebooks/explore?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(res.status).toBe(200);
      seen.push(...res.body.data.filter((n: any) => n.ownerId === marce.uid));
      cursor = res.body.nextCursor;
      pages++;
    } while (cursor && pages < 50);
    expect(seen.map((n) => n.id).sort()).toEqual([...ids].sort());
    expect(seen.find((n) => n.id === priv)).toBeUndefined();
    const liked = seen.find((n) => n.id === ids[4]);
    expect(liked).toMatchObject({ likeCount: 1, likedByMe: true, category: 'Biodiversidad', pageCount: 1 });
    expect(liked.owner).toMatchObject({ id: marce.uid, name: 'Marcela Prueba', username: 'marce.prueba' });
    expect((await anon(`/notebooks/${ids[4]}`)).body.data).toMatchObject({ likeCount: 1, owner: { id: marce.uid, name: 'Marcela Prueba' } });
    // Sin sesión también se puede explorar; la búsqueda filtra por título.
    const found = await anon('/notebooks/explore?q=salida%203');
    expect(found.body.data.map((n: any) => n.id)).toEqual([ids[3]]);
    expect(found.body.data[0].likedByMe).toBe(false);
  });

  it('Explorar oculta bloqueos y, con «following=1», muestra solo a quienes sigo', async () => {
    const a = await person('nc-a');
    const b = await person('nc-b');
    const yo = await person('nc-yo');
    const na = (await a.json('POST', '/notebooks', { title: 'Cuaderno de A', visibility: 'public' })).body.data.id;
    const nb = (await b.json('POST', '/notebooks', { title: 'Cuaderno de B', visibility: 'public' })).body.data.id;
    await yo.json('PUT', `/users/${a.uid}/follow`);
    const following = (await yo.json('GET', '/notebooks/explore?following=1&limit=100')).body.data.map((n: any) => n.id);
    expect(following).toContain(na);
    expect(following).not.toContain(nb);
    await b.json('PUT', `/users/${yo.uid}/block`);
    const all = (await yo.json('GET', '/notebooks/explore?limit=100')).body.data.map((n: any) => n.id);
    expect(all).toContain(na);
    expect(all).not.toContain(nb);
    expect((await anon('/notebooks/explore?following=1')).status).toBe(401);
  });

  it('retirar la publicación lo saca de Explorar sin borrarlo; la categoría se puede editar', async () => {
    const d = await person('nc-dueña');
    const id = (await d.json('POST', '/notebooks', { title: 'Humedal Angachilla', visibility: 'public' })).body.data.id;
    expect((await anon('/notebooks/explore?q=angachilla')).body.data.map((n: any) => n.id)).toEqual([id]);
    const patched = await d.json('PATCH', `/notebooks/${id}`, { visibility: 'private', category: 'Aves' });
    expect(patched.body.data).toMatchObject({ visibility: 'private', category: 'Aves' });
    expect((await anon('/notebooks/explore?q=angachilla')).body.data).toEqual([]);
    expect((await anon(`/notebooks/${id}`)).status).toBe(404);
    expect((await d.json('GET', `/notebooks/${id}`)).status).toBe(200); // sigue existiendo para su dueña
  });

  it('perfil: cuadernos públicos con sus «me gusta»', async () => {
    const d = await person('nc-perfil');
    const id = (await d.json('POST', '/notebooks', { title: 'Visible', visibility: 'public' })).body.data.id;
    await d.json('POST', '/notebooks', { title: 'Oculto', visibility: 'private' });
    const other = await person('nc-visita');
    await other.json('PUT', `/notebooks/${id}/like`);
    const list = (await other.json('GET', `/notebooks?owner=${d.uid}`)).body.data;
    expect(list.map((n: any) => n.title)).toEqual(['Visible']);
    expect(list[0]).toMatchObject({ likeCount: 1, likedByMe: true });
  });
});

describe('personas: directorio, seguidores y seguidos', () => {
  it('directorio sin texto, con número real de seguidores', async () => {
    const z = await person('dir-z', { fullName: 'Zulema Directorio' });
    const f = await person('dir-f');
    await f.json('PUT', `/users/${z.uid}/follow`);
    let cursor: string | null = null;
    let row: any;
    for (let i = 0; i < 50 && !row; i++) {
      const res = await f.json('GET', `/users?limit=50${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(res.status).toBe(200);
      row = res.body.data.find((p: any) => p.id === z.uid);
      cursor = res.body.nextCursor;
      if (!cursor) break;
    }
    expect(row).toMatchObject({ name: 'Zulema Directorio', followers: 1, followedByMe: true, followsMe: false });
  });

  it('listas de seguidores y seguidos visibles; perfil privado responde 403', async () => {
    const p = await person('cx-p', { fullName: 'Pública' });
    const s1 = await person('cx-s1', { fullName: 'Sigue Uno' });
    const yo = await person('cx-yo');
    await s1.json('PUT', `/users/${p.uid}/follow`);
    await yo.json('PUT', `/users/${s1.uid}/follow`);
    const followers = (await yo.json('GET', `/users/${p.uid}/followers`)).body.data;
    expect(followers).toEqual([expect.objectContaining({ id: s1.uid, name: 'Sigue Uno', followedByMe: true, followsMe: false })]);
    expect((await yo.json('GET', `/users/${s1.uid}/following`)).body.data.map((x: any) => x.id)).toEqual([p.uid]);

    const priv = await person('cx-priv', { visibility: 'private' });
    expect((await yo.json('GET', `/users/${priv.uid}/followers`)).status).toBe(403);
    expect((await priv.json('GET', `/users/${priv.uid}/followers`)).status).toBe(200);
  });
});

// Evita advertencia de importación sin uso cuando se ejecuta con el pool de Cloudflare.
void env;
