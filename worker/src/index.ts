import { createApp } from './app';
import { purgeMedia } from './services/maintenance';
import type { Env } from './types/env';

const app = createApp();

// Punto de entrada del Worker. Solo exporta el handler por defecto:
// workerd trata cualquier otra exportación como un handler y fallaría al arrancar.
export default {
  fetch: app.fetch,
  /** Cron diario (wrangler.toml → [triggers]): limpieza de archivos. */
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(
      purgeMedia(env).then((r) => console.log(JSON.stringify({ level: 'info', event: 'media_purge', ...r }))),
    );
  },
} satisfies ExportedHandler<Env>;
