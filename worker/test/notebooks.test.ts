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
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    return { status: res.status, body: (res.status === 204 ? null : await res.json()) as any };
  };
  await json('GET', '/me');
  return { uid, token, json };
}
const anon = async (path: string) => {
  const res = await call(`/api/v1${path}`);
  return { status: res.status, body: (await res.json()) as any };
};

const text = (id: string, body: string, extra: Record<string, unknown> = {}) => ({
  id,
  type: 'text',
  x: 100,
  y: 120,
  width: 400,
  height: 80,
  rotation: 0,
  z: 1,
  data: { text: body, size: 28 },
  ...extra,
});

async function notebookWithPage(owner: Awaited<ReturnType<typeof person>>, extra: Record<string, unknown> = {}) {
  const nb = (await owner.json('POST', '/notebooks', { title: 'Salida a Angachilla', ...extra })).body.data;
  const pages = (await owner.json('GET', `/notebooks/${nb.id}/pages`)).body.data;
  return { nb, page: pages[0] };
}

describe('cuadernos', () => {
  it('crear un cuaderno incluye su primera página y es privado por defecto', async () => {
    const ana = await person('nb-ana');
    const { nb, page } = await notebookWithPage(ana);
    expect(nb).toMatchObject({ title: 'Salida a Angachilla', visibility: 'private', pageCount: 1 });
    expect(page).toMatchObject({ position: 0, version: 1 });
    expect((await ana.json('GET', '/notebooks')).body.data.map((n: any) => n.id)).toContain(nb.id);
  });

  it('un cuaderno privado no lo ve nadie más; uno público sí, pero solo lectura', async () => {
    const ana = await person('nb-priv-ana');
    const beto = await person('nb-priv-beto');
    const { nb, page } = await notebookWithPage(ana);

    expect((await beto.json('GET', `/notebooks/${nb.id}`)).status).toBe(404);
    expect((await anon(`/pages/${page.id}`)).status).toBe(404);
    expect((await beto.json('GET', `/notebooks?owner=${ana.uid}`)).body.data).toHaveLength(0);

    await ana.json('PATCH', `/notebooks/${nb.id}`, { visibility: 'public' });
    expect((await anon(`/notebooks/${nb.id}`)).status).toBe(200);
    const read = await beto.json('GET', `/pages/${page.id}`);
    expect(read.status).toBe(200);
    expect(read.body.data.editable).toBe(false);

    expect((await beto.json('PUT', `/pages/${page.id}`, { version: 1, elements: [] })).status).toBe(404);
    expect((await beto.json('PATCH', `/notebooks/${nb.id}`, { title: 'mío' })).status).toBe(404);
    expect((await beto.json('DELETE', `/notebooks/${nb.id}`)).status).toBe(404);
    expect((await beto.json('POST', `/notebooks/${nb.id}/pages`)).status).toBe(404);
  });

  it('valida título y color', async () => {
    const ana = await person('nb-val');
    expect((await ana.json('POST', '/notebooks', { title: '' })).status).toBe(400);
    expect((await ana.json('POST', '/notebooks', { title: 'x', color: 'verde' })).status).toBe(400);
    expect((await ana.json('POST', '/notebooks', { title: 'x', color: '#ABCDEF' })).status).toBe(201);
  });

  it('borrar oculta el cuaderno y sus páginas', async () => {
    const ana = await person('nb-del');
    const { nb, page } = await notebookWithPage(ana);
    expect((await ana.json('DELETE', `/notebooks/${nb.id}`)).status).toBe(204);
    expect((await ana.json('GET', `/notebooks/${nb.id}`)).status).toBe(404);
    expect((await ana.json('GET', `/pages/${page.id}`)).status).toBe(404);
  });
});

describe('páginas', () => {
  it('guardar y releer elementos con su posición, rotación y datos', async () => {
    const ana = await person('pg-save');
    const { page } = await notebookWithPage(ana);
    const drawing = {
      id: 'dibujo-1',
      type: 'drawing',
      x: 0,
      y: 0,
      width: 1000,
      height: 1414,
      z: 0,
      data: { strokes: [{ tool: 'pen', color: '#22261F', width: 4, opacity: 1, points: [10, 10, 20, 25, 30, 40] }] },
    };
    const saved = await ana.json('PUT', `/pages/${page.id}`, {
      version: 1,
      title: 'Chucao en el sendero',
      locationName: 'Humedal Angachilla',
      latitude: -39.86,
      longitude: -73.23,
      locationSource: 'gps',
      elements: [text('t1', 'Canto a las 8:10', { rotation: -3.5 }), drawing],
    });
    expect(saved.status).toBe(200);
    expect(saved.body.data.version).toBe(2);

    const read = (await ana.json('GET', `/pages/${page.id}`)).body.data;
    expect(read).toMatchObject({ title: 'Chucao en el sendero', latitude: -39.86, locationSource: 'gps', version: 2, editable: true });
    expect(read.canvas).toEqual({ width: 1000, height: 1414 });
    const byId = Object.fromEntries(read.elements.map((e: any) => [e.id, e]));
    expect(byId.t1).toMatchObject({ type: 'text', rotation: -3.5, data: { text: 'Canto a las 8:10', size: 28 } });
    expect(byId['dibujo-1'].data.strokes[0].points).toEqual([10, 10, 20, 25, 30, 40]);
  });

  it('una versión desactualizada recibe 409 y no cambia nada', async () => {
    const ana = await person('pg-conflict');
    const { page } = await notebookWithPage(ana);
    expect((await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [text('a', 'desde el teléfono')] })).status).toBe(200);
    const stale = await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [text('b', 'desde el computador')] });
    expect(stale.status).toBe(409);
    expect(stale.body.error).toMatchObject({ code: 'version_conflict', details: { currentVersion: 2 } });

    const read = (await ana.json('GET', `/pages/${page.id}`)).body.data;
    expect(read.elements.map((e: any) => e.data.text)).toEqual(['desde el teléfono']);
  });

  it('guardar reemplaza los elementos (borrar uno lo quita)', async () => {
    const ana = await person('pg-replace');
    const { page } = await notebookWithPage(ana);
    await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [text('a', 'uno'), text('b', 'dos')] });
    await ana.json('PUT', `/pages/${page.id}`, { version: 2, elements: [text('b', 'dos')] });
    expect((await ana.json('GET', `/pages/${page.id}`)).body.data.elements.map((e: any) => e.id)).toEqual(['b']);
  });

  it('valida los elementos', async () => {
    const ana = await person('pg-validate');
    const { page } = await notebookWithPage(ana);
    const bad = [
      { version: 1, elements: [{ ...text('a', 'x'), type: 'script' }] },
      { version: 1, elements: [{ ...text('a', 'x'), width: -5 }] },
      { version: 1, elements: [text('a', 'x'), text('a', 'y')] },
      { version: 1, elements: [{ ...text('a', 'x'), id: '../../etc' }] },
      { version: 1, latitude: -39.8, elements: [] },
      { version: 1, elements: [text('a', 'x', { data: { text: 'x'.repeat(400_001) } })] },
    ];
    for (const body of bad) {
      expect((await ana.json('PUT', `/pages/${page.id}`, body)).status, JSON.stringify(body).slice(0, 80)).not.toBe(200);
    }
  });

  it('las fotos de una página deben ser archivos propios', async () => {
    const ana = await person('pg-media-ana');
    const beto = await person('pg-media-beto');
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0xff, 0xd9]);
    const up = await call('/api/v1/media?purpose=notebook-photo', {
      method: 'POST',
      headers: { Authorization: `Bearer ${beto.token}`, 'Content-Type': 'image/jpeg' },
      body: jpeg,
    });
    const betosPhoto = ((await up.json()) as any).data.id;
    const { page } = await notebookWithPage(ana);
    const photo = { id: 'f1', type: 'photo', x: 0, y: 0, width: 300, height: 200, mediaAssetId: betosPhoto };
    expect((await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [photo] })).status).toBe(400);
  });

  it('agregar, reordenar, duplicar y borrar páginas', async () => {
    const ana = await person('pg-order');
    const { nb, page: p1 } = await notebookWithPage(ana);
    const p2 = (await ana.json('POST', `/notebooks/${nb.id}/pages`)).body.data;
    const p3 = (await ana.json('POST', `/notebooks/${nb.id}/pages`)).body.data;

    const reordered = await ana.json('PUT', `/notebooks/${nb.id}/page-order`, { pageIds: [p3.id, p1.id, p2.id] });
    expect(reordered.body.data.map((p: any) => p.id)).toEqual([p3.id, p1.id, p2.id]);
    expect((await ana.json('PUT', `/notebooks/${nb.id}/page-order`, { pageIds: [p1.id] })).status).toBe(400);

    await ana.json('PUT', `/pages/${p1.id}`, { version: 1, elements: [text('a', 'original')] });
    const copy = (await ana.json('POST', `/pages/${p1.id}/duplicate`)).body.data;
    const order = (await ana.json('GET', `/notebooks/${nb.id}/pages`)).body.data.map((p: any) => p.id);
    expect(order).toEqual([p3.id, p1.id, copy.id, p2.id]);
    expect((await ana.json('GET', `/pages/${copy.id}`)).body.data.elements[0].data.text).toBe('original');

    expect((await ana.json('DELETE', `/pages/${p2.id}`)).status).toBe(204);
    expect((await ana.json('GET', `/notebooks/${nb.id}`)).body.data.pageCount).toBe(3);
  });

  it('duplicar un cuaderno copia páginas y elementos como privado', async () => {
    const ana = await person('nb-dup');
    const { nb, page } = await notebookWithPage(ana, { visibility: 'public' });
    await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [text('a', 'nota de campo')] });
    const copy = (await ana.json('POST', `/notebooks/${nb.id}/duplicate`)).body.data;
    expect(copy).toMatchObject({ title: 'Salida a Angachilla (copia)', visibility: 'private', pageCount: 1 });
    const copyPage = (await ana.json('GET', `/notebooks/${copy.id}/pages`)).body.data[0];
    expect((await ana.json('GET', `/pages/${copyPage.id}`)).body.data.elements[0].data.text).toBe('nota de campo');
  });

  it('acepta páginas grandes (dibujos) hasta 2 MB', async () => {
    const ana = await person('pg-big');
    const { page } = await notebookWithPage(ana);
    const points = Array.from({ length: 30_000 }, (_, i) => i % 1000);
    const drawing = { id: 'd', type: 'drawing', x: 0, y: 0, width: 1000, height: 1414, data: { strokes: [{ points }] } };
    const res = await ana.json('PUT', `/pages/${page.id}`, { version: 1, elements: [drawing] });
    expect(res.status).toBe(200);
    const rows = await env.DB.prepare('SELECT length(data_json) AS n FROM notebook_elements WHERE page_id = ?1').bind(page.id).first<{ n: number }>();
    expect(rows!.n).toBeGreaterThan(100_000);
  });
});
