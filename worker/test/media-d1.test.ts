import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { purgeMedia } from '../src/services/maintenance';
import { D1_CHUNK_BYTES } from '../src/services/media-store';
import { makeApp, makeSigner } from './helpers';

/** Sin R2 (plan gratuito sin tarjeta): los archivos van a D1. */
let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
const noR2 = { ...env, MEDIA: undefined };
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks, { MEDIA: undefined });
});

/** JPEG "grande" (firma válida + relleno) para forzar varios trozos. */
function bigJpeg(size: number) {
  const b = new Uint8Array(size);
  // SOI + APP0 (JFIF) completo + inicio de datos de imagen (SOS); luego relleno.
  b.set([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xda, 0, 2]);
  for (let i = 24; i < size - 2; i++) b[i] = i % 251;
  b.set([0xff, 0xd9], size - 2);
  return b;
}

const sha = async (b: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map((x) => x.toString(16).padStart(2, '0')).join('');

async function upload(token: string, body: Uint8Array) {
  const res = await call('/api/v1/media?purpose=observation-photo', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'image/jpeg' },
    body,
  });
  return { status: res.status, body: (await res.json()) as { data: { id: string } } };
}

describe('archivos sin R2 (guardados en D1)', () => {
  it('sube, descarga idéntico (en varios trozos) y respeta los permisos', async () => {
    const ana = await signer.sign({ sub: 'd1-ana' });
    const beto = await signer.sign({ sub: 'd1-beto' });
    const original = bigJpeg(D1_CHUNK_BYTES * 2 + 1234);
    const up = await upload(ana, original);
    expect(up.status).toBe(201);
    const id = up.body.data.id;

    const parts = await env.DB.prepare(
      'SELECT count(*) AS n FROM media_chunks WHERE object_key = (SELECT object_key FROM media_assets WHERE id = ?1)',
    ).bind(id).first<{ n: number }>();
    expect(parts!.n).toBe(3);

    const mine = await call(`/api/v1/media/${id}`, { headers: { Authorization: `Bearer ${ana}` } });
    expect(mine.status).toBe(200);
    const got = new Uint8Array(await mine.arrayBuffer());
    expect(got.byteLength).toBe(original.byteLength);
    expect(await sha(got)).toBe(await sha(original)); // comparar 2 MB byte a byte con toEqual es muy lento
    // Privado: otra persona no lo ve.
    expect((await call(`/api/v1/media/${id}`, { headers: { Authorization: `Bearer ${beto}` } })).status).toBe(404);
  }, 30_000);

  it('borrar elimina los trozos', async () => {
    const ana = await signer.sign({ sub: 'd1-del' });
    const id = (await upload(ana, bigJpeg(5000))).body.data.id;
    const key = (await env.DB.prepare('SELECT object_key FROM media_assets WHERE id = ?1').bind(id).first<{ object_key: string }>())!.object_key;
    expect((await call(`/api/v1/media/${id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${ana}` } })).status).toBe(204);
    expect((await env.DB.prepare('SELECT count(*) AS n FROM media_chunks WHERE object_key = ?1').bind(key).first<{ n: number }>())!.n).toBe(0);
  });

  it('el barrido elimina trozos huérfanos antiguos', async () => {
    await env.DB.prepare("INSERT INTO media_chunks (object_key, part, bytes, created_at) VALUES ('u/x/observation-photo/huerfano.jpg', 0, X'00', '2020-01-01T00:00:00.000Z')").run();
    const report = await purgeMedia(noR2 as typeof env);
    expect(report.orphansRemoved).toBeGreaterThanOrEqual(1);
    expect((await env.DB.prepare("SELECT count(*) AS n FROM media_chunks WHERE object_key LIKE '%huerfano%'").first<{ n: number }>())!.n).toBe(0);
  });

  it('con R2 activado después, lo guardado en D1 se sigue sirviendo', async () => {
    const ana = await signer.sign({ sub: 'd1-then-r2' });
    const original = bigJpeg(3000);
    const id = (await upload(ana, original)).body.data.id;
    const withR2 = makeApp(signer.jwks); // env normal, con R2
    const res = await withR2(`/api/v1/media/${id}`, { headers: { Authorization: `Bearer ${ana}` } });
    expect(res.status).toBe(200);
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(original);
  });
});
