import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { JWTVerifyGetKey } from 'jose';
import { optionalAuth, requireAuth, requireConsent } from './middleware/auth';
import { corsPolicy, errorHandler, notFoundHandler, requestId, securityHeaders } from './middleware/common';
import { rateLimit } from './middleware/rate-limit';
import { healthRoutes } from './routes/health';
import { meRoutes } from './routes/me';
import { communitiesRoutes } from './routes/communities';
import { mediaDownloadRoutes, mediaRoutes } from './routes/media';
import { messagesRoutes } from './routes/messages';
import { notificationsRoutes, reportsRoutes } from './routes/notifications';
import { notebooksRoutes, pagesRoutes } from './routes/notebooks';
import { observationsRoutes, placesRoutes, speciesRoutes } from './routes/observations';
import { myConnectionsRoutes, peopleRoutes } from './routes/people';
import { commentsRoutes, postsRoutes } from './routes/posts';
import { myProfileRoutes, publicProfileRoutes } from './routes/profiles';
import { firebaseKeyResolver } from './services/firebase-auth';
import { createMiddleware } from 'hono/factory';
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
  // Todo cuerpo JSON tiene tope de 64 KB, salvo la subida de archivos
  // (límite por tipo) y el guardado de una página de cuaderno (2 MB).
  app.use('/api/*', async (c, next) => {
    if (c.req.method === 'POST' && c.req.path === '/api/v1/media') return next();
    if (c.req.method === 'PUT' && /^\/api\/v1\/pages\/[^/]+$/.test(c.req.path)) return next();
    return jsonLimit(c, next);
  });

  const v1 = new Hono<AppBindings>();
  v1.route('/health', healthRoutes);

  /** Lecturas con sesión opcional; escrituras con sesión obligatoria y límite. */
  const writeLimit = rateLimit('RL_WRITE', { onlyWrites: true });
  const publicLimit = rateLimit('RL_PUBLIC');
  const readOpenWriteAuth = createMiddleware<AppBindings>(async (c, next) => {
    if (c.req.method === 'GET' || c.req.method === 'HEAD') {
      return maybeAuth(c, async () => {
        await publicLimit(c, next);
      });
    }
    return auth(c, async () => {
      // Bloquear o desbloquear es una acción de seguridad: no exige consentimiento.
      if (/\/block$/.test(c.req.path)) {
        await writeLimit(c, next);
        return;
      }
      await requireConsent(c, async () => {
        await writeLimit(c, next);
      });
    });
  });

  // Cuenta propia.
  v1.use('/me', auth);
  v1.use('/me/*', auth, writeLimit);
  v1.use('/me/profile', requireConsent);
  v1.route('/me/profile', myProfileRoutes);
  v1.route('/me/notifications', notificationsRoutes);
  v1.route('/me', myConnectionsRoutes);
  v1.route('/me', meRoutes);

  // Red social (Fase 5).
  for (const base of ['/posts', '/users', '/communities', '/notebooks', '/pages', '/observations']) {
    v1.use(base, readOpenWriteAuth);
    v1.use(`${base}/*`, readOpenWriteAuth);
  }
  v1.route('/posts', postsRoutes);
  v1.route('/users', peopleRoutes);
  v1.route('/communities', communitiesRoutes);
  v1.route('/notebooks', notebooksRoutes);
  v1.route('/pages', pagesRoutes);
  v1.route('/observations', observationsRoutes);

  // Catálogo y lugares del mapa: solo lectura pública.
  for (const base of ['/species', '/places']) {
    v1.use(base, maybeAuth, publicLimit);
    v1.use(`${base}/*`, maybeAuth, publicLimit);
  }
  v1.route('/species', speciesRoutes);
  v1.route('/places', placesRoutes);
  for (const base of ['/comments', '/conversations', '/reports']) {
    v1.use(base, auth, writeLimit);
    v1.use(`${base}/*`, auth, writeLimit);
  }
  // Denunciar no exige consentimiento; comentar y escribir mensajes sí.
  for (const base of ['/comments', '/conversations']) {
    v1.use(base, requireConsent);
    v1.use(`${base}/*`, requireConsent);
  }
  v1.route('/comments', commentsRoutes);
  v1.route('/conversations', messagesRoutes);
  v1.route('/reports', reportsRoutes);

  // Perfiles públicos.
  v1.use('/profiles/*', maybeAuth, rateLimit('RL_PUBLIC'));
  v1.route('/profiles', publicProfileRoutes);

  // Archivos: la subida, listado, enlaces y borrado exigen sesión;
  // la descarga admite dueño, archivo público o URL firmada.
  v1.post('/media', auth, requireConsent, rateLimit('RL_UPLOAD'));
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
