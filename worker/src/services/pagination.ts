import { badRequest } from './http-error';

/** Paginación por cursor sobre (created_at, id), estable ante inserciones. */
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 50;

export interface Cursor {
  createdAt: string;
  id: string;
}

export function encodeCursor(c: Cursor): string {
  return btoa(JSON.stringify([c.createdAt, c.id])).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function decodeCursor(raw: string | undefined): Cursor | null {
  if (!raw) return null;
  try {
    const json = atob(raw.replace(/-/g, '+').replace(/_/g, '/'));
    const value: unknown = JSON.parse(json);
    if (Array.isArray(value) && value.length === 2 && typeof value[0] === 'string' && typeof value[1] === 'string' && value[0].length <= 40 && value[1].length <= 64) {
      return { createdAt: value[0], id: value[1] };
    }
  } catch {
    /* cae al error de abajo */
  }
  throw badRequest('Cursor de paginación inválido.');
}

export function parseLimit(raw: string | undefined): number {
  if (raw === undefined) return DEFAULT_PAGE_SIZE;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) throw badRequest('`limit` debe ser un entero positivo.');
  return Math.min(n, MAX_PAGE_SIZE);
}

/** Recibe `limit + 1` filas y devuelve la página y el cursor siguiente. */
export function paginate<T extends { created_at: string; id: string }>(rows: T[], limit: number) {
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  const nextCursor = rows.length > limit && last ? encodeCursor({ createdAt: last.created_at, id: last.id }) : null;
  return { items, nextCursor };
}
