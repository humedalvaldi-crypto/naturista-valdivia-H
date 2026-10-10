/** Bindings y variables declarados en wrangler.toml. */
export interface Env {
  DB: D1Database;
  /** Bucket R2 (opcional). Sin él, los archivos se guardan en D1 (plan gratuito sin tarjeta). */
  MEDIA?: R2Bucket;
  APP_ENV: string;
  FIREBASE_PROJECT_ID: string;
  /** Lista separada por comas de orígenes permitidos para CORS. */
  ALLOWED_ORIGINS: string;
  /** Clave HMAC para URLs firmadas de archivos (`wrangler secret put MEDIA_SIGNING_KEY`). */
  MEDIA_SIGNING_KEY?: string;
  /** Límites de frecuencia (Cloudflare Rate Limiting). Opcionales en local. */
  RL_WRITE?: RateLimit;
  RL_UPLOAD?: RateLimit;
  RL_PUBLIC?: RateLimit;
  /** Versión vigente de términos; vacía = no se exige consentimiento (solo en pruebas). */
  CONSENT_VERSION?: string;
  /** Edad mínima que la persona debe confirmar. */
  MIN_AGE?: string;
}

/** Identidad verificada a partir de un Firebase ID token. */
export interface AuthUser {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  picture: string | null;
  signInProvider: string | null;
  /** Momento del inicio de sesión (segundos), se conserva al renovar el token. */
  authTime: number;
}

/** Estado de la cuenta en D1, leído una vez por petición autenticada. */
export interface AccountState {
  exists: boolean;
  status: string | null;
  consentVersion: string | null;
}

export interface AppVariables {
  requestId: string;
  user: AuthUser;
  /** Presente solo en rutas con autenticación opcional cuando hay token válido. */
  maybeUser?: AuthUser;
  account?: AccountState;
}

export type AppBindings = { Bindings: Env; Variables: AppVariables };
