import { Hono } from 'hono';
import { MediaRepository } from '../repositories/media';
import { ProfilesRepository, UsernameTakenError, type ProfileRow } from '../repositories/profiles';
import { UsersRepository } from '../repositories/users';
import { badRequest, HttpError, notFound } from '../services/http-error';
import type { AppBindings } from '../types/env';
import { updateProfileSchema, usernameSchema } from '../validators/profile';

const mediaPath = (id: string | null) => (id ? `/api/v1/media/${id}` : null);

export const toProfileDto = (p: ProfileRow) => ({
  userId: p.user_id,
  username: p.username,
  fullName: p.full_name,
  bio: p.bio,
  location: p.location,
  photo: mediaPath(p.photo_asset_id) ?? p.photo_url,
  banner: mediaPath(p.banner_asset_id) ?? p.banner_url,
  visibility: p.visibility,
  updatedAt: p.updated_at,
});

async function readJson(c: { req: { json: () => Promise<unknown> } }) {
  try {
    return await c.req.json();
  } catch {
    throw badRequest('El cuerpo debe ser JSON válido.');
  }
}

/** /api/v1/me/profile — perfil propio (requiere sesión). */
export const myProfileRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const uid = c.get('user').uid;
    await new UsersRepository(c.env.DB).upsertFromAuth(c.get('user'));
    const row = await new ProfilesRepository(c.env.DB).get(uid);
    return c.json({ data: row ? toProfileDto(row) : null });
  })
  .patch('/', async (c) => {
    const parsed = updateProfileSchema.safeParse(await readJson(c));
    if (!parsed.success) {
      throw badRequest(
        'Datos de perfil inválidos.',
        parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      );
    }
    const uid = c.get('user').uid;
    await new UsersRepository(c.env.DB).upsertFromAuth(c.get('user'));

    // Las imágenes del perfil deben ser archivos PROPIOS y de tipo imagen.
    const media = new MediaRepository(c.env.DB);
    for (const [field, purposes] of [
      ['photoAssetId', ['profile-photo']],
      ['bannerAssetId', ['profile-banner']],
    ] as const) {
      const id = parsed.data[field];
      if (!id) continue;
      const asset = await media.findActive(id);
      if (!asset || asset.owner_id !== uid || !(purposes as readonly string[]).includes(asset.purpose)) {
        throw badRequest(`El archivo indicado en ${field} no es válido.`);
      }
    }

    try {
      const row = await new ProfilesRepository(c.env.DB).upsert(uid, parsed.data);
      return c.json({ data: toProfileDto(row) });
    } catch (err) {
      if (err instanceof UsernameTakenError) throw new HttpError(409, 'username_taken', 'Ese nombre de usuario ya está en uso.');
      throw err;
    }
  });

/** /api/v1/profiles/:username — perfil público. */
export const publicProfileRoutes = new Hono<AppBindings>().get('/:username', async (c) => {
  const parsed = usernameSchema.safeParse(c.req.param('username'));
  if (!parsed.success) throw notFound('Perfil no encontrado.');
  const row = await new ProfilesRepository(c.env.DB).getByUsername(parsed.data);
  const viewer = c.get('maybeUser')?.uid;
  // 'followers' se resolverá con la tabla follows (Fase 5); por ahora solo el dueño.
  const visible = row && (row.visibility === 'public' || row.user_id === viewer);
  if (!visible) throw notFound('Perfil no encontrado.');
  return c.json({ data: toProfileDto(row) });
});
