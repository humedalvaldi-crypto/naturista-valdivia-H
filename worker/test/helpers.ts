import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWK } from 'jose';
import { env } from 'cloudflare:test';
import { createApp } from '../src/app';

export const PROJECT_ID = 'test-project';

/** Par de claves RSA que simula las de Firebase, con JWKS local (sin red). */
export async function makeSigner(kid = 'test-kid') {
  const { publicKey, privateKey } = await generateKeyPair('RS256', { extractable: true });
  const jwk: JWK = { ...(await exportJWK(publicKey)), kid, alg: 'RS256', use: 'sig' };
  const jwks = createLocalJWKSet({ keys: [jwk] });

  async function sign(claims: Record<string, unknown> = {}, opts: { kid?: string; expSec?: number; iatSec?: number } = {}) {
    const now = Math.floor(Date.now() / 1000);
    const iat = opts.iatSec ?? now - 10;
    const { sub = 'uid-alice', aud = PROJECT_ID, iss = `https://securetoken.google.com/${PROJECT_ID}`, ...rest } = claims;
    return new SignJWT({ auth_time: iat, firebase: { sign_in_provider: 'google.com' }, ...rest })
      .setProtectedHeader({ alg: 'RS256', kid: opts.kid ?? kid, typ: 'JWT' })
      .setSubject(sub as string)
      .setAudience(aud as string)
      .setIssuer(iss as string)
      .setIssuedAt(iat)
      .setExpirationTime(opts.expSec ?? now + 3600)
      .sign(privateKey);
  }
  return { jwks, sign };
}

export function makeApp(jwks: ReturnType<typeof createLocalJWKSet>, overrides: Record<string, unknown> = {}) {
  const app = createApp({ keyResolver: () => jwks });
  const bindings = { ...env, ...overrides };
  return (path: string, init: RequestInit = {}) => app.request(path, init, bindings);
}
