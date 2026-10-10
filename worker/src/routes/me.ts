import { Hono } from 'hono';
import { AccountRepository } from '../repositories/account';
import { SocialRepository } from '../repositories/social';
import { UsersRepository, type SettingsRow, type UserRow } from '../repositories/users';
import { parseBody, personDto } from '../services/dto';
import { badRequest } from '../services/http-error';
import type { AppBindings } from '../types/env';
import { consentSchema, feedbackSchema, NOTIFICATION_KINDS, updateSettingsSchema } from '../validators/settings';


const toUserDto = (u: UserRow) => ({
  id: u.id,
  email: u.email,
  emailVerified: u.email_verified === 1,
  displayName: u.display_name,
  photoUrl: u.photo_url,
  authProvider: u.auth_provider,
  createdAt: u.created_at,
});

function extra(s: SettingsRow): { notifications?: Record<string, boolean>; privacy?: { messages?: string } } {
  try {
    return JSON.parse(s.extra_json ?? '{}');
  } catch {
    return {};
  }
}

const toSettingsDto = (s: SettingsRow) => {
  const e = extra(s);
  return {
    language: s.language,
    theme: s.theme,
    notifications: Object.fromEntries(NOTIFICATION_KINDS.map((k) => [k, e.notifications?.[k] !== false])),
    privacy: { messages: e.privacy?.messages ?? 'everyone' },
    updatedAt: s.updated_at,
  };
};

const defaultSettings = { language: 'es', theme: 'system', notifications: { follow: true, comment: true, reaction: true, message: true }, privacy: { messages: 'everyone' }, updatedAt: null };

/**
 * Rutas del usuario autenticado. La identidad sale SIEMPRE del token
 * verificado (c.get('user')), nunca del cuerpo ni de la URL.
 */
export const meRoutes = new Hono<AppBindings>()
  // GET /api/v1/me — registra/actualiza al usuario y devuelve su cuenta y preferencias.
  .get('/', async (c) => {
    const repo = new UsersRepository(c.env.DB);
    const user = await repo.upsertFromAuth(c.get('user'));
    const settings = await repo.getSettings(user.id);
    const required = c.env.CONSENT_VERSION || null;
    return c.json({
      data: {
        user: toUserDto(user),
        settings: settings ? toSettingsDto(settings) : null,
        consent: {
          requiredVersion: required,
          minAge: Number(c.env.MIN_AGE ?? 14),
          acceptedVersion: user.consent_version ?? null,
          acceptedAt: user.consent_at ?? null,
          upToDate: required === null || user.consent_version === required,
        },
      },
    });
  })
  // POST /api/v1/me/consent — acepta los términos vigentes y confirma la edad mínima.
  .post('/consent', async (c) => {
    const input = await parseBody(c, consentSchema);
    const required = c.env.CONSENT_VERSION;
    if (required && input.version !== required) {
      throw badRequest('La versión de los términos no es la vigente. Recarga la app.');
    }
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    await c.env.DB.prepare(
      `UPDATE users SET consent_version = ?2, consent_at = ?3, age_confirmed = 1 WHERE id = ?1`,
    )
      .bind(user.uid, input.version, new Date().toISOString())
      .run();
    return c.body(null, 204);
  })
  // POST /api/v1/me/sessions/revoke — cierra la sesión en todos los dispositivos.
  .post('/sessions/revoke', async (c) => {
    const user = c.get('user');
    // Un segundo de margen: el token actual también deja de valer.
    const at = new Date(Date.now() + 1000).toISOString();
    await c.env.DB.prepare(`UPDATE users SET tokens_valid_after = ?2 WHERE id = ?1`).bind(user.uid, at).run();
    return c.body(null, 204);
  })
  // GET /api/v1/me/settings — preferencias guardadas en el servidor (avisos y privacidad).
  .get('/settings', async (c) => {
    const settings = await new UsersRepository(c.env.DB).getSettings(c.get('user').uid);
    return c.json({ data: settings ? toSettingsDto(settings) : defaultSettings });
  })
  // GET /api/v1/me/stats — números propios y espacio usado.
  .get('/stats', async (c) => {
    const uid = c.get('user').uid;
    const q = (sql: string) => c.env.DB.prepare(sql).bind(uid);
    const rows = await c.env.DB.batch<{ n: number }>([
      q('SELECT count(*) AS n FROM observations WHERE owner_id = ?1 AND deleted_at IS NULL'),
      q('SELECT count(DISTINCT species_id) AS n FROM observations WHERE owner_id = ?1 AND deleted_at IS NULL AND species_id IS NOT NULL'),
      q('SELECT count(*) AS n FROM species_unlocks WHERE user_id = ?1'),
      q('SELECT count(*) AS n FROM notebooks WHERE owner_id = ?1 AND deleted_at IS NULL'),
      q('SELECT count(*) AS n FROM notebook_pages p JOIN notebooks n ON n.id = p.notebook_id WHERE n.owner_id = ?1 AND n.deleted_at IS NULL'),
      q('SELECT count(*) AS n FROM posts WHERE author_id = ?1 AND deleted_at IS NULL'),
      q('SELECT count(*) AS n FROM follows WHERE followed_id = ?1'),
      q('SELECT count(*) AS n FROM follows WHERE follower_id = ?1'),
      q("SELECT count(*) AS n FROM media_assets WHERE owner_id = ?1 AND status = 'active'"),
      q("SELECT COALESCE(sum(size_bytes), 0) AS n FROM media_assets WHERE owner_id = ?1 AND status = 'active'"),
      q('SELECT min(observed_at) AS n FROM observations WHERE owner_id = ?1 AND deleted_at IS NULL'),
    ]);
    const v = (i: number) => (rows[i]?.results[0]?.n ?? 0) as number;
    return c.json({
      data: {
        observations: v(0),
        speciesObserved: v(1),
        speciesUnlocked: v(2),
        notebooks: v(3),
        pages: v(4),
        posts: v(5),
        followers: v(6),
        following: v(7),
        files: v(8),
        storageBytes: v(9),
        firstObservationAt: (rows[10]?.results[0]?.n as unknown as string | null) ?? null,
      },
    });
  })
  // GET /api/v1/me/blocked — personas bloqueadas (se desbloquean con DELETE /users/:id/block).
  .get('/blocked', async (c) => {
    const rows = await new SocialRepository(c.env.DB).listBlocked(c.get('user').uid);
    return c.json({ data: rows.map((r) => ({ ...personDto(r), since: r.created_at })) });
  })
  // POST /api/v1/me/feedback — mensaje al equipo del proyecto.
  .post('/feedback', async (c) => {
    const input = await parseBody(c, feedbackSchema);
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    const id = crypto.randomUUID();
    await c.env.DB.prepare(
      `INSERT INTO feedback (id, user_id, kind, message, app_version, platform) VALUES (?1, ?2, ?3, ?4, ?5, ?6)`,
    )
      .bind(id, user.uid, input.kind, input.message, input.appVersion ?? null, input.platform ?? null)
      .run();
    return c.json({ data: { id } }, 201);
  })
  // GET /api/v1/me/export — copia de todos los datos propios (JSON descargable).
  .get('/export', async (c) => {
    const uid = c.get('user').uid;
    const data = await new AccountRepository(c.env.DB).export(uid);
    return c.body(JSON.stringify(data, null, 2), 200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': 'attachment; filename="naturista-valdivia-mis-datos.json"',
      'Cache-Control': 'no-store',
    });
  })
  // DELETE /api/v1/me — elimina la cuenta y su contenido. Exige confirmación explícita.
  .delete('/', async (c) => {
    if (c.req.header('X-Confirm-Delete') !== 'ELIMINAR') {
      throw badRequest('Confirma la eliminación enviando la cabecera X-Confirm-Delete: ELIMINAR.');
    }
    await new AccountRepository(c.env.DB).delete(c.get('user').uid);
    return c.body(null, 204);
  })
  // PATCH /api/v1/me/settings — idioma y tema.
  .patch('/settings', async (c) => {
    const body = await c.req.json().catch(() => {
      throw badRequest('El cuerpo debe ser JSON válido.');
    });
    const parsed = updateSettingsSchema.safeParse(body);
    if (!parsed.success) {
      throw badRequest(
        'Datos de preferencias inválidos.',
        parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      );
    }
    const repo = new UsersRepository(c.env.DB);
    await repo.upsertFromAuth(c.get('user'));
    const settings = await repo.updateSettings(c.get('user').uid, parsed.data);
    return c.json({ data: toSettingsDto(settings) });
  });
