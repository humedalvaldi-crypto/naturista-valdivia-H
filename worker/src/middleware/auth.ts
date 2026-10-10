import { createMiddleware } from 'hono/factory';
import type { JWTVerifyGetKey } from 'jose';
import { InvalidTokenError, verifyFirebaseIdToken } from '../services/firebase-auth';
import { HttpError, unauthorized } from '../services/http-error';
import type { AppBindings, AuthUser } from '../types/env';
import type { Context } from 'hono';

/**
 * Revisa en D1 que la sesión siga vigente:
 * - rechaza tokens emitidos antes de "cerrar sesión en todos los dispositivos";
 * - rechaza tokens anteriores a la eliminación de la cuenta (no se reviven datos);
 * - una cuenta suspendida solo puede leer, exportar o eliminar sus datos.
 */
async function checkSession(c: Context<AppBindings>, user: AuthUser) {
  const row = await c.env.DB.prepare(
    `SELECT u.id AS id, u.status, u.consent_version, u.tokens_valid_after, d.deleted_at
     FROM (SELECT ?1 AS uid) x
     LEFT JOIN users u ON u.id = x.uid
     LEFT JOIN deleted_accounts d ON d.uid = x.uid`,
  )
    .bind(user.uid)
    .first<{ id: string | null; status: string | null; consent_version: string | null; tokens_valid_after: string | null; deleted_at: string | null }>();
  const authMs = user.authTime * 1000;
  const before = (iso: string | null | undefined) => iso != null && authMs < Date.parse(iso);
  if (before(row?.tokens_valid_after) || before(row?.deleted_at)) {
    throw new HttpError(401, 'session_revoked', 'La sesión fue cerrada. Vuelve a iniciar sesión.');
  }
  const status = row?.status ?? null;
  const method = c.req.method;
  const ownDataAction = c.req.path.startsWith('/api/v1/me') && (method === 'DELETE' || method === 'GET');
  if (status === 'suspended' && method !== 'GET' && method !== 'HEAD' && !ownDataAction) {
    throw new HttpError(403, 'account_suspended', 'La cuenta está suspendida.');
  }
  c.set('account', { exists: row?.id != null, status, consentVersion: row?.consent_version ?? null });
}

/**
 * Escrituras de contenido: exigen haber aceptado la versión vigente de los
 * términos (y confirmado la edad mínima). Responde 428 si falta.
 */
export const requireConsent = createMiddleware<AppBindings>(async (c, next) => {
  const version = c.env.CONSENT_VERSION;
  if (!version || c.req.method === 'GET' || c.req.method === 'HEAD') return next();
  if (c.get('account')?.consentVersion !== version) {
    throw new HttpError(428, 'consent_required', 'Acepta los términos de uso para continuar.');
  }
  await next();
});

/**
 * Exige `Authorization: Bearer <Firebase ID token>` válido y deja la identidad
 * verificada en `c.get('user')`. El token nunca se registra.
 */
export function requireAuth(keyResolver: () => JWTVerifyGetKey) {
  return createMiddleware<AppBindings>(async (c, next) => {
    const header = c.req.header('Authorization') ?? '';
    const match = /^Bearer ([A-Za-z0-9\-_.]+)$/.exec(header);
    if (!match?.[1]) throw unauthorized();

    try {
      const user = await verifyFirebaseIdToken(match[1], {
        projectId: c.env.FIREBASE_PROJECT_ID,
        keyResolver: keyResolver(),
      });
      c.set('user', user);
      await checkSession(c, user);
    } catch (err) {
      if (err instanceof InvalidTokenError) {
        // Solo el motivo, nunca el token.
        console.warn(JSON.stringify({ level: 'warn', event: 'auth_rejected', reason: err.reason, requestId: c.get('requestId') }));
        throw unauthorized(err.reason === 'expired' ? 'La sesión expiró. Vuelve a iniciar sesión.' : 'Token de sesión inválido.');
      }
      throw err;
    }
    await next();
  });
}

/**
 * Autenticación opcional: sin cabecera continúa como anónimo; con una
 * cabecera inválida responde 401 (no se ignora un token malo en silencio).
 */
export function optionalAuth(keyResolver: () => JWTVerifyGetKey) {
  const strict = requireAuth(keyResolver);
  return createMiddleware<AppBindings>(async (c, next) => {
    if (!c.req.header('Authorization')) return next();
    return strict(c, async () => {
      c.set('maybeUser', c.get('user'));
      await next();
    });
  });
}
