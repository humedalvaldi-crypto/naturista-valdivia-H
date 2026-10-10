import type { AuthUser } from '../types/env';
import type { UpdateSettingsInput } from '../validators/settings';

export interface UserRow {
  id: string;
  email: string | null;
  email_verified: number;
  display_name: string | null;
  photo_url: string | null;
  auth_provider: string | null;
  status: string;
  created_at: string;
  updated_at: string;
  last_seen_at: string | null;
  consent_version?: string | null;
  consent_at?: string | null;
}

export interface SettingsRow {
  user_id: string;
  language: 'es' | 'en';
  theme: 'system' | 'light' | 'dark';
  extra_json?: string;
  updated_at: string;
}

/** Acceso a datos de usuarios. Todas las consultas son parametrizadas. */
export class UsersRepository {
  constructor(private readonly db: D1Database) {}

  /**
   * Crea el usuario si no existe (con el UID de Firebase como clave) o
   * actualiza los datos que provienen del token. Idempotente.
   * No sobrescribe display_name/photo_url con valores vacíos.
   */
  async upsertFromAuth(user: AuthUser): Promise<UserRow> {
    const now = new Date().toISOString();
    await this.db.batch([
      this.db
        .prepare(
          `INSERT INTO users (id, email, email_verified, display_name, photo_url, auth_provider, last_seen_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           ON CONFLICT (id) DO UPDATE SET
             email          = excluded.email,
             email_verified = excluded.email_verified,
             display_name   = COALESCE(excluded.display_name, users.display_name),
             photo_url      = COALESCE(excluded.photo_url, users.photo_url),
             auth_provider  = COALESCE(excluded.auth_provider, users.auth_provider),
             last_seen_at   = excluded.last_seen_at,
             updated_at     = ?7`,
        )
        .bind(user.uid, user.email, user.emailVerified ? 1 : 0, user.name, user.picture, user.signInProvider, now),
      this.db.prepare(`INSERT INTO user_settings (user_id) VALUES (?1) ON CONFLICT (user_id) DO NOTHING`).bind(user.uid),
    ]);
    const row = await this.findById(user.uid);
    if (!row) throw new Error('upsert_failed');
    return row;
  }

  findById(id: string): Promise<UserRow | null> {
    return this.db.prepare(`SELECT * FROM users WHERE id = ?1`).bind(id).first<UserRow>();
  }

  getSettings(userId: string): Promise<SettingsRow | null> {
    return this.db
      .prepare(`SELECT user_id, language, theme, extra_json, updated_at FROM user_settings WHERE user_id = ?1`)
      .bind(userId)
      .first<SettingsRow>();
  }

  async updateSettings(userId: string, input: UpdateSettingsInput): Promise<SettingsRow> {
    const now = new Date().toISOString();
    await this.db
      .prepare(
        `INSERT INTO user_settings (user_id, language, theme, extra_json, updated_at)
         VALUES (?1, COALESCE(?2, 'es'), COALESCE(?3, 'system'), json_patch('{}', ?5), ?4)
         ON CONFLICT (user_id) DO UPDATE SET
           language   = COALESCE(?2, user_settings.language),
           theme      = COALESCE(?3, user_settings.theme),
           extra_json = json_patch(user_settings.extra_json, ?5),
           updated_at = ?4`,
      )
      .bind(
        userId,
        input.language ?? null,
        input.theme ?? null,
        now,
        JSON.stringify({
          ...(input.notifications ? { notifications: input.notifications } : {}),
          ...(input.privacy ? { privacy: input.privacy } : {}),
        }),
      )
      .run();
    const row = await this.getSettings(userId);
    if (!row) throw new Error('settings_update_failed');
    return row;
  }
}
