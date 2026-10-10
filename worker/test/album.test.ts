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
const anon = async (path: string) => {
  const res = await call(`/api/v1${path}`);
  return { status: res.status, body: (await res.json()) as any };
};
const obs = (speciesId: string, extra: Record<string, unknown> = {}) => ({
  speciesId, observedAt: '2026-10-01T08:00:00Z', latitude: -39.86, longitude: -73.23, ...extra,
});

describe('álbum de especies y logros', () => {
  it('observar desbloquea la especie; lo privado solo lo ve la propia persona', async () => {
    const ana = await person('album-ana');
    await ana.json('POST', '/observations', obs('sp-scelorchilus-rubecula'));
    await ana.json('POST', '/observations', obs('sp-scelorchilus-rubecula'));
    await ana.json('POST', '/observations', obs('sp-lontra-provocax', { visibility: 'private' }));

    const mine = (await ana.json('GET', `/users/${ana.uid}/album`)).body.data;
    const byId = Object.fromEntries(mine.species.map((s: any) => [s.id, s]));
    expect(byId['sp-scelorchilus-rubecula']).toMatchObject({ unlocked: true, via: 'observation', observationCount: 2 });
    expect(byId['sp-lontra-provocax']).toMatchObject({ unlocked: true });
    expect(byId['sp-ardea-alba']).toMatchObject({ unlocked: false, via: null });
    expect(mine.stats).toMatchObject({ unlocked: 2, observations: 3, threatened: 1 });
    const ach = Object.fromEntries(mine.achievements.map((a: any) => [a.id, a]));
    expect(ach['first-observation']).toMatchObject({ unlocked: true });
    expect(ach['threatened-species']).toMatchObject({ unlocked: true });
    expect(ach['species-5']).toMatchObject({ unlocked: false, progress: 2, target: 5 });

    const seen = (await anon(`/users/${ana.uid}/album`)).body.data;
    expect(seen.species.find((s: any) => s.id === 'sp-lontra-provocax').unlocked).toBe(false); // era privada
    expect(seen.stats).toMatchObject({ unlocked: 1, observations: 2 });
  });

  it('desbloqueos heredados de la app antigua y logro de pionera', async () => {
    const beto = await person('album-beto');
    await env.DB.prepare("INSERT INTO species_unlocks (user_id, species_id) VALUES (?1, 'sp-ardea-alba')").bind(beto.uid).run();
    const data = (await beto.json('GET', `/users/${beto.uid}/album`)).body.data;
    expect(data.species.find((s: any) => s.id === 'sp-ardea-alba')).toMatchObject({ unlocked: true, via: 'legacy' });
    expect(data.achievements.find((a: any) => a.id === 'pioneer').unlocked).toBe(true);
  });

  it('perfil privado: el álbum no se muestra a terceros', async () => {
    const cami = await person('album-cami');
    await cami.json('PATCH', '/me/profile', { visibility: 'private' });
    expect((await anon(`/users/${cami.uid}/album`)).status).toBe(404);
    expect((await cami.json('GET', `/users/${cami.uid}/album`)).status).toBe(200);
    expect((await anon('/users/no-existe/album')).status).toBe(404);
  });
});
