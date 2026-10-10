/**
 * URLs firmadas de acceso temporal a un archivo (para <img> o reproductores
 * que no pueden enviar la cabecera Authorization).
 * Firma: HMAC-SHA256(clave, `${id}.${exp}`) en base64url.
 */

const enc = new TextEncoder();

function b64url(bytes: ArrayBuffer): string {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64url(await crypto.subtle.sign('HMAC', key, enc.encode(message)));
}

/** Comparación en tiempo constante. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export const SIGNED_URL_TTL_SECONDS = 60 * 60;

export async function signMediaAccess(secret: string, id: string, nowSec = Math.floor(Date.now() / 1000)) {
  const exp = nowSec + SIGNED_URL_TTL_SECONDS;
  return { exp, sig: await hmac(secret, `${id}.${exp}`) };
}

export async function verifyMediaAccess(
  secret: string,
  id: string,
  exp: string | undefined,
  sig: string | undefined,
  nowSec = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  if (!secret || !exp || !sig || !/^\d{1,12}$/.test(exp)) return false;
  if (Number(exp) < nowSec || Number(exp) > nowSec + SIGNED_URL_TTL_SECONDS + 60) return false;
  return safeEqual(await hmac(secret, `${id}.${exp}`), sig);
}
