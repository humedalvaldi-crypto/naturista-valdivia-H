import { createMiddleware } from 'hono/factory';
import type { JWTVerifyGetKey } from 'jose';
import { InvalidTokenError, verifyFirebaseIdToken } from '../services/firebase-auth';
import { unauthorized } from '../services/http-error';
import type { AppBindings } from '../types/env';

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
