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
  const req = (method: string, path: string, body?: unknown, headers: Record<string, string> = {}) =>
    call(`/api/v1${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const json = async (method: string, path: string, body?: unknown, headers?: Record<string, string>) => {
    const res = await req(method, path, body, headers);
    return { status: res.status, body: (res.status === 204 ? null : await res.json()) as any, res };
  };
  await json('GET', '/me');
  return { uid, json, req };
}

describe('mis datos', () => {
  it('exportar incluye todo lo propio, con ubicaciones exactas', async () => {
    const ana = await person('acc-export');
    await ana.json('POST', '/posts', { body: 'Hola humedal' });
    await ana.json('POST', '/observations', { speciesId: 'sp-lontra-provocax', observedAt: '2026-10-01T08:00:00Z', latitude: -39.8612, longitude: -73.2345 });
    const nb = (await ana.json('POST', '/notebooks', { title: 'Bitácora' })).body.data;
    const pages = (await ana.json('GET', `/notebooks/${nb.id}/pages`)).body.data;
    await ana.json('PUT', `/pages/${pages[0].id}`, { version: 1, elements: [{ id: 't', type: 'text', x: 1, y: 1, width: 10, height: 10, data: { text: 'nota' } }] });

    const res = await ana.req('GET', '/me/export');
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Disposition')).toContain('attachment');
    const data = (await res.json()) as any;
    expect(data.account.id).toBe(ana.uid);
    expect(data.posts.map((p: any) => p.body)).toEqual(['Hola humedal']);
    expect(data.observations[0]).toMatchObject({ latitude: -39.8612, species_id: 'sp-lontra-provocax' });
    expect(data.notebooks[0].pages[0].elements[0].data_json).toEqual({ text: 'nota' });
  });

  it('exportar exige sesión', async () => {
    expect((await call('/api/v1/me/export')).status).toBe(401);
  });

  it('eliminar la cuenta borra su contenido y deja constancia solo del UID', async () => {
    const ana = await person('acc-del-ana');
    const beto = await person('acc-del-beto');
    const com = (await ana.json('POST', '/communities', { name: 'Grupo de Ana', slug: 'grupo-de-ana' })).body.data;
    await beto.json('PUT', `/communities/${com.slug}/membership`);
    const betoPost = (await beto.json('POST', '/posts', { body: 'Post de Beto en el grupo', communitySlug: com.slug })).body.data;
    await ana.json('POST', '/observations', { taxonName: 'Coipo', observedAt: '2026-10-01T08:00:00Z', latitude: -39.8, longitude: -73.2 });

    expect((await ana.json('DELETE', '/me')).status).toBe(400); // sin confirmación
    expect((await ana.json('DELETE', '/me', undefined, { 'X-Confirm-Delete': 'ELIMINAR' })).status).toBe(204);

    const count = async (sql: string) => (await env.DB.prepare(sql).bind(ana.uid).first<{ n: number }>())!.n;
    expect(await count('SELECT count(*) AS n FROM users WHERE id = ?1')).toBe(0);
    expect(await count('SELECT count(*) AS n FROM observations WHERE owner_id = ?1')).toBe(0);
    expect(await count('SELECT count(*) AS n FROM deleted_accounts WHERE uid = ?1')).toBe(1);
    // La publicación de Beto sigue (sin comunidad).
    expect((await beto.json('GET', `/posts/${betoPost.id}`)).body.data).toMatchObject({ body: 'Post de Beto en el grupo', community: null });
  });
});

describe('papelera de cuadernos', () => {
  it('un cuaderno borrado aparece en la papelera y se puede restaurar con sus páginas', async () => {
    const ana = await person('trash-ana');
    const beto = await person('trash-beto');
    const nb = (await ana.json('POST', '/notebooks', { title: 'Salida' })).body.data;
    await ana.json('DELETE', `/notebooks/${nb.id}`);
    expect((await ana.json('GET', '/notebooks')).body.data.map((n: any) => n.id)).not.toContain(nb.id);

    const trash = (await ana.json('GET', '/notebooks/trash')).body.data;
    expect(trash.map((n: any) => n.id)).toEqual([nb.id]);
    expect(trash[0].deletedAt).toBeTruthy();
    expect((await beto.json('GET', '/notebooks/trash')).body.data).toEqual([]);
    expect((await beto.json('POST', `/notebooks/${nb.id}/restore`)).status).toBe(404);

    expect((await ana.json('POST', `/notebooks/${nb.id}/restore`)).status).toBe(200);
    expect((await ana.json('GET', `/notebooks/${nb.id}/pages`)).body.data).toHaveLength(1);
    expect((await ana.json('GET', '/notebooks/trash')).body.data).toEqual([]);
  });

  it('pasados 30 días se borra definitivamente', async () => {
    const ana = await person('trash-old');
    const nb = (await ana.json('POST', '/notebooks', { title: 'Viejo' })).body.data;
    await env.DB.prepare("UPDATE notebooks SET deleted_at = '2020-01-01T00:00:00.000Z' WHERE id = ?1").bind(nb.id).run();
    expect((await ana.json('GET', '/notebooks/trash')).body.data).toEqual([]);
    expect((await ana.json('POST', `/notebooks/${nb.id}/restore`)).status).toBe(404);
    const { NotebooksRepository } = await import('../src/repositories/notebooks');
    expect(await new NotebooksRepository(env.DB).purgeTrash(30)).toBeGreaterThanOrEqual(1);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM notebook_pages WHERE notebook_id = ?1').bind(nb.id).first('n')).toBe(0);
  });
});
