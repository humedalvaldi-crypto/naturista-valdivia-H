import { Hono } from 'hono';
import { AccountRepository } from '../repositories/account';
import { UsersRepository, type SettingsRow, type UserRow } from '../repositories/users';
import { badRequest } from '../services/http-error';
import type { AppBindings } from '../types/env';
import { updateSettingsSchema } from '../validators/settings';

const toUserDto = (u: UserRow) => ({
  id: u.id,
  email: u.email,
  emailVerified: u.email_verified === 1,
  displayName: u.display_name,
  photoUrl: u.photo_url,
  authProvider: u.auth_provider,
  createdAt: u.created_at,
});

const toSettingsDto = (s: SettingsRow) => ({ language: s.language, theme: s.theme, updatedAt: s.updated_at });

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
    return c.json({ data: { user: toUserDto(user), settings: settings ? toSettingsDto(settings) : null } });
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
