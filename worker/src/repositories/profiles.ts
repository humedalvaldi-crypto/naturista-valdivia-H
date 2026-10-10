import type { UpdateProfileInput } from '../validators/profile';

export interface ProfileRow {
  user_id: string;
  username: string | null;
  full_name: string | null;
  bio: string | null;
  location: string | null;
  photo_url: string | null;
  banner_url: string | null;
  photo_asset_id: string | null;
  banner_asset_id: string | null;
  visibility: 'public' | 'followers' | 'private';
  created_at: string;
  updated_at: string;
}

export class UsernameTakenError extends Error {}

export class ProfilesRepository {
  constructor(private readonly db: D1Database) {}

  get(userId: string): Promise<ProfileRow | null> {
    return this.db.prepare(`SELECT * FROM profiles WHERE user_id = ?1`).bind(userId).first<ProfileRow>();
  }

  getByUsername(username: string): Promise<ProfileRow | null> {
    return this.db.prepare(`SELECT * FROM profiles WHERE username = ?1`).bind(username).first<ProfileRow>();
  }

  /**
   * Crea o actualiza el perfil. Solo toca los campos presentes en `input`
   * (un campo `null` lo borra). Los nombres de columna salen de una lista
   * fija, nunca del cliente.
   */
  async upsert(userId: string, input: UpdateProfileInput): Promise<ProfileRow> {
    const columns: Record<keyof UpdateProfileInput, string> = {
      username: 'username',
      fullName: 'full_name',
      bio: 'bio',
      location: 'location',
      visibility: 'visibility',
      photoAssetId: 'photo_asset_id',
      bannerAssetId: 'banner_asset_id',
    };
    const entries = (Object.keys(columns) as (keyof UpdateProfileInput)[])
      .filter((k) => input[k] !== undefined)
      .map((k) => [columns[k], input[k] ?? null] as const);

    const now = new Date().toISOString();
    const names = entries.map(([col]) => col);
    const values = entries.map(([, v]) => v);
    const insertCols = ['user_id', ...names, 'updated_at'];
    const placeholders = insertCols.map((_, i) => `?${i + 1}`);
    const updates = [...names.map((col, i) => `${col} = ?${i + 2}`), `updated_at = ?${names.length + 2}`];

    try {
      await this.db
        .prepare(
          `INSERT INTO profiles (${insertCols.join(', ')}) VALUES (${placeholders.join(', ')})
           ON CONFLICT (user_id) DO UPDATE SET ${updates.join(', ')}`,
        )
        .bind(userId, ...values, now)
        .run();
    } catch (err) {
      if (String((err as Error).message).includes('UNIQUE constraint failed: profiles.username')) {
        throw new UsernameTakenError();
      }
      throw err;
    }
    const row = await this.get(userId);
    if (!row) throw new Error('profile_upsert_failed');
    return row;
  }
}
