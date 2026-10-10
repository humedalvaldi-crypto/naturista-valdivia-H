import type { z } from 'zod';
import { badRequest } from './http-error';

const mediaPath = (id: string | null) => (id ? `/api/v1/media/${id}` : null);

/** Datos públicos mínimos de una persona dentro de otras respuestas. */
export function personDto(p: {
  id: string;
  username: string | null;
  full_name: string | null;
  display_name: string | null;
  photo_asset_id: string | null;
}) {
  return {
    id: p.id,
    username: p.username,
    name: p.full_name ?? p.display_name ?? p.username ?? 'Naturalista',
    photo: mediaPath(p.photo_asset_id),
  };
}

export { mediaPath };

/** Lee y valida un cuerpo JSON con un esquema zod; 400 con detalle si falla. */
export async function parseBody<S extends z.ZodType>(c: { req: { json: () => Promise<unknown> } }, schema: S): Promise<z.infer<S>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw badRequest('El cuerpo debe ser JSON válido.');
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw badRequest(
      'Datos inválidos.',
      parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
    );
  }
  return parsed.data;
}
