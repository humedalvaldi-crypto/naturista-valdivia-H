import { Hono } from 'hono';
import type { AppBindings } from '../types/env';

/** GET /api/v1/health — estado de la API y de la base de datos. Público. */
export const healthRoutes = new Hono<AppBindings>().get('/', async (c) => {
  let database: 'ok' | 'error' = 'ok';
  try {
    await c.env.DB.prepare('SELECT 1').first();
  } catch {
    database = 'error';
  }
  const status = database === 'ok' ? 'ok' : 'degraded';
  return c.json(
    { status, version: 'v1', environment: c.env.APP_ENV, checks: { database }, time: new Date().toISOString() },
    status === 'ok' ? 200 : 503,
  );
});
