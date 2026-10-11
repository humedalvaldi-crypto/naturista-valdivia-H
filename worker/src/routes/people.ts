import { Hono } from 'hono';
import { ACHIEVEMENTS, AlbumRepository } from '../repositories/album';
import { NotificationsRepository } from '../repositories/notifications';
import { ProfilesRepository } from '../repositories/profiles';
import { SocialRepository, type PersonSearchRow } from '../repositories/social';
import { UsersRepository } from '../repositories/users';
import { personDto } from '../services/dto';
import { badRequest, HttpError, notFound } from '../services/http-error';
import { parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { speciesDto } from './observations';
import { toProfileDto } from './profiles';

/**
 * /api/v1/users/:id — relaciones con otra persona (por UID).
 * GET        /?q=texto&cursor=    buscar personas (paginado, sin límite total); sin q, directorio
 * GET        /:id/followers|following  seguidores / seguidos visibles (respeta la privacidad del perfil)
 * GET        /suggestions         sugerencias de la propia red (sesión)
 * GET        /:id                 resumen público (perfil, contadores, si la sigo y si me sigue)
 * PUT|DELETE /:id/follow          seguir / dejar de seguir
 * PUT|DELETE /:id/block           bloquear / desbloquear
 * GET        /:id/album           álbum de especies y logros (lo privado solo para la propia persona)
 */
const searchDto = (r: PersonSearchRow & { mutuals?: number }) => ({
  ...personDto(r),
  followedByMe: r.followed_by_me === 1,
  followsMe: r.follows_me === 1,
  ...(r.followers !== undefined ? { followers: r.followers } : {}),
  ...(r.mutuals !== undefined ? { mutuals: r.mutuals } : {}),
});

export const peopleRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const q = (c.req.query('q') ?? '').trim();
    if (q.length === 1) throw badRequest('Escribe al menos 2 letras para buscar.');
    if (q.length > 60) throw badRequest('La búsqueda es demasiado larga.');
    const limit = parseLimit(c.req.query('limit'));
    let after: { name: string; id: string } | null = null;
    const raw = c.req.query('cursor');
    if (raw) {
      try {
        const parsed = JSON.parse(atob(raw)) as { n?: unknown; i?: unknown };
        if (typeof parsed.n !== 'string' || typeof parsed.i !== 'string') throw new Error();
        after = { name: parsed.n, id: parsed.i };
      } catch {
        throw badRequest('Cursor inválido.');
      }
    }
    const viewer = c.get('maybeUser')?.uid ?? null;
    const rows = await new SocialRepository(c.env.DB).search(viewer, q, limit, after);
    const items = rows.slice(0, limit);
    const last = items[items.length - 1];
    return c.json({
      data: items.filter((r) => r.id !== viewer).map(searchDto),
      nextCursor: rows.length > limit && last ? btoa(JSON.stringify({ n: last.sort_name ?? '', i: last.id })) : null,
    });
  })
  .get('/suggestions', async (c) => {
    const viewer = c.get('maybeUser')?.uid;
    if (!viewer) throw new HttpError(401, 'unauthorized', 'Inicia sesión para ver sugerencias.');
    const rows = await new SocialRepository(c.env.DB).suggestions(viewer, Math.min(parseLimit(c.req.query('limit')), 20));
    return c.json({ data: rows.map(searchDto) });
  })
  .get('/:id/album', async (c) => {
    const id = c.req.param('id');
    const viewer = c.get('maybeUser')?.uid ?? null;
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(id))) throw notFound('Persona no encontrada.');
    const self = viewer === id;
    if (!self) {
      if (viewer && (await social.blockedEitherWay(viewer, id))) throw notFound('Persona no encontrada.');
      const visibility = (await new ProfilesRepository(c.env.DB).get(id))?.visibility ?? 'public';
      const following = viewer ? await social.isFollowing(viewer, id) : false;
      if (!(visibility === 'public' || (visibility === 'followers' && following))) throw notFound('Persona no encontrada.');
    }
    const repo = new AlbumRepository(c.env.DB);
    const [rows, counts] = await Promise.all([repo.album(id, self), repo.counts(id, self)]);
    const species = rows.map((r) => {
      const fromObservation = r.observation_count > 0;
      const unlocked = fromObservation || r.legacy_unlocked_at !== null;
      return {
        ...speciesDto(r),
        unlocked,
        via: fromObservation ? 'observation' : r.legacy_unlocked_at ? 'legacy' : null,
        firstSeen: r.first_seen ?? r.legacy_unlocked_at,
        observationCount: r.observation_count,
      };
    });
    return c.json({
      data: {
        species,
        stats: { unlocked: species.filter((s) => s.unlocked).length, total: species.length, ...counts },
        achievements: ACHIEVEMENTS.map((a) => ({
          id: a.id,
          target: a.target,
          progress: Math.min(counts[a.metric], a.target),
          unlocked: counts[a.metric] >= a.target,
        })),
      },
    });
  })
  .get('/:id/:direction{followers|following}', async (c) => {
    const id = c.req.param('id');
    const direction = c.req.param('direction') as 'followers' | 'following';
    const viewer = c.get('maybeUser')?.uid ?? null;
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(id))) throw notFound('Persona no encontrada.');
    if (viewer && viewer !== id && (await social.blockedEitherWay(viewer, id))) throw notFound('Persona no encontrada.');
    const visibility = (await new ProfilesRepository(c.env.DB).get(id))?.visibility ?? 'public';
    const canSee = viewer === id || visibility === 'public' || (visibility === 'followers' && viewer !== null && (await social.isFollowing(viewer, id)));
    if (!canSee) throw new HttpError(403, 'profile_restricted', 'Este perfil es privado.');
    const limit = parseLimit(c.req.query('limit'));
    const before = c.req.query('before') ?? null;
    const rows = await social.listConnections(id, direction, limit, before, viewer);
    const items = rows.slice(0, limit);
    return c.json({
      data: items.map((r) => ({ ...personDto(r), since: r.created_at, followedByMe: r.followed_by_me === 1, followsMe: r.follows_me === 1 })),
      nextBefore: rows.length > limit ? (items[items.length - 1]?.created_at ?? null) : null,
    });
  })
  .get('/:id', async (c) => {
    const id = c.req.param('id');
    const viewer = c.get('maybeUser')?.uid ?? null;
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(id))) throw notFound('Persona no encontrada.');
    if (viewer && viewer !== id && (await social.blockedEitherWay(viewer, id))) throw notFound('Persona no encontrada.');

    const profile = await new ProfilesRepository(c.env.DB).get(id);
    const visibility = profile?.visibility ?? 'public';
    const following = viewer ? await social.isFollowing(viewer, id) : false;
    const canSee = viewer === id || visibility === 'public' || (visibility === 'followers' && following);
    const user = await new UsersRepository(c.env.DB).findById(id);

    return c.json({
      data: {
        id,
        name: profile?.full_name ?? user?.display_name ?? profile?.username ?? 'Naturalista',
        username: profile?.username ?? null,
        profile: canSee && profile ? toProfileDto(profile) : null,
        restricted: !canSee,
        counts: await social.counts(id),
        followedByMe: following,
        followsMe: viewer && viewer !== id ? await social.isFollowing(id, viewer) : false,
        isMe: viewer === id,
      },
    });
  })
  .put('/:id/follow', async (c) => {
    const me = c.get('user');
    const target = c.req.param('id');
    if (target === me.uid) throw badRequest('No puedes seguirte a ti.');
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(target)) || (await social.blockedEitherWay(me.uid, target))) {
      throw notFound('Persona no encontrada.');
    }
    await new UsersRepository(c.env.DB).upsertFromAuth(me);
    if (await social.follow(me.uid, target)) {
      await new NotificationsRepository(c.env.DB).create({ userId: target, actorId: me.uid, type: 'follow' });
    }
    return c.json({ data: { following: true, counts: await social.counts(target) } });
  })
  .delete('/:id/follow', async (c) => {
    const social = new SocialRepository(c.env.DB);
    await social.unfollow(c.get('user').uid, c.req.param('id'));
    return c.json({ data: { following: false, counts: await social.counts(c.req.param('id')) } });
  })
  .put('/:id/block', async (c) => {
    const me = c.get('user');
    const target = c.req.param('id');
    if (target === me.uid) throw badRequest('No puedes bloquearte a ti.');
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(target))) throw notFound('Persona no encontrada.');
    await new UsersRepository(c.env.DB).upsertFromAuth(me);
    await social.block(me.uid, target);
    return c.body(null, 204);
  })
  .delete('/:id/block', async (c) => {
    await new SocialRepository(c.env.DB).unblock(c.get('user').uid, c.req.param('id'));
    return c.body(null, 204);
  });

/** /api/v1/me/followers y /api/v1/me/following (paginados por fecha). */
export const myConnectionsRoutes = new Hono<AppBindings>().get('/:direction{followers|following}', async (c) => {
  const direction = c.req.param('direction') as 'followers' | 'following';
  const limit = parseLimit(c.req.query('limit'));
  const before = c.req.query('before') ?? null;
  const rows = await new SocialRepository(c.env.DB).listConnections(c.get('user').uid, direction, limit, before);
  const items = rows.slice(0, limit);
  return c.json({
    data: items.map((r) => ({ ...personDto(r), since: r.created_at })),
    nextBefore: rows.length > limit ? (items[items.length - 1]?.created_at ?? null) : null,
  });
});
