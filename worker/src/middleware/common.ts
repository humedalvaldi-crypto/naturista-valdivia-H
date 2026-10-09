import { cors } from 'hono/cors';
import { createMiddleware } from 'hono/factory';
import type { ErrorHandler, NotFoundHandler } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { HttpError } from '../services/http-error';
import type { AppBindings } from '../types/env';

/** Asigna un identificador de petición para correlacionar registros. */
export const requestId = createMiddleware<AppBindings>(async (c, next) => {
  const id = c.req.header('cf-ray') ?? crypto.randomUUID();
  c.set('requestId', id);
  await next();
  c.header('X-Request-Id', id);
});

/** Cabeceras de seguridad para una API JSON. */
export const securityHeaders = createMiddleware<AppBindings>(async (c, next) => {
  await next();
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('Referrer-Policy', 'no-referrer');
  c.header('Cache-Control', c.res.headers.get('Cache-Control') ?? 'no-store');
});

export function parseAllowedOrigins(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0 && o !== '*');
}

/** CORS limitado a la lista blanca de ALLOWED_ORIGINS (sin comodines). */
export const corsPolicy = createMiddleware<AppBindings>(async (c, next) => {
  const allowed = parseAllowedOrigins(c.env.ALLOWED_ORIGINS);
  return cors({
    origin: (origin) => (allowed.includes(origin) ? origin : null),
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Authorization', 'Content-Type'],
    exposeHeaders: ['X-Request-Id'],
    maxAge: 600,
  })(c, next);
});

/** Respuesta de error uniforme: { error: { code, message, details?, requestId } } */
export const errorHandler: ErrorHandler<AppBindings> = (err, c) => {
  const rid = c.get('requestId');
  if (err instanceof HttpError) {
    return c.json(
      { error: { code: err.code, message: err.message, details: err.details, requestId: rid } },
      err.status,
    );
  }
  if (err instanceof HTTPException) {
    const status = err.status;
    const code = status === 413 ? 'payload_too_large' : 'http_error';
    return c.json({ error: { code, message: err.message || 'Error de solicitud.', requestId: rid } }, status);
  }
  // Error no previsto: se registra el tipo y mensaje, sin cabeceras ni cuerpo.
  console.error(JSON.stringify({ level: 'error', event: 'unhandled', requestId: rid, name: (err as Error).name, message: (err as Error).message }));
  return c.json({ error: { code: 'internal_error', message: 'Error interno del servidor.', requestId: rid } }, 500);
};

export const notFoundHandler: NotFoundHandler<AppBindings> = (c) =>
  c.json({ error: { code: 'not_found', message: 'Ruta no encontrada.', requestId: c.get('requestId') } }, 404);
