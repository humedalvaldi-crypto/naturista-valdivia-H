import { Hono } from 'hono';
import { CommunitiesRepository, SlugTakenError, type CommunityRow } from '../repositories/communities';
import { MediaRepository } from '../repositories/media';
import { UsersRepository } from '../repositories/users';
import { mediaPath, parseBody } from '../services/dto';
import { badRequest, HttpError, notFound } from '../services/http-error';
import { parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { createCommunitySchema } from '../validators/social';

const communityDto = (c: CommunityRow) => ({
  id: c.id,
  slug: c.slug,
  name: c.name,
  description: c.description,
  wetland: c.wetland,
  photo: mediaPath(c.photo_asset_id),
  memberCount: c.member_count,
  myRole: c.my_role,
  createdAt: c.created_at,
});

const viewerOf = (c: { get: (k: 'maybeUser' | 'user') => { uid: string } | undefined }) =>
  c.get('user')?.uid ?? c.get('maybeUser')?.uid ?? null;

/**
 * /api/v1/communities
 * GET  /?mine=1&q=&limit=&after=   listado por nombre
 * POST /                           crear (sesión)
 * GET  /:slug                      detalle
 * PUT|DELETE /:slug/membership     unirse / salir (sesión)
 */
export const communitiesRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const viewer = viewerOf(c);
    const mine = c.req.query('mine') === '1';
    if (mine && !viewer) throw new HttpError(401, 'unauthorized', 'Autenticación requerida.');
    const q = c.req.query('q')?.trim().slice(0, 60);
    // Se escapan los comodines de LIKE para buscar texto literal.
    const like = q ? `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%` : null;
    const limit = parseLimit(c.req.query('limit'));
    const after = c.req.query('after') ?? null;
    const rows = await new CommunitiesRepository(c.env.DB).list(viewer, { mine, query: like, limit, afterName: after });
    const items = rows.slice(0, limit);
    return c.json({
      data: items.map(communityDto),
      nextAfter: rows.length > limit ? (items[items.length - 1]?.name ?? null) : null,
    });
  })
  .post('/', async (c) => {
    const input = await parseBody(c, createCommunitySchema);
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    if (input.photoAssetId) {
      const asset = await new MediaRepository(c.env.DB).findActive(input.photoAssetId);
      if (!asset || asset.owner_id !== user.uid || asset.purpose !== 'community-photo') {
        throw badRequest('La imagen indicada no es válida.');
      }
    }
    const repo = new CommunitiesRepository(c.env.DB);
    try {
      await repo.create({
        id: crypto.randomUUID(),
        slug: input.slug,
        name: input.name,
        description: input.description ?? null,
        wetland: input.wetland ?? null,
        photoAssetId: input.photoAssetId ?? null,
        createdBy: user.uid,
      });
    } catch (err) {
      if (err instanceof SlugTakenError) throw new HttpError(409, 'slug_taken', 'Ya existe una comunidad con esa dirección.');
      throw err;
    }
    const row = await repo.getBySlug(input.slug, user.uid);
    return c.json({ data: row ? communityDto(row) : null }, 201);
  })
  .get('/:slug', async (c) => {
    const row = await new CommunitiesRepository(c.env.DB).getBySlug(c.req.param('slug'), viewerOf(c));
    if (!row) throw notFound('Comunidad no encontrada.');
    return c.json({ data: communityDto(row) });
  })
  .put('/:slug/membership', async (c) => {
    const user = c.get('user');
    const repo = new CommunitiesRepository(c.env.DB);
    const row = await repo.getBySlug(c.req.param('slug'), user.uid);
    if (!row) throw notFound('Comunidad no encontrada.');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    await repo.join(row.id, user.uid);
    const updated = await repo.getBySlug(row.slug, user.uid);
    return c.json({ data: updated ? communityDto(updated) : null });
  })
  .delete('/:slug/membership', async (c) => {
    const user = c.get('user');
    const repo = new CommunitiesRepository(c.env.DB);
    const row = await repo.getBySlug(c.req.param('slug'), user.uid);
    if (!row) throw notFound('Comunidad no encontrada.');
    const result = await repo.leave(row.id, user.uid);
    if (result === 'owner') throw new HttpError(409, 'owner_cannot_leave', 'Quien creó la comunidad no puede salir de ella.');
    const updated = await repo.getBySlug(row.slug, user.uid);
    return c.json({ data: updated ? communityDto(updated) : null });
  });
