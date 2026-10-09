import type { ContentfulStatusCode } from 'hono/utils/http-status';

/** Error con código estable para el cliente. El mensaje nunca incluye tokens. */
export class HttpError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}

export const unauthorized = (message = 'Autenticación requerida.') =>
  new HttpError(401, 'unauthorized', message);
export const notFound = (message = 'Recurso no encontrado.') => new HttpError(404, 'not_found', message);
export const badRequest = (message: string, details?: unknown) =>
  new HttpError(400, 'invalid_request', message, details);
