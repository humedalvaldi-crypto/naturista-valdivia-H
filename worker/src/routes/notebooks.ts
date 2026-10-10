import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { NotebooksRepository, type ElementRow, type NotebookRow, type PageRow } from '../repositories/notebooks';
import { UsersRepository } from '../repositories/users';
import { mediaPath, parseBody } from '../services/dto';
import { badRequest, HttpError, notFound } from '../services/http-error';
import type { AppBindings } from '../types/env';
import {
  createNotebookSchema,
  MAX_PAGE_BODY_BYTES,
  PAGE_HEIGHT,
  PAGE_WIDTH,
  pageOrderSchema,
  savePageSchema,
  updateNotebookSchema,
} from '../validators/notebooks';

/** Archivos que se pueden poner en una página. */
const NOTEBOOK_MEDIA_PURPOSES = ['notebook-photo', 'notebook-audio', 'observation-photo', 'post-photo'];

const notebookDto = (n: NotebookRow) => ({
  id: n.id,
  ownerId: n.owner_id,
  title: n.title,
  description: n.description,
  color: n.color,
  cover: mediaPath(n.cover_asset_id),
  visibility: n.visibility,
  pageCount: n.page_count,
  createdAt: n.created_at,
  updatedAt: n.updated_at,
});

const pageDto = (p: PageRow) => ({
  id: p.id,
  notebookId: p.notebook_id,
  position: p.position,
  title: p.title,
  pageDate: p.page_date,
  locationName: p.location_name,
  latitude: p.latitude,
  longitude: p.longitude,
  locationSource: p.location_source,
  weather: p.weather,
  paper: p.paper,
  version: p.version,
  elementCount: p.element_count,
  updatedAt: p.updated_at,
});

const elementDto = (e: ElementRow) => ({
  id: e.id,
  type: e.type,
  x: e.x,
  y: e.y,
  width: e.width,
  height: e.height,
  rotation: e.rotation,
  z: e.z,
  data: JSON.parse(e.data_json) as Record<string, unknown>,
  mediaAssetId: e.media_asset_id,
  mediaUrl: mediaPath(e.media_asset_id),
});

const viewerOf = (c: { get: (k: 'maybeUser' | 'user') => { uid: string } | undefined }) =>
  c.get('user')?.uid ?? c.get('maybeUser')?.uid ?? null;

/** El cuaderno, si quien pide puede verlo (dueña o público). */
async function readable(repo: NotebooksRepository, id: string, viewer: string | null) {
  const n = await repo.get(id);
  if (!n || (n.visibility !== 'public' && n.owner_id !== viewer)) throw notFound('Cuaderno no encontrado.');
  return n;
}

/** El cuaderno, solo si quien pide es la dueña. Mismo 404 en otro caso. */
async function owned(repo: NotebooksRepository, id: string, uid: string) {
  const n = await repo.get(id);
  if (!n || n.owner_id !== uid) throw notFound('Cuaderno no encontrado.');
  return n;
}

/** Comprueba que los archivos usados son propios y aptos; los hace públicos si el cuaderno lo es. */
async function checkMedia(db: D1Database, ownerId: string, ids: string[], makePublic: boolean) {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return;
  const ph = unique.map((_, i) => `?${i + 2}`).join(', ');
  const rows = await db
    .prepare(`SELECT id, purpose FROM media_assets WHERE owner_id = ?1 AND status = 'active' AND id IN (${ph})`)
    .bind(ownerId, ...unique)
    .all<{ id: string; purpose: string }>();
  const ok = rows.results.filter((r) => NOTEBOOK_MEDIA_PURPOSES.includes(r.purpose));
  if (ok.length !== unique.length) throw badRequest('Algún archivo de la página no es válido.');
  if (makePublic) {
    await db.prepare(`UPDATE media_assets SET visibility = 'public' WHERE id IN (${ph}) AND owner_id = ?1`).bind(ownerId, ...unique).run();
  }
}

/**
 * /api/v1/notebooks
 * GET    /?owner=<uid>          cuadernos (míos con sesión; de otra persona, solo públicos)
 * POST   /                      crear
 * GET    /:id                   ver (dueña o público)
 * PATCH  /:id                   editar (dueña)
 * DELETE /:id                   borrar (dueña)
 * POST   /:id/duplicate         duplicar (dueña)
 * GET    /:id/pages             páginas
 * POST   /:id/pages             agregar página al final (dueña)
 * PUT    /:id/page-order        reordenar (dueña)
 * GET    /trash                 papelera: borrados hace menos de 30 días (dueña)
 * POST   /:id/restore           sacar de la papelera (dueña)
 * PUT|DELETE /:id/like           me gusta / quitarlo (sesión; cuaderno visible)
 */
export const TRASH_DAYS = 30;
export const notebooksRoutes = new Hono<AppBindings>()
  .get('/', async (c) => {
    const viewer = viewerOf(c);
    const owner = c.req.query('owner') ?? viewer;
    if (!owner) throw new HttpError(401, 'unauthorized', 'Autenticación requerida.');
    const rows = await new NotebooksRepository(c.env.DB).listByOwner(owner, owner === viewer);
    return c.json({ data: rows.map(notebookDto) });
  })
  .post('/', async (c) => {
    const input = await parseBody(c, createNotebookSchema);
    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);
    const repo = new NotebooksRepository(c.env.DB);
    const id = crypto.randomUUID();
    await repo.create({
      id,
      ownerId: user.uid,
      title: input.title,
      description: input.description ?? null,
      color: input.color ?? '#2E5B2A',
      visibility: input.visibility ?? 'private',
    });
    await repo.addPage(id, crypto.randomUUID(), new Date().toISOString().slice(0, 10));
    return c.json({ data: notebookDto((await repo.get(id))!) }, 201);
  })
  .get('/trash', async (c) => {
    const viewer = viewerOf(c);
    if (!viewer) throw new HttpError(401, 'unauthorized', 'Autenticación requerida.');
    const rows = await new NotebooksRepository(c.env.DB).trash(viewer, TRASH_DAYS);
    return c.json({ data: rows.map((n) => ({ ...notebookDto(n), deletedAt: n.deleted_at })) });
  })
  .post('/:id/restore', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    if (!(await repo.restore(c.req.param('id'), c.get('user').uid, TRASH_DAYS))) throw notFound('Cuaderno no encontrado en la papelera.');
    return c.json({ data: notebookDto((await repo.get(c.req.param('id')))!) });
  })
  .get('/:id', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const viewer = viewerOf(c);
    const n = await readable(repo, c.req.param('id'), viewer);
    return c.json({ data: { ...notebookDto(n), ...(await repo.likes(n.id, viewer)) } });
  })
  .put('/:id/like', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const uid = c.get('user').uid;
    const n = await readable(repo, c.req.param('id'), uid);
    await new UsersRepository(c.env.DB).upsertFromAuth(c.get('user'));
    await repo.like(n.id, uid);
    return c.json({ data: await repo.likes(n.id, uid) });
  })
  .delete('/:id/like', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const uid = c.get('user').uid;
    const n = await readable(repo, c.req.param('id'), uid);
    await repo.unlike(n.id, uid);
    return c.json({ data: await repo.likes(n.id, uid) });
  })
  .patch('/:id', async (c) => {
    const input = await parseBody(c, updateNotebookSchema);
    const uid = c.get('user').uid;
    const repo = new NotebooksRepository(c.env.DB);
    const n = await owned(repo, c.req.param('id'), uid);
    if (input.coverAssetId) await checkMedia(c.env.DB, uid, [input.coverAssetId], false);
    await repo.update(n.id, input);
    // Al hacerlo público, sus imágenes deben poder verse.
    if (input.visibility === 'public') {
      const ids = (
        await c.env.DB.prepare(
          `SELECT DISTINCT e.media_asset_id AS id FROM notebook_elements e JOIN notebook_pages p ON p.id = e.page_id
           WHERE p.notebook_id = ?1 AND e.media_asset_id IS NOT NULL`,
        )
          .bind(n.id)
          .all<{ id: string }>()
      ).results.map((r) => r.id);
      const cover = input.coverAssetId ?? n.cover_asset_id;
      await checkMedia(c.env.DB, uid, cover ? [...ids, cover] : ids, true);
    }
    return c.json({ data: notebookDto((await repo.get(n.id))!) });
  })
  .delete('/:id', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const n = await owned(repo, c.req.param('id'), c.get('user').uid);
    await repo.softDelete(n.id);
    return c.body(null, 204);
  })
  .post('/:id/duplicate', async (c) => {
    const uid = c.get('user').uid;
    const repo = new NotebooksRepository(c.env.DB);
    const n = await owned(repo, c.req.param('id'), uid);
    const id = crypto.randomUUID();
    await repo.duplicateNotebook(n, id, uid);
    return c.json({ data: notebookDto((await repo.get(id))!) }, 201);
  })
  .get('/:id/pages', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const n = await readable(repo, c.req.param('id'), viewerOf(c));
    return c.json({ data: (await repo.listPages(n.id)).map(pageDto) });
  })
  .post('/:id/pages', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const n = await owned(repo, c.req.param('id'), c.get('user').uid);
    if (n.page_count >= 500) throw badRequest('El cuaderno alcanzó el máximo de 500 páginas.');
    const id = crypto.randomUUID();
    await repo.addPage(n.id, id, new Date().toISOString().slice(0, 10));
    const page = await repo.getPage(id);
    return c.json({ data: page ? pageDto(page) : { id } }, 201);
  })
  .put('/:id/page-order', async (c) => {
    const { pageIds } = await parseBody(c, pageOrderSchema);
    const repo = new NotebooksRepository(c.env.DB);
    const n = await owned(repo, c.req.param('id'), c.get('user').uid);
    if (!(await repo.reorder(n.id, pageIds))) throw badRequest('La lista debe contener exactamente las páginas del cuaderno.');
    return c.json({ data: (await repo.listPages(n.id)).map(pageDto) });
  });

/**
 * /api/v1/pages
 * GET    /:id             página con sus elementos (dueña o cuaderno público)
 * PUT    /:id             guardar página completa (dueña; exige `version`)
 * DELETE /:id             borrar página (dueña)
 * POST   /:id/duplicate   duplicar página (dueña)
 */
export const pagesRoutes = new Hono<AppBindings>()
  .get('/:id', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const page = await repo.getPage(c.req.param('id'));
    const viewer = viewerOf(c);
    if (!page || (page.visibility !== 'public' && page.owner_id !== viewer)) throw notFound('Página no encontrada.');
    return c.json({
      data: {
        ...pageDto(page),
        canvas: { width: PAGE_WIDTH, height: PAGE_HEIGHT },
        editable: page.owner_id === viewer,
        elements: (await repo.elements(page.id)).map(elementDto),
      },
    });
  })
  .put(
    '/:id',
    bodyLimit({
      maxSize: MAX_PAGE_BODY_BYTES,
      onError: () => {
        throw new HttpError(413, 'payload_too_large', 'La página es demasiado grande para guardarse.');
      },
    }),
    async (c) => {
      const input = await parseBody(c, savePageSchema);
      const uid = c.get('user').uid;
      const repo = new NotebooksRepository(c.env.DB);
      const page = await repo.getPage(c.req.param('id'));
      if (!page || page.owner_id !== uid) throw notFound('Página no encontrada.');

      const mediaIds = input.elements.map((e) => e.mediaAssetId).filter((v): v is string => typeof v === 'string');
      await checkMedia(c.env.DB, uid, mediaIds, page.visibility === 'public');

      const newVersion = await repo.savePage({ id: page.id, notebookId: page.notebook_id }, input);
      if (newVersion === null) {
        const current = await repo.getPage(page.id);
        throw new HttpError(409, 'version_conflict', 'La página cambió en otro dispositivo. Recárgala para no perder cambios.', {
          currentVersion: current?.version ?? null,
        });
      }
      return c.json({ data: { id: page.id, version: newVersion } });
    },
  )
  .delete('/:id', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const page = await repo.getPage(c.req.param('id'));
    if (!page || page.owner_id !== c.get('user').uid) throw notFound('Página no encontrada.');
    await repo.deletePage(page);
    return c.body(null, 204);
  })
  .post('/:id/duplicate', async (c) => {
    const repo = new NotebooksRepository(c.env.DB);
    const page = await repo.getPage(c.req.param('id'));
    if (!page || page.owner_id !== c.get('user').uid) throw notFound('Página no encontrada.');
    const id = crypto.randomUUID();
    await repo.duplicatePage(page, id);
    const copy = await repo.getPage(id);
    return c.json({ data: copy ? pageDto(copy) : { id } }, 201);
  });
