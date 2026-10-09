/** Bindings y variables declarados en wrangler.toml. */
export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;
  APP_ENV: string;
  FIREBASE_PROJECT_ID: string;
  /** Lista separada por comas de orígenes permitidos para CORS. */
  ALLOWED_ORIGINS: string;
}

/** Identidad verificada a partir de un Firebase ID token. */
export interface AuthUser {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  picture: string | null;
  signInProvider: string | null;
}

export interface AppVariables {
  requestId: string;
  user: AuthUser;
}

export type AppBindings = { Bindings: Env; Variables: AppVariables };
