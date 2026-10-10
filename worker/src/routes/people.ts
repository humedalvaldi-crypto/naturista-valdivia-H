import { Hono } from 'hono';
import { NotificationsRepository } from '../repositories/notifications';
import { ProfilesRepository } from '../repositories/profiles';
import { SocialRepository } from '../repositories/social';
import { UsersRepository } from '../repositories/users';
import { personDto } from '../services/dto';
import { badRequest, notFound } from '../services/http-error';
import { parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { toProfileDto } from './profiles';

/**
 * /api/v1/users/:id — relaciones con otra persona (por UID).
 * GET        /:id                 resumen público (perfil, contadores, si la sigo)
 * PUT|DELETE /:id/follow          seguir / dejar de seguir
 * PUT|DELETE /:id/block           bloquear / desbloquear
 */
export const peopleRoutes = new Hono<AppBindings>()
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
