import { Hono } from 'hono';
import { MediaRepository } from '../repositories/media';
import { ObservationsRepository, type ObservationRow, type PlaceRow, type SpeciesRow, type ObservationWrite } from '../repositories/observations';
import { UsersRepository } from '../repositories/users';
import { mediaPath, parseBody, personDto } from '../services/dto';
import { publicLocation } from '../services/geoprivacy';
import { badRequest, notFound } from '../services/http-error';
import { decodeCursor, paginate, parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { createObservationSchema, parseBbox, TAXON_GROUPS, updateObservationSchema } from '../validators/observations';

/** Fotos válidas para una observación. */
const OBSERVATION_MEDIA_PURPOSES = ['observation-photo', 'post-photo', 'notebook-photo'];
/** Máximo de puntos por consulta del mapa. */
export const MAX_MAP_POINTS = 500;

export const speciesDto = (s: SpeciesRow) => ({
  id: s.id,
  scientificName: s.scientific_name,
  commonNameEs: s.common_name_es,
  commonNameEn: s.common_name_en,
  group: s.taxon_group,
  conservationStatus: s.conservation_status,
  origin: s.origin,
  sensitive: s.sensitive === 1,
  illustration: s.illustration,
});

/**
 * Quien observó ve todo. Para el resto, si la ubicación está oculta: solo
 * la celda pública, sin precisión ni nombre del lugar (podría delatarla).
 */
export function observationDto(o: ObservationRow, viewer: string | null) {
  const mine = o.owner_id === viewer;
  const hidden = !mine && o.obscured === 1;
  return {
    id: o.id,
    owner: personDto({
      id: o.owner_id,
      username: o.owner_username,
      full_name: o.owner_full_name,
      display_name: o.owner_display_name,
      photo_asset_id: o.owner_photo_asset_id,
    }),
    species: o.species_id
      ? {
          id: o.species_id,
          scientificName: o.sp_scientific_name,
          commonNameEs: o.sp_common_name_es,
          commonNameEn: o.sp_common_name_en,
          group: o.sp_taxon_group,
          conservationStatus: o.sp_conservation_status,
          sensitive: o.sp_sensitive === 1,
          illustration: o.sp_illustration,
        }
      : null,
    taxonName: o.taxon_name,
    count: o.individual_count,
    observedAt: o.observed_at,
    latitude: mine ? o.latitude : o.public_latitude,
    longitude: mine ? o.longitude : o.public_longitude,
    accuracyM: hidden ? null : o.accuracy_m,
    locationSource: hidden ? null : o.location_source,
    locationName: hidden ? null : o.location_name,
    obscured: o.obscured === 1,
    geoprivacy: mine ? o.geoprivacy : undefined,
    notes: o.notes,
    photo: mediaPath(o.photo_asset_id),
    visibility: o.visibility,
    isMine: mine,
    createdAt: o.created_at,
    updatedAt: o.updated_at,
  };
}

const placeDto = (p: PlaceRow) => ({
  id: p.id,
  kind: p.kind,
  name: p.name,
  description: p.description,
  latitude: p.latitude,
  longitude: p.longitude,
  geojson: p.geojson ? (JSON.parse(p.geojson) as unknown) : null,
});

const viewerOf = (c: { get: (k: 'maybeUser' | 'user') => { uid: string } | undefined }) =>
  c.get('user')?.uid ?? c.get('maybeUser')?.uid ?? null;

/** La foto debe ser propia y apta; su visibilidad sigue a la de la observación. */
async function checkPhoto(db: D1Database, ownerId: string, id: string | null, visibility: 'public' | 'private') {
  if (!id) return;
  const media = new MediaRepository(db);
  const row = await media.findActive(id);
  if (!row || row.owner_id !== ownerId || !OBSERVATION_MEDIA_PURPOSES.includes(row.purpose)) {
    throw badRequest('La foto no es válida.');
  }
  await media.setVisibility(id, visibility);
}

/**
 * /api/v1/species
 * GET /?q=&group=&limit=    buscar en el catálogo
 * GET /:id                  ficha
 */
export const speciesRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const q = c.req.query('q')?.trim().slice(0, 60) || null;
    const group = c.req.query('group') ?? null;
    if (group && !(TAXON_GROUPS as readonly string[]).includes(group)) throw badRequest('`group` no es válido.', { allowed: TAXON_GROUPS });
    const limit = Math.min(parseLimit(c.req.query('limit') ?? '50'), 50);
    const rows = await new ObservationsRepository(c.env.DB).searchSpecies(q, group, limit);
    return c.json({ data: rows.map(speciesDto) });
  })
  .get('/:id', async (c) => {
    const s = await new ObservationsRepository(c.env.DB).getSpecies(c.req.param('id'));
    if (!s) throw notFound('Especie no encontrada.');
    return c.json({ data: speciesDto(s) });
  });

/**
 * /api/v1/places
 * GET /?bbox=oeste,sur,este,norte   humedales y lugares del mapa
 */
export const placesRoutes = new Hono<AppBindings>().get('/', async (c) => {
  const bbox = parseBbox(c.req.query('bbox'));
  const rows = await new ObservationsRepository(c.env.DB).places(bbox, 500);
  return c.json({ data: rows.map(placeDto) });
});

/**
 * /api/v1/observations
 * GET    /?bbox=&user=&species=&group=&limit=&cursor=   lista (con bbox: hasta 500 puntos para el mapa)
 * POST   /                                             registrar (sesión)
 * GET    /:id                                          ver
 * PATCH  /:id                                          editar (dueña)
 * DELETE /:id                                          borrar (dueña)
 */
export const observationsRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const viewer = viewerOf(c);
    const bbox = parseBbox(c.req.query('bbox'));
    const group = c.req.query('group') ?? null;
    if (group && !(TAXON_GROUPS as readonly string[]).includes(group)) throw badRequest('`group` no es válido.');
    const rawLimit = c.req.query('limit');
    let limit = parseLimit(rawLimit);
    if (bbox && rawLimit !== undefined) {
      const n = Number(rawLimit);
      limit = Math.min(Number.isInteger(n) && n > 0 ? n : limit, MAX_MAP_POINTS);
    }
    const rows = await new ObservationsRepository(c.env.DB).list({
      viewer,
      bbox,
      ownerId: c.req.query('user') ?? null,
      speciesId: c.req.query('species') ?? null,
      group,
      limit,
      cursor: decodeCursor(c.req.query('cursor')),
    });
    const { items, nextCursor } = paginate(rows, limit);
    return c.json({ data: items.map((o) => observationDto(o, viewer)), nextCursor });
  })
  .post('/', async (c) => {
    const input = await parseBody(c, createObservationSchema);
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    const repo = new ObservationsRepository(c.env.DB);

    const species = input.speciesId ? await repo.getSpecies(input.speciesId) : null;
    if (input.speciesId && !species) throw badRequest('La especie no existe en el catálogo.');
    await checkPhoto(c.env.DB, user.uid, input.photoAssetId ?? null, input.visibility);

    const obscured = input.geoprivacy === 'obscured' || species?.sensitive === 1;
    const pub = publicLocation(input.latitude, input.longitude, obscured);
    const id = crypto.randomUUID();
    await repo.insert({
      id,
      ownerId: user.uid,
      speciesId: species?.id ?? null,
      taxonName: input.taxonName ?? null,
      count: input.count ?? null,
      observedAt: new Date(input.observedAt).toISOString(),
      latitude: input.latitude,
      longitude: input.longitude,
      accuracyM: input.accuracyM ?? null,
      locationSource: input.locationSource,
      locationName: input.locationName ?? null,
      publicLatitude: pub.lat,
      publicLongitude: pub.lng,
      obscured,
      geoprivacy: input.geoprivacy,
      notes: input.notes ?? null,
      photoAssetId: input.photoAssetId ?? null,
      visibility: input.visibility,
    });
    return c.json({ data: observationDto((await repo.getOwned(id, user.uid))!, user.uid) }, 201);
  })
  .get('/:id', async (c) => {
    const viewer = viewerOf(c);
    const o = await new ObservationsRepository(c.env.DB).get(c.req.param('id'), viewer);
    if (!o) throw notFound('Observación no encontrada.');
    return c.json({ data: observationDto(o, viewer) });
  })
  .patch('/:id', async (c) => {
    const input = await parseBody(c, updateObservationSchema);
    const uid = c.get('user').uid;
    const repo = new ObservationsRepository(c.env.DB);
    const cur = await repo.getOwned(c.req.param('id'), uid);
    if (!cur) throw notFound('Observación no encontrada.');

    const speciesId = input.speciesId !== undefined ? input.speciesId : cur.species_id;
    const species = speciesId ? await repo.getSpecies(speciesId) : null;
    if (speciesId && !species) throw badRequest('La especie no existe en el catálogo.');
    const taxonName = input.taxonName !== undefined ? input.taxonName : cur.taxon_name;
    if (!speciesId && !taxonName) throw badRequest('Indica la especie o un nombre.');

    const visibility = input.visibility ?? cur.visibility;
    const photoAssetId = input.photoAssetId !== undefined ? input.photoAssetId : cur.photo_asset_id;
    if (input.photoAssetId !== undefined || input.visibility !== undefined) await checkPhoto(c.env.DB, uid, photoAssetId, visibility);

    const latitude = input.latitude ?? cur.latitude;
    const longitude = input.longitude ?? cur.longitude;
    const geoprivacy = input.geoprivacy ?? cur.geoprivacy;
    const obscured = geoprivacy === 'obscured' || species?.sensitive === 1;
    const pub = publicLocation(latitude, longitude, obscured);
    const next: ObservationWrite = {
      id: cur.id,
      ownerId: uid,
      speciesId: species?.id ?? null,
      taxonName,
      count: input.count !== undefined ? input.count : cur.individual_count,
      observedAt: input.observedAt ? new Date(input.observedAt).toISOString() : cur.observed_at,
      latitude,
      longitude,
      accuracyM: input.accuracyM !== undefined ? input.accuracyM : cur.accuracy_m,
      locationSource: input.locationSource ?? cur.location_source,
      locationName: input.locationName !== undefined ? input.locationName : cur.location_name,
      publicLatitude: pub.lat,
      publicLongitude: pub.lng,
      obscured,
      geoprivacy,
      notes: input.notes !== undefined ? input.notes : cur.notes,
      photoAssetId,
      visibility,
    };
    await repo.update(next);
    return c.json({ data: observationDto((await repo.getOwned(cur.id, uid))!, uid) });
  })
  .delete('/:id', async (c) => {
    const ok = await new ObservationsRepository(c.env.DB).softDelete(c.req.param('id'), c.get('user').uid);
    if (!ok) throw notFound('Observación no encontrada.');
    return c.body(null, 204);
  });
