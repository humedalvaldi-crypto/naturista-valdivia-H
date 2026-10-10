import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { clearExifGps, stripLocationMetadata } from '../src/services/image-metadata';
import { cellCenter } from '../src/services/geoprivacy';
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
  return { uid, token, json };
}
const anon = async (path: string) => {
  const res = await call(`/api/v1${path}`);
  return { status: res.status, body: (await res.json()) as any };
};

// Humedal Angachilla (aprox.).
const LAT = -39.8612;
const LNG = -73.2345;
const obs = (extra: Record<string, unknown> = {}) => ({
  observedAt: '2026-10-01T08:10:00-03:00',
  latitude: LAT,
  longitude: LNG,
  accuracyM: 12,
  locationSource: 'gps',
  locationName: 'Sendero del humedal, junto al puente',
  ...extra,
});

describe('catálogo', () => {
  it('busca especies por nombre común o científico y por grupo', async () => {
    const byCommon = await anon('/species?q=huill');
    expect(byCommon.body.data.map((s: any) => s.scientificName)).toEqual(['Lontra provocax']);
    expect(byCommon.body.data[0]).toMatchObject({ conservationStatus: 'EN', sensitive: true });
    const aves = (await anon('/species?group=aves')).body.data;
    expect(aves.length).toBeGreaterThan(5);
    expect(aves.every((s: any) => s.group === 'aves')).toBe(true);
    expect((await anon('/species?q=%25')).body.data).toHaveLength(0); // comodín literal
    expect((await anon('/species?group=dragones')).status).toBe(400);
  });
});

describe('observaciones', () => {
  it('registrar y ver: la dueña ve la ubicación exacta', async () => {
    const ana = await person('obs-ana');
    const res = await ana.json('POST', '/observations', obs({ speciesId: 'sp-scelorchilus-rubecula', count: 2, notes: 'Canto desde el sotobosque' }));
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ latitude: LAT, longitude: LNG, obscured: false, isMine: true, count: 2 });
    expect(res.body.data.species.commonNameEs).toBe('Chucao');

    const other = await anon(`/observations/${res.body.data.id}`);
    expect(other.body.data).toMatchObject({ latitude: LAT, longitude: LNG, locationName: 'Sendero del humedal, junto al puente', isMine: false });
  });

  it('especie sensible: terceros solo ven una celda de 0,1°, sin lugar ni precisión', async () => {
    const ana = await person('obs-sens');
    const created = (await ana.json('POST', '/observations', obs({ speciesId: 'sp-lontra-provocax', geoprivacy: 'open' }))).body.data;
    expect(created).toMatchObject({ latitude: LAT, obscured: true, locationName: 'Sendero del humedal, junto al puente' });

    const seen = (await anon(`/observations/${created.id}`)).body.data;
    expect(seen).toMatchObject({ latitude: cellCenter(LAT), longitude: cellCenter(LNG), obscured: true, locationName: null, accuracyM: null });
    expect(seen.geoprivacy).toBeUndefined();

    // Un recuadro diminuto alrededor del punto real no la encuentra (no se puede triangular).
    const tiny = `${LNG - 0.001},${LAT - 0.001},${LNG + 0.001},${LAT + 0.001}`;
    const found = (await anon(`/observations?bbox=${tiny}&limit=500`)).body.data.map((o: any) => o.id);
    expect(found).not.toContain(created.id);
    // La dueña sí.
    expect((await ana.json('GET', `/observations?bbox=${tiny}`)).body.data.map((o: any) => o.id)).toContain(created.id);
    // En la base no se guarda la exacta como pública.
    const row = await env.DB.prepare('SELECT public_latitude FROM observations WHERE id = ?1').bind(created.id).first<{ public_latitude: number }>();
    expect(row!.public_latitude).not.toBe(LAT);
  });

  it('quien observa puede ocultar la ubicación de cualquier especie', async () => {
    const ana = await person('obs-geopriv');
    const created = (await ana.json('POST', '/observations', obs({ taxonName: 'Martín pescador', geoprivacy: 'obscured' }))).body.data;
    expect((await anon(`/observations/${created.id}`)).body.data).toMatchObject({ obscured: true, latitude: cellCenter(LAT) });
    // Volver a abrirla.
    const opened = (await ana.json('PATCH', `/observations/${created.id}`, { geoprivacy: 'open' })).body.data;
    expect(opened.obscured).toBe(false);
    expect((await anon(`/observations/${created.id}`)).body.data.latitude).toBe(LAT);
  });

  it('privadas, perfiles privados y bloqueos', async () => {
    const ana = await person('obs-priv-ana');
    const beto = await person('obs-priv-beto');
    const priv = (await ana.json('POST', '/observations', obs({ taxonName: 'Nido', visibility: 'private' }))).body.data;
    expect((await beto.json('GET', `/observations/${priv.id}`)).status).toBe(404);
    expect((await ana.json('GET', `/observations/${priv.id}`)).status).toBe(200);

    const pub = (await ana.json('POST', '/observations', obs({ taxonName: 'Tagua' }))).body.data;
    expect((await beto.json('GET', `/observations/${pub.id}`)).status).toBe(200);
    await beto.json('PUT', `/users/${ana.uid}/block`);
    expect((await ana.json('GET', `/observations?user=${beto.uid}`)).status).toBe(200);
    expect((await beto.json('GET', `/observations/${pub.id}`)).status).toBe(404);
  });

  it('solo la dueña edita o borra', async () => {
    const ana = await person('obs-own-ana');
    const beto = await person('obs-own-beto');
    const o = (await ana.json('POST', '/observations', obs({ taxonName: 'Coipo' }))).body.data;
    expect((await beto.json('PATCH', `/observations/${o.id}`, { notes: 'mío' })).status).toBe(404);
    expect((await beto.json('DELETE', `/observations/${o.id}`)).status).toBe(404);
    expect((await ana.json('PATCH', `/observations/${o.id}`, { notes: 'Dos individuos' })).body.data.notes).toBe('Dos individuos');
    expect((await ana.json('DELETE', `/observations/${o.id}`)).status).toBe(204);
    expect((await anon(`/observations/${o.id}`)).status).toBe(404);
  });

  it('valida los datos', async () => {
    const ana = await person('obs-val');
    const bad = [
      obs(), // sin especie ni nombre
      obs({ taxonName: 'x', latitude: 120 }),
      obs({ taxonName: 'x', observedAt: '2999-01-01T00:00:00Z' }),
      obs({ taxonName: 'x', speciesId: 'sp-no-existe' }),
      obs({ taxonName: 'x', count: 0 }),
      obs({ taxonName: 'x', extra: true }),
    ];
    for (const body of bad) expect((await ana.json('POST', '/observations', body)).status, JSON.stringify(body)).toBe(400);
    expect((await anon('/observations?bbox=1,2,3')).status).toBe(400);
    expect((await anon('/observations?bbox=10,0,5,1')).status).toBe(400);
  });

  it('sin sesión no se registra', async () => {
    const res = await call('/api/v1/observations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(obs({ taxonName: 'x' })) });
    expect(res.status).toBe(401);
  });

  it('la foto debe ser propia y sigue la visibilidad de la observación', async () => {
    const ana = await person('obs-photo-ana');
    const beto = await person('obs-photo-beto');
    const upload = async (who: { token: string }) => {
      const res = await call('/api/v1/media?purpose=observation-photo', {
        method: 'POST',
        headers: { Authorization: `Bearer ${who.token}`, 'Content-Type': 'image/jpeg' },
        body: jpegWithGps(),
      });
      return ((await res.json()) as any).data.id as string;
    };
    const betos = await upload(beto);
    expect((await ana.json('POST', '/observations', obs({ taxonName: 'x', photoAssetId: betos }))).status).toBe(400);
    const mine = await upload(ana);
    const o = (await ana.json('POST', '/observations', obs({ taxonName: 'Garza', photoAssetId: mine }))).body.data;
    expect(o.photo).toBe(`/api/v1/media/${mine}`);
    expect((await call(`/api/v1/media/${mine}`)).status).toBe(200); // pública
  });

  it('el mapa admite hasta 500 puntos; la lista normal pagina', async () => {
    const res = await anon(`/observations?bbox=-74,-41,-72,-39&limit=9999`);
    expect(res.status).toBe(200);
    const page = await anon('/observations?limit=1');
    expect(page.body.data).toHaveLength(1);
    expect(page.body.nextCursor).toBeTruthy();
  });

  it('lugares: lista vacía hasta migrar, con validación de bbox', async () => {
    expect((await anon('/places')).body.data).toEqual([]);
    expect((await anon('/places?bbox=a,b,c,d')).status).toBe(400);
  });
});

/** JPEG mínimo con EXIF (orientación + GPS) y XMP. */
function jpegWithGps(): Uint8Array {
  // TIFF little-endian: IFD0 con Orientation (0x0112) y GPSInfo (0x8825) → IFD GPS con GPSLatitude (RATIONAL×3).
  const tiff = new Uint8Array(8 + 2 + 2 * 12 + 4 + 2 + 12 + 4 + 24);
  const v = new DataView(tiff.buffer);
  tiff.set([0x49, 0x49, 0x2a, 0x00]);
  v.setUint32(4, 8, true);
  v.setUint16(8, 2, true);
  // Orientation = 6
  v.setUint16(10, 0x0112, true); v.setUint16(12, 3, true); v.setUint32(14, 1, true); v.setUint16(18, 6, true);
  // GPSInfo → offset 38
  v.setUint16(22, 0x8825, true); v.setUint16(24, 4, true); v.setUint32(26, 1, true); v.setUint32(30, 38, true);
  v.setUint32(34, 0, true);
  v.setUint16(38, 1, true);
  v.setUint16(40, 0x0002, true); v.setUint16(42, 5, true); v.setUint32(44, 3, true); v.setUint32(48, 56, true);
  v.setUint32(52, 0, true);
  [39, 1, 51, 1, 4012, 100].forEach((n, i) => v.setUint32(56 + i * 4, n, true));

  const exifHeader = [0x45, 0x78, 0x69, 0x66, 0, 0];
  const app1Len = 2 + exifHeader.length + tiff.length;
  const xmp = new TextEncoder().encode('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta exif:GPSLatitude="39,51.67S"/>');
  const parts = [
    [0xff, 0xd8],
    [0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0],
    [0xff, 0xe1, app1Len >> 8, app1Len & 0xff, ...exifHeader, ...tiff],
    [0xff, 0xe1, (xmp.length + 2) >> 8, (xmp.length + 2) & 0xff, ...xmp],
    [0xff, 0xda, 0, 2, 0x11, 0x22, 0xff, 0xd9],
  ];
  return new Uint8Array(parts.flat());
}

describe('metadatos de las fotos', () => {
  it('quita el GPS y el XMP del JPEG pero conserva la orientación', () => {
    const src = jpegWithGps();
    const out = stripLocationMetadata(src, 'image/jpeg');
    const text = new TextDecoder('latin1').decode(out);
    expect(text).not.toContain('GPSLatitude');
    expect(text).not.toContain('xap/1.0');
    // Los racionales de la latitud (39/1, 51/1) ya no están.
    const view = new DataView(out.buffer, out.byteOffset);
    const tiffStart = out.indexOf(0x49, 22); // "II" del TIFF tras el APP0 y la cabecera Exif
    expect(view.getUint32(tiffStart + 56, true)).toBe(0);
    // Orientación intacta.
    expect(view.getUint16(tiffStart + 18, true)).toBe(6);
    expect(out.slice(-4)).toEqual(new Uint8Array([0x11, 0x22, 0xff, 0xd9]));
  });

  it('la foto subida se guarda ya limpia', async () => {
    const ana = await person('meta-ana');
    const res = await call('/api/v1/media?purpose=observation-photo', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ana.token}`, 'Content-Type': 'image/jpeg' },
      body: jpegWithGps(),
    });
    const id = ((await res.json()) as any).data.id;
    const stored = new Uint8Array(await (await call(`/api/v1/media/${id}`, { headers: { Authorization: `Bearer ${ana.token}` } })).arrayBuffer());
    expect(new TextDecoder('latin1').decode(stored)).not.toContain('GPSLatitude');
    expect(stored.length).toBeLessThan(jpegWithGps().length);
  });

  it('PNG sin fragmentos de texto ni eXIf', () => {
    const chunk = (type: string, data: number[]) => [0, 0, 0, data.length, ...[...type].map((c) => c.charCodeAt(0)), ...data, 0, 0, 0, 0];
    const png = new Uint8Array([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ...chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
      ...chunk('tEXt', [...new TextEncoder().encode('GPS\0-39.86')]),
      ...chunk('eXIf', [1, 2, 3]),
      ...chunk('IEND', []),
    ]);
    const out = new TextDecoder('latin1').decode(stripLocationMetadata(png, 'image/png'));
    expect(out).toContain('IHDR');
    expect(out).toContain('IEND');
    expect(out).not.toContain('tEXt');
    expect(out).not.toContain('eXIf');
  });

  it('TIFF inválido se rechaza', () => {
    expect(() => clearExifGps(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]))).toThrow();
  });
});
