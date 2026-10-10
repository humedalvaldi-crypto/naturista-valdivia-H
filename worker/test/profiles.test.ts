import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

const json = (token: string, method: string, body: unknown) => ({
  method,
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

type ProfileDto = { username: string | null; fullName: string | null; bio: string | null; photo: string | null; visibility: string };

describe('perfil propio', () => {
  it('empieza vacío y se puede editar', async () => {
    const t = await signer.sign({ sub: 'uid-prof1' });
    const empty = await call('/api/v1/me/profile', { headers: { Authorization: `Bearer ${t}` } });
    expect((await empty.json<{ data: unknown }>()).data).toBeNull();

    const res = await call('/api/v1/me/profile', json(t, 'PATCH', { username: 'Martin.Pescador', fullName: '  Martín  ', bio: 'Aves de Valdivia' }));
    expect(res.status).toBe(200);
    const { data } = await res.json<{ data: ProfileDto }>();
    expect(data).toMatchObject({ username: 'martin.pescador', fullName: 'Martín', bio: 'Aves de Valdivia', visibility: 'public' });
  });

  it('valida los campos y rechaza campos desconocidos', async () => {
    const t = await signer.sign({ sub: 'uid-prof2' });
    for (const body of [{}, { username: 'ab' }, { username: 'con espacio' }, { bio: 'x'.repeat(501) }, { visibility: 'todos' }, { isAdmin: true }]) {
      const res = await call('/api/v1/me/profile', json(t, 'PATCH', body));
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
  });

  it('el nombre de usuario es único (sin distinguir mayúsculas)', async () => {
    const a = await signer.sign({ sub: 'uid-prof3' });
    const b = await signer.sign({ sub: 'uid-prof4' });
    expect((await call('/api/v1/me/profile', json(a, 'PATCH', { username: 'huillin' }))).status).toBe(200);
    const res = await call('/api/v1/me/profile', json(b, 'PATCH', { username: 'Huillin' }));
    expect(res.status).toBe(409);
  });

  it('solo acepta como foto un archivo propio de tipo foto de perfil', async () => {
    const owner = await signer.sign({ sub: 'uid-prof5' });
    const other = await signer.sign({ sub: 'uid-prof6' });
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
    const up = await call('/api/v1/media?purpose=profile-photo', {
      method: 'POST',
      headers: { Authorization: `Bearer ${owner}`, 'Content-Type': 'image/png' },
      body: png,
    });
    const { data: asset } = await up.json<{ data: { id: string } }>();

    expect((await call('/api/v1/me/profile', json(other, 'PATCH', { photoAssetId: asset.id }))).status).toBe(400);
    const ok = await call('/api/v1/me/profile', json(owner, 'PATCH', { photoAssetId: asset.id }));
    expect((await ok.json<{ data: ProfileDto }>()).data.photo).toBe(`/api/v1/media/${asset.id}`);
  });
});

describe('perfil público', () => {
  it('muestra perfiles públicos y oculta los privados a terceros', async () => {
    const a = await signer.sign({ sub: 'uid-pp1' });
    await call('/api/v1/me/profile', json(a, 'PATCH', { username: 'chucao', fullName: 'Chucao' }));
    expect((await call('/api/v1/profiles/chucao')).status).toBe(200);

    await call('/api/v1/me/profile', json(a, 'PATCH', { visibility: 'private' }));
    expect((await call('/api/v1/profiles/chucao')).status).toBe(404);
    const other = await signer.sign({ sub: 'uid-pp2' });
    expect((await call('/api/v1/profiles/chucao', { headers: { Authorization: `Bearer ${other}` } })).status).toBe(404);
    expect((await call('/api/v1/profiles/chucao', { headers: { Authorization: `Bearer ${a}` } })).status).toBe(200);
  });

  it('un token inválido en una ruta pública no se ignora', async () => {
    expect((await call('/api/v1/profiles/chucao', { headers: { Authorization: 'Bearer x.y.z' } })).status).toBe(401);
  });
});
