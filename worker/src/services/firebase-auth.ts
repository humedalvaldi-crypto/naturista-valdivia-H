import { createRemoteJWKSet, errors, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from 'jose';
import type { AuthUser } from '../types/env';

/**
 * Claves públicas con las que Firebase Authentication firma los ID tokens.
 * Referencia: https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
 */
export const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let defaultResolver: JWTVerifyGetKey | undefined;

/** Resolver JWKS remoto, cacheado por instancia del Worker (jose respeta el caché HTTP). */
export function firebaseKeyResolver(): JWTVerifyGetKey {
  defaultResolver ??= createRemoteJWKSet(new URL(FIREBASE_JWKS_URL), {
    cooldownDuration: 30_000,
    cacheMaxAge: 6 * 60 * 60 * 1000,
  });
  return defaultResolver;
}

export class InvalidTokenError extends Error {
  constructor(readonly reason: string) {
    super(`Token inválido: ${reason}`);
    this.name = 'InvalidTokenError';
  }
}

export interface VerifyOptions {
  projectId: string;
  keyResolver: JWTVerifyGetKey;
  /** Segundos de tolerancia de reloj. */
  clockToleranceSec?: number;
  now?: () => number;
}

/**
 * Verifica un Firebase ID token: firma RS256 con las claves de Google,
 * `iss`, `aud`, `exp`, `iat`, `auth_time` y `sub`.
 * Nunca se confía en un UID enviado por el cliente fuera del token.
 */
export async function verifyFirebaseIdToken(token: string, opts: VerifyOptions): Promise<AuthUser> {
  if (!opts.projectId) throw new InvalidTokenError('project_not_configured');
  if (!token || token.split('.').length !== 3 || token.length > 4096) {
    throw new InvalidTokenError('malformed');
  }

  let payload: JWTPayload;
  try {
    const result = await jwtVerify(token, opts.keyResolver, {
      algorithms: ['RS256'],
      issuer: `https://securetoken.google.com/${opts.projectId}`,
      audience: opts.projectId,
      clockTolerance: opts.clockToleranceSec ?? 5,
      requiredClaims: ['exp', 'iat', 'sub', 'auth_time'],
      currentDate: opts.now ? new Date(opts.now()) : undefined,
    });
    payload = result.payload;
  } catch (err) {
    if (err instanceof errors.JWTExpired) throw new InvalidTokenError('expired');
    if (err instanceof errors.JWTClaimValidationFailed) throw new InvalidTokenError(`claim_${err.claim}`);
    if (err instanceof errors.JWSSignatureVerificationFailed) throw new InvalidTokenError('signature');
    if (err instanceof errors.JWKSNoMatchingKey) throw new InvalidTokenError('unknown_key');
    throw new InvalidTokenError('unverifiable');
  }

  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0 || sub.length > 128) {
    throw new InvalidTokenError('claim_sub');
  }
  const nowSec = Math.floor((opts.now?.() ?? Date.now()) / 1000);
  const authTime = payload['auth_time'];
  if (typeof authTime !== 'number' || authTime > nowSec + (opts.clockToleranceSec ?? 5)) {
    throw new InvalidTokenError('claim_auth_time');
  }

  const firebase = payload['firebase'] as { sign_in_provider?: unknown } | undefined;
  const str = (v: unknown) => (typeof v === 'string' && v.length > 0 ? v : null);

  return {
    uid: sub,
    email: str(payload['email']),
    emailVerified: payload['email_verified'] === true,
    name: str(payload['name']),
    picture: str(payload['picture']),
    signInProvider: str(firebase?.sign_in_provider),
  };
}
