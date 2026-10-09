import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { JWTVerifyGetKey } from 'jose';
import { requireAuth } from './middleware/auth';
import { corsPolicy, errorHandler, notFoundHandler, requestId, securityHeaders } from './middleware/common';
import { healthRoutes } from './routes/health';
import { meRoutes } from './routes/me';
import { firebaseKeyResolver } from './services/firebase-auth';
import { HttpError } from './services/http-error';
import type { AppBindings } from './types/env';

/** Tamaño máximo de un cuerpo JSON. Las subidas de archivos tendrán su propio límite (Fase 4). */
export const MAX_JSON_BODY_BYTES = 64 * 1024;

export interface AppOptions {
  /** Permite inyectar claves de prueba. En producción se usa el JWKS de Google. */
  keyResolver?: () => JWTVerifyGetKey;
}

export function createApp(options: AppOptions = {}) {
  const keyResolver = options.keyResolver ?? firebaseKeyResolver;
  const auth = requireAuth(keyResolver);

  const app = new Hono<AppBindings>();
  app.use('*', requestId, securityHeaders, corsPolicy);
  app.use(
    '/api/*',
    bodyLimit({
      maxSize: MAX_JSON_BODY_BYTES,
      onError: () => {
        throw new HttpError(413, 'payload_too_large', 'El cuerpo de la solicitud es demasiado grande.');
      },
    }),
  );

  const v1 = new Hono<AppBindings>();
  v1.route('/health', healthRoutes);
  v1.use('/me', auth);
  v1.use('/me/*', auth);
  v1.route('/me', meRoutes);

  app.route('/api/v1', v1);
  app.notFound(notFoundHandler);
  app.onError(errorHandler);
  return app;
}

export default createApp();
