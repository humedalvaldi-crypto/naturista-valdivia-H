import { Hono } from 'hono';
import { MediaRepository, type MediaRow } from '../repositories/media';
import { UsersRepository } from '../repositories/users';
import { declaredMatches, isPurpose, MAX_UPLOAD_BYTES, PURPOSES, sniff, type MediaPurpose } from '../services/media-types';
import { badRequest, HttpError, notFound } from '../services/http-error';
import { decodeCursor, paginate, parseLimit } from '../services/pagination';
import { signMediaAccess, verifyMediaAccess } from '../services/signed-url';
import type { AppBindings } from '../types/env';

/** Propósitos cuyos archivos son públicos por naturaleza (se muestran en perfiles y grupos). */
const PUBLIC_PURPOSES: ReadonlySet<MediaPurpose> = new Set(['profile-photo', 'profile-banner', 'community-photo']);

const toMediaDto = (m: MediaRow) => ({
  id: m.id,
  purpose: m.purpose,
  contentType: m.content_type,
  size: m.size_bytes,
  sha256: m.sha256,
  visibility: m.visibility,
  url: `/api/v1/media/${m.id}`,
  createdAt: m.created_at,
});

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Lee el cuerpo con un tope: corta en cuanto supera `max` bytes. */
async function readLimited(body: ReadableStream<Uint8Array> | null, max: number): Promise<Uint8Array> {
  if (!body) throw badRequest('Falta el archivo en el cuerpo de la solicitud.');
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      throw new HttpError(413, 'file_too_large', `El archivo supera el máximo de ${Math.round(max / 1024 / 1024)} MB.`);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.byteLength;
  }
  return out;
}

/**
 * Rutas autenticadas de archivos (montadas bajo /api/v1/media con requireAuth).
 *
 * POST /?purpose=observation-photo   cuerpo = bytes del archivo, Content-Type real
 * GET  /mine?limit=&cursor=           archivos propios, paginados
 * POST /:id/link                      URL firmada temporal (1 h)
 * DELETE /:id                         borrado (solo el dueño)
 */
export const mediaRoutes = new Hono<AppBindings>()
  .post('/', async (c) => {
    const purpose = c.req.query('purpose');
    if (!isPurpose(purpose)) throw badRequest('`purpose` no es válido.', { allowed: Object.keys(PURPOSES) });
    const rule = PURPOSES[purpose];

    const declaredLength = Number(c.req.header('Content-Length') ?? '0');
    if (declaredLength > rule.maxBytes) {
      throw new HttpError(413, 'file_too_large', `El archivo supera el máximo de ${Math.round(rule.maxBytes / 1024 / 1024)} MB.`);
    }

    const bytes = await readLimited(c.req.raw.body, Math.min(rule.maxBytes, MAX_UPLOAD_BYTES));
    if (bytes.byteLength === 0) throw badRequest('El archivo está vacío.');

    const type = sniff(bytes);
    if (!type || !(rule.kinds as readonly string[]).includes(type.kind)) {
      throw new HttpError(415, 'unsupported_media_type', 'Tipo de archivo no admitido para este uso.');
    }
    if (!declaredMatches(c.req.header('Content-Type'), type)) {
      throw new HttpError(415, 'content_type_mismatch', 'El tipo declarado no coincide con el contenido del archivo.');
    }

    const user = c.get('user');
    await new UsersRepository(c.env.DB).upsertFromAuth(user);

    const id = crypto.randomUUID();
    const objectKey = `u/${user.uid}/${purpose}/${id}.${type.ext}`; // generado por el servidor
    const hash = await sha256Hex(bytes);
    const visibility = PUBLIC_PURPOSES.has(purpose) ? 'public' : 'private';

    await c.env.MEDIA.put(objectKey, bytes, {
      httpMetadata: { contentType: type.mime },
      customMetadata: { owner: user.uid, assetId: id },
      sha256: hash,
    });
    try {
      const row = await new MediaRepository(c.env.DB).insert({
        id,
        ownerId: user.uid,
        purpose,
        objectKey,
        contentType: type.mime,
        sizeBytes: bytes.byteLength,
        sha256: hash,
        visibility,
      });
      return c.json({ data: toMediaDto(row) }, 201);
    } catch (err) {
      // Si no se pudo registrar, no dejamos el objeto huérfano en R2.
      await c.env.MEDIA.delete(objectKey).catch(() => undefined);
      throw err;
    }
  })
  .get('/mine', async (c) => {
    const limit = parseLimit(c.req.query('limit'));
    const cursor = decodeCursor(c.req.query('cursor'));
    const rows = await new MediaRepository(c.env.DB).listByOwner(c.get('user').uid, limit, cursor);
    const { items, nextCursor } = paginate(rows, limit);
    return c.json({ data: items.map(toMediaDto), nextCursor });
  })
  .post('/:id/link', async (c) => {
    const secret = c.env.MEDIA_SIGNING_KEY;
    if (!secret) throw new HttpError(503, 'signing_unavailable', 'Los enlaces temporales no están configurados.');
    const row = await new MediaRepository(c.env.DB).findActive(c.req.param('id'));
    if (!row || row.owner_id !== c.get('user').uid) throw notFound('Archivo no encontrado.');
    const { exp, sig } = await signMediaAccess(secret, row.id);
    return c.json({ data: { url: `/api/v1/media/${row.id}?exp=${exp}&sig=${sig}`, expiresAt: new Date(exp * 1000).toISOString() } });
  })
  .delete('/:id', async (c) => {
    const repo = new MediaRepository(c.env.DB);
    const row = await repo.markDeleted(c.req.param('id'), c.get('user').uid);
    // Mismo 404 si no existe o es de otra persona: no revela qué IDs existen.
    if (!row) throw notFound('Archivo no encontrado.');
    try {
      await c.env.MEDIA.delete(row.object_key);
      await repo.markPurged(row.id);
    } catch {
      // Queda pendiente: el barrido programado lo eliminará.
    }
    return c.body(null, 204);
  });

/**
 * GET /api/v1/media/:id — descarga. Permitido si el archivo es público, si
 * quien pide es el dueño (token) o con una URL firmada vigente.
 */
export const mediaDownloadRoutes = new Hono<AppBindings>().get('/:id', async (c) => {
  const id = c.req.param('id');
  if (!/^[0-9a-f-]{36}$/.test(id)) throw notFound('Archivo no encontrado.');
  const row = await new MediaRepository(c.env.DB).findActive(id);
  if (!row) throw notFound('Archivo no encontrado.');

  const isOwner = c.get('maybeUser')?.uid === row.owner_id;
  const signed = await verifyMediaAccess(c.env.MEDIA_SIGNING_KEY ?? '', row.id, c.req.query('exp'), c.req.query('sig'));
  if (row.visibility !== 'public' && !isOwner && !signed) throw notFound('Archivo no encontrado.');

  const object = await c.env.MEDIA.get(row.object_key);
  if (!object) throw notFound('Archivo no encontrado.');

  const headers = new Headers({
    'Content-Type': row.content_type,
    'Content-Length': String(row.size_bytes),
    'Content-Disposition': 'inline',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; sandbox",
    ETag: `"${row.sha256}"`,
    'Cache-Control': row.visibility === 'public' ? 'public, max-age=86400, immutable' : 'private, max-age=300',
  });
  return new Response(object.body, { status: 200, headers });
});
