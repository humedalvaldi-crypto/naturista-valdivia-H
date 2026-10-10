import { Hono } from 'hono';
import { MessagesRepository, type ConversationRow, type MessageRow } from '../repositories/messages';
import { NotificationsRepository } from '../repositories/notifications';
import { SocialRepository } from '../repositories/social';
import { UsersRepository } from '../repositories/users';
import { parseBody, personDto } from '../services/dto';
import { badRequest, HttpError, notFound } from '../services/http-error';
import { decodeCursor, paginate, parseLimit } from '../services/pagination';
import type { AppBindings } from '../types/env';
import { openConversationSchema, sendMessageSchema } from '../validators/social';

const conversationDto = (c: ConversationRow) => ({
  id: c.id,
  with: personDto({
    id: c.other_id,
    username: c.other_username,
    full_name: c.other_full_name,
    display_name: c.other_display_name,
    photo_asset_id: c.other_photo_asset_id,
  }),
  lastMessage: c.last_body,
  lastMessageAt: c.last_message_at,
  unread: c.unread,
});

const messageDto = (m: MessageRow, me: string) => ({
  id: m.id,
  body: m.body,
  mine: m.sender_id === me,
  createdAt: m.created_at,
  readAt: m.read_at,
});

/**
 * Mensajería privada 1 a 1 (todo con sesión).
 * GET  /api/v1/conversations                 mis conversaciones
 * POST /api/v1/conversations {userId}        abrir (o recuperar) con otra persona
 * GET  /api/v1/conversations/:id/messages    mensajes (recientes primero)
 * POST /api/v1/conversations/:id/messages    enviar
 * POST /api/v1/conversations/:id/read       marcar como leídos
 */
export const messagesRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const me = c.get('user').uid;
    const rows = await new MessagesRepository(c.env.DB).listConversations(me, parseLimit(c.req.query('limit')));
    return c.json({ data: rows.map(conversationDto) });
  })
  .post('/', async (c) => {
    const { userId } = await parseBody(c, openConversationSchema);
    const me = c.get('user');
    if (userId === me.uid) throw badRequest('No puedes escribirte a ti.');
    const social = new SocialRepository(c.env.DB);
    if (!(await social.userExists(userId)) || (await social.blockedEitherWay(me.uid, userId))) {
      throw notFound('Persona no encontrada.');
    }
    await new UsersRepository(c.env.DB).upsertFromAuth(me);
    const id = await new MessagesRepository(c.env.DB).openConversation(me.uid, userId);
    return c.json({ data: { id } }, 201);
  })
  .get('/:id/messages', async (c) => {
    const me = c.get('user').uid;
    const repo = new MessagesRepository(c.env.DB);
    const conv = await repo.getForMember(c.req.param('id'), me);
    if (!conv) throw notFound('Conversación no encontrada.');
    const limit = parseLimit(c.req.query('limit'));
    const rows = await repo.list(conv.id, limit, decodeCursor(c.req.query('cursor')));
    const { items, nextCursor } = paginate(rows, limit);
    return c.json({ data: items.map((m) => messageDto(m, me)), nextCursor });
  })
  .post('/:id/messages', async (c) => {
    const { body } = await parseBody(c, sendMessageSchema);
    const me = c.get('user').uid;
    const repo = new MessagesRepository(c.env.DB);
    const conv = await repo.getForMember(c.req.param('id'), me);
    if (!conv) throw notFound('Conversación no encontrada.');
    const other = conv.user_a === me ? conv.user_b : conv.user_a;
    if (await new SocialRepository(c.env.DB).blockedEitherWay(me, other)) {
      throw new HttpError(403, 'blocked', 'No puedes enviar mensajes en esta conversación.');
    }
    const msg = await repo.send({ id: crypto.randomUUID(), conversationId: conv.id, senderId: me, body });
    await new NotificationsRepository(c.env.DB).create({ userId: other, actorId: me, type: 'message', conversationId: conv.id });
    return c.json({ data: messageDto(msg, me) }, 201);
  })
  .post('/:id/read', async (c) => {
    const me = c.get('user').uid;
    const repo = new MessagesRepository(c.env.DB);
    const conv = await repo.getForMember(c.req.param('id'), me);
    if (!conv) throw notFound('Conversación no encontrada.');
    await repo.markRead(conv.id, me);
    return c.body(null, 204);
  });
