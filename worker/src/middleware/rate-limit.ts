import { createMiddleware } from 'hono/factory';
import { HttpError } from '../services/http-error';
import type { AppBindings, Env } from '../types/env';

type LimiterName = 'RL_WRITE' | 'RL_UPLOAD' | 'RL_PUBLIC';

/**
 * Límite de frecuencia con Cloudflare Rate Limiting. La clave es el UID del
 * usuario autenticado o, si no hay sesión, la IP (cabecera de Cloudflare).
 * Si el binding no existe (desarrollo local) no limita.
 */
export function rateLimit(name: LimiterName, opts: { onlyWrites?: boolean } = {}) {
  return createMiddleware<AppBindings>(async (c, next) => {
    if (opts.onlyWrites && ['GET', 'HEAD', 'OPTIONS'].includes(c.req.method)) return next();
    const limiter = (c.env as Env)[name];
    if (!limiter) return next();

    const who = c.get('user')?.uid ?? c.get('maybeUser')?.uid ?? `ip:${c.req.header('cf-connecting-ip') ?? 'unknown'}`;
    const { success } = await limiter.limit({ key: `${name}:${who}` });
    if (!success) {
      c.header('Retry-After', '60');
      throw new HttpError(429, 'rate_limited', 'Demasiadas solicitudes. Espera un momento e inténtalo de nuevo.');
    }
    return next();
  });
}
