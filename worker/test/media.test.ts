import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { purgeMedia } from '../src/services/maintenance';
import { makeApp, makeSigner } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

/** JPEG mínimo válido por firma (los primeros bytes son lo que se comprueba). */
const jpeg = () => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0xff, 0xd9]);
const png = () => new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
const html = () => new TextEncoder().encode('<html><script>alert(1)</script></html>');

async function upload(token: string, body: Uint8Array, contentType: string, purpose = 'observation-photo') {
  return call(`/api/v1/media?purpose=${purpose}`, {
    method: 'POST',
    headers: { ...bearer(token), 'Content-Type': contentType },
    body,
  });
}

type MediaDto = { id: string; url: string; visibility: string; contentType: string; size: number };

describe('subida de archivos', () => {
  it('exige sesión', async () => {
    const res = await call('/api/v1/media?purpose=observation-photo', { method: 'POST', body: jpeg() });
    expect(res.status).toBe(401);
  });

  it('guarda una imagen válida con clave generada por el servidor', async () => {
    const token = await signer.sign({ sub: 'uid-up1' });
    const res = await upload(token, jpeg(), 'image/jpeg');
    expect(res.status).toBe(201);
    const { data } = await res.json<{ data: MediaDto }>();
    expect(data).toMatchObject({ contentType: 'image/jpeg', size: jpeg().byteLength, visibility: 'private' });

    const row = await env.DB.prepare('SELECT object_key, owner_id FROM media_assets WHERE id = ?1').bind(data.id).first<{ object_key: string; owner_id: string }>();
    expect(row?.owner_id).toBe('uid-up1');
    expect(row?.object_key).toBe(`u/uid-up1/observation-photo/${data.id}.jpg`);
    expect(await env.MEDIA!.head(row!.object_key)).not.toBeNull();
  });

  it('rechaza un propósito desconocido', async () => {
    const token = await signer.sign({ sub: 'uid-up2' });
    expect((await upload(token, jpeg(), 'image/jpeg', 'otra-cosa')).status).toBe(400);
  });

  it('rechaza archivos que no son del tipo admitido aunque digan serlo', async () => {
    const token = await signer.sign({ sub: 'uid-up3' });
    const res = await upload(token, html(), 'image/jpeg');
    expect(res.status).toBe(415);
  });

  it('rechaza si el tipo declarado no coincide con el contenido', async () => {
    const token = await signer.sign({ sub: 'uid-up4' });
    const res = await upload(token, png(), 'image/jpeg');
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe('content_type_mismatch');
  });

  it('rechaza audio donde se espera imagen', async () => {
    const token = await signer.sign({ sub: 'uid-up5' });
    const ogg = new TextEncoder().encode('OggS\0\x02\0\0\0\0\0\0\0\0');
    expect((await upload(token, ogg, 'audio/ogg', 'profile-photo')).status).toBe(415);
    expect((await upload(token, ogg, 'audio/ogg', 'notebook-audio')).status).toBe(201);
  });

  it('rechaza archivos más grandes que el límite del propósito', async () => {
    const token = await signer.sign({ sub: 'uid-up6' });
    const big = new Uint8Array(5 * 1024 * 1024 + 10);
    big.set(jpeg());
    const res = await upload(token, big, 'image/jpeg', 'profile-photo'); // máx. 5 MB
    expect(res.status).toBe(413);
  });

  it('rechaza un archivo vacío', async () => {
    const token = await signer.sign({ sub: 'uid-up7' });
    expect((await upload(token, new Uint8Array(0), 'image/jpeg')).status).toBe(400);
  });
});

describe('acceso a archivos', () => {
  it('el dueño puede descargar su archivo privado; otra persona y anónimos no', async () => {
    const owner = await signer.sign({ sub: 'uid-dl-owner' });
    const other = await signer.sign({ sub: 'uid-dl-other' });
    const { data } = await (await upload(owner, jpeg(), 'image/jpeg')).json<{ data: MediaDto }>();

    const mine = await call(data.url, { headers: bearer(owner) });
    expect(mine.status).toBe(200);
    expect(mine.headers.get('Content-Type')).toBe('image/jpeg');
    expect(mine.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(new Uint8Array(await mine.arrayBuffer())).toEqual(jpeg());

    expect((await call(data.url, { headers: bearer(other) })).status).toBe(404);
    expect((await call(data.url)).status).toBe(404);
  });

  it('las fotos de perfil son públicas', async () => {
    const owner = await signer.sign({ sub: 'uid-pub' });
    const { data } = await (await upload(owner, png(), 'image/png', 'profile-photo')).json<{ data: MediaDto }>();
    expect(data.visibility).toBe('public');
    expect((await call(data.url)).status).toBe(200);
  });

  it('una URL firmada da acceso temporal y no se puede alterar', async () => {
    const owner = await signer.sign({ sub: 'uid-sig' });
    const { data } = await (await upload(owner, jpeg(), 'image/jpeg')).json<{ data: MediaDto }>();

    const link = await call(`/api/v1/media/${data.id}/link`, { method: 'POST', headers: bearer(owner) });
    expect(link.status).toBe(200);
    const { data: signed } = await link.json<{ data: { url: string } }>();

    expect((await call(signed.url)).status).toBe(200);
    expect((await call(signed.url.replace(/sig=.{4}/, 'sig=AAAA'))).status).toBe(404);
    expect((await call(signed.url.replace(/exp=\d+/, 'exp=9999999999'))).status).toBe(404);
  });

  it('nadie más puede pedir un enlace firmado de un archivo ajeno', async () => {
    const owner = await signer.sign({ sub: 'uid-sig2' });
    const other = await signer.sign({ sub: 'uid-sig3' });
    const { data } = await (await upload(owner, jpeg(), 'image/jpeg')).json<{ data: MediaDto }>();
    expect((await call(`/api/v1/media/${data.id}/link`, { method: 'POST', headers: bearer(other) })).status).toBe(404);
  });

  it('lista solo los archivos propios, paginados', async () => {
    const a = await signer.sign({ sub: 'uid-list-a' });
    const b = await signer.sign({ sub: 'uid-list-b' });
    for (let i = 0; i < 3; i++) await upload(a, jpeg(), 'image/jpeg');
    await upload(b, jpeg(), 'image/jpeg');

    const first = await (await call('/api/v1/media/mine?limit=2', { headers: bearer(a) })).json<{ data: MediaDto[]; nextCursor: string | null }>();
    expect(first.data).toHaveLength(2);
    expect(first.nextCursor).toBeTruthy();
    const second = await (
      await call(`/api/v1/media/mine?limit=2&cursor=${first.nextCursor}`, { headers: bearer(a) })
    ).json<{ data: MediaDto[]; nextCursor: string | null }>();
    expect(second.data).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
    const ids = [...first.data, ...second.data].map((m) => m.id);
    expect(new Set(ids).size).toBe(3);
  });

  it('rechaza cursores y límites inválidos', async () => {
    const a = await signer.sign({ sub: 'uid-list-c' });
    expect((await call('/api/v1/media/mine?cursor=basura', { headers: bearer(a) })).status).toBe(400);
    expect((await call('/api/v1/media/mine?limit=-1', { headers: bearer(a) })).status).toBe(400);
  });
});

describe('borrado de archivos', () => {
  it('solo el dueño borra; el objeto desaparece de R2', async () => {
    const owner = await signer.sign({ sub: 'uid-del' });
    const other = await signer.sign({ sub: 'uid-del-other' });
    const { data } = await (await upload(owner, jpeg(), 'image/jpeg')).json<{ data: MediaDto }>();
    const key = `u/uid-del/observation-photo/${data.id}.jpg`;

    expect((await call(`/api/v1/media/${data.id}`, { method: 'DELETE', headers: bearer(other) })).status).toBe(404);
    expect(await env.MEDIA!.head(key)).not.toBeNull();

    expect((await call(`/api/v1/media/${data.id}`, { method: 'DELETE', headers: bearer(owner) })).status).toBe(204);
    expect(await env.MEDIA!.head(key)).toBeNull();
    expect((await call(data.url, { headers: bearer(owner) })).status).toBe(404);
  });

  it('el barrido elimina huérfanos antiguos y respeta los registrados', async () => {
    await env.MEDIA!.put('u/uid-x/observation-photo/huerfano.jpg', jpeg());
    const owner = await signer.sign({ sub: 'uid-keep' });
    const { data } = await (await upload(owner, jpeg(), 'image/jpeg')).json<{ data: MediaDto }>();

    const report = await purgeMedia(env, Date.now() + 2 * 24 * 60 * 60 * 1000);
    expect(report.orphansRemoved).toBeGreaterThanOrEqual(1);
    expect(await env.MEDIA!.head('u/uid-x/observation-photo/huerfano.jpg')).toBeNull();
    expect(await env.MEDIA!.head(`u/uid-keep/observation-photo/${data.id}.jpg`)).not.toBeNull();
  });
});

describe('límites de frecuencia', () => {
  it('responde 429 cuando el límite se agota', async () => {
    const { createApp } = await import('../src/app');
    const app = createApp({ keyResolver: () => signer.jwks });
    const denyAll = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const token = await signer.sign({ sub: 'uid-rl' });
    const res = await app.request(
      '/api/v1/media?purpose=observation-photo',
      { method: 'POST', headers: { ...bearer(token), 'Content-Type': 'image/jpeg' }, body: jpeg() },
      { ...env, RL_UPLOAD: denyAll },
    );
    expect(res.status).toBe(429);
    expect(res.headers.get('Retry-After')).toBe('60');
  });
});
