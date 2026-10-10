import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { JWTVerifyGetKey } from 'jose';
import { optionalAuth, requireAuth } from './middleware/auth';
import { corsPolicy, errorHandler, notFoundHandler, requestId, securityHeaders } from './middleware/common';
import { rateLimit } from './middleware/rate-limit';
import { healthRoutes } from './routes/health';
import { meRoutes } from './routes/me';
import { mediaDownloadRoutes, mediaRoutes } from './routes/media';
import { myProfileRoutes, publicProfileRoutes } from './routes/profiles';
import { firebaseKeyResolver } from './services/firebase-auth';
import { HttpError } from './services/http-error';
import type { AppBindings } from './types/env';

/** Tamaño máximo de un cuerpo JSON. Las subidas de archivos tienen su propio límite por tipo. */
export const MAX_JSON_BODY_BYTES = 64 * 1024;

export interface AppOptions {
  /** Permite inyectar claves de prueba. En producción se usa el JWKS de Google. */
  keyResolver?: () => JWTVerifyGetKey;
}

export function createApp(options: AppOptions = {}) {
  const keyResolver = options.keyResolver ?? firebaseKeyResolver;
  const auth = requireAuth(keyResolver);
  const maybeAuth = optionalAuth(keyResolver);

  const jsonLimit = bodyLimit({
    maxSize: MAX_JSON_BODY_BYTES,
    onError: () => {
      throw new HttpError(413, 'payload_too_large', 'El cuerpo de la solicitud es demasiado grande.');
    },
  });

  const app = new Hono<AppBindings>();
  app.use('*', requestId, securityHeaders, corsPolicy);
  // Todo cuerpo JSON tiene tope, salvo la subida de archivos (POST /api/v1/media).
  app.use('/api/*', async (c, next) => {
    if (c.req.method === 'POST' && c.req.path === '/api/v1/media') return next();
    return jsonLimit(c, next);
  });

  const v1 = new Hono<AppBindings>();
  v1.route('/health', healthRoutes);

  // Cuenta propia.
  v1.use('/me', auth);
  v1.use('/me/*', auth, rateLimit('RL_WRITE', { onlyWrites: true }));
  v1.route('/me/profile', myProfileRoutes);
  v1.route('/me', meRoutes);

  // Perfiles públicos.
  v1.use('/profiles/*', maybeAuth, rateLimit('RL_PUBLIC'));
  v1.route('/profiles', publicProfileRoutes);

  // Archivos: la subida, listado, enlaces y borrado exigen sesión;
  // la descarga admite dueño, archivo público o URL firmada.
  v1.post('/media', auth, rateLimit('RL_UPLOAD'));
  v1.use('/media/mine', auth);
  v1.post('/media/:id/link', auth, rateLimit('RL_WRITE'));
  v1.delete('/media/:id', auth, rateLimit('RL_WRITE'));
  v1.get('/media/:id', maybeAuth, rateLimit('RL_PUBLIC'));
  v1.route('/media', mediaRoutes);
  v1.route('/media', mediaDownloadRoutes);

  app.route('/api/v1', v1);
  app.notFound(notFoundHandler);
  app.onError(errorHandler);
  return app;
}
