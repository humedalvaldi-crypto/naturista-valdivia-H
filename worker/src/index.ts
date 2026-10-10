import { createApp } from './app';
import { NotebooksRepository } from './repositories/notebooks';
import { TRASH_DAYS } from './routes/notebooks';
import { purgeMedia } from './services/maintenance';
import type { Env } from './types/env';

const app = createApp();

// Punto de entrada del Worker. Solo exporta el handler por defecto:
// workerd trata cualquier otra exportación como un handler y fallaría al arrancar.
export default {
  fetch: app.fetch,
  /** Cron diario (wrangler.toml → [triggers]): vacía la papelera (30 días) y limpia archivos. */
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(
      (async () => {
        const trash = await new NotebooksRepository(env.DB).purgeTrash(TRASH_DAYS);
        const media = await purgeMedia(env);
        console.log(JSON.stringify({ level: 'info', event: 'maintenance', notebooksPurged: trash, ...media }));
      })(),
    );
  },
} satisfies ExportedHandler<Env>;
