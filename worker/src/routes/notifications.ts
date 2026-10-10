import { Hono } from 'hono';
import { NotificationsRepository, type NotificationRow } from '../repositories/notifications';
import { UsersRepository } from '../repositories/users';
import { parseBody, personDto } from '../services/dto';
import { HttpError } from '../services/http-error';
import { decodeCursor, paginate, parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { markReadSchema, reportSchema } from '../validators/social';

const notificationDto = (n: NotificationRow) => ({
  id: n.id,
  type: n.type,
  actor: n.actor_id
    ? personDto({
        id: n.actor_id,
        username: n.actor_username,
        full_name: n.actor_full_name,
        display_name: n.actor_display_name,
        photo_asset_id: n.actor_photo_asset_id,
      })
    : null,
  postId: n.post_id,
  conversationId: n.conversation_id,
  notebookId: n.notebook_id,
  body: n.body,
  createdAt: n.created_at,
  read: n.read_at !== null,
});

/** /api/v1/me/notifications */
export const notificationsRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const limit = parseLimit(c.req.query('limit'));
    const rows = await new NotificationsRepository(c.env.DB).list(c.get('user').uid, limit, decodeCursor(c.req.query('cursor')));
    const { items, nextCursor } = paginate(rows, limit);
    return c.json({ data: items.map(notificationDto), nextCursor });
  })
  .get('/unread-count', async (c) => {
    return c.json({ data: { unread: await new NotificationsRepository(c.env.DB).unreadCount(c.get('user').uid) } });
  })
  .post('/read', async (c) => {
    const { ids } = await parseBody(c, markReadSchema);
    await new NotificationsRepository(c.env.DB).markRead(c.get('user').uid, ids ?? null);
    return c.body(null, 204);
  });

/** POST /api/v1/reports — denunciar contenido o personas. Idempotente por persona y objetivo. */
export const reportsRoutes = new Hono<AppBindings>().post('/', async (c) => {
  const input = await parseBody(c, reportSchema);
  const user = c.get('user');
  if (input.targetType === 'user' && input.targetId === user.uid) {
    throw new HttpError(400, 'invalid_request', 'No puedes denunciarte a ti.');
  }
  await new UsersRepository(c.env.DB).upsertFromAuth(user);
  await c.env.DB.prepare(
    `INSERT INTO reports (id, reporter_id, target_type, target_id, reason, details) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
     ON CONFLICT (reporter_id, target_type, target_id) DO NOTHING`,
  )
    .bind(crypto.randomUUID(), user.uid, input.targetType, input.targetId, input.reason, input.details ?? null)
    .run();
  return c.json({ data: { received: true } }, 202);
});
