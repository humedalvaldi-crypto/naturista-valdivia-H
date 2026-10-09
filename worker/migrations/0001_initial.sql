-- Naturista Valdivia — esquema inicial (Fase 1)
-- Solo identidad, preferencias, perfil público y trazabilidad de migración.
-- El resto de tablas (posts, notebooks, observations, ...) se añade en sus
-- fases con migraciones nuevas; nunca se edita una migración ya aplicada.

-- D1 aplica las claves foráneas por defecto.

-- Usuarios. `id` es SIEMPRE el UID de Firebase Authentication (no se genera aquí).
CREATE TABLE users (
  id             TEXT PRIMARY KEY CHECK (length(id) BETWEEN 1 AND 128),
  email          TEXT,
  email_verified INTEGER NOT NULL DEFAULT 0 CHECK (email_verified IN (0, 1)),
  display_name   TEXT,
  photo_url      TEXT,
  auth_provider  TEXT,
  status         TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_seen_at   TEXT,
  -- Trazabilidad: 'firestore' si el registro llegó por migración.
  legacy_source  TEXT,
  migrated_at    TEXT
);
CREATE INDEX idx_users_email ON users (email);

-- Preferencias del usuario (idioma, tema). Las secciones menos estructuradas
-- de `settings/{uid}` en Firestore se conservan en `extra_json`.
CREATE TABLE user_settings (
  user_id    TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  language   TEXT NOT NULL DEFAULT 'es' CHECK (language IN ('es', 'en')),
  theme      TEXT NOT NULL DEFAULT 'system' CHECK (theme IN ('system', 'light', 'dark')),
  extra_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extra_json)),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Perfil PÚBLICO. Los datos personales sensibles del sistema antiguo
-- (RUT, fecha de nacimiento, teléfono, WhatsApp, género, dirección) NO van
-- aquí: ver docs/security.md, sección "Datos personales heredados".
CREATE TABLE profiles (
  user_id      TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  username     TEXT UNIQUE COLLATE NOCASE CHECK (username IS NULL OR length(username) BETWEEN 3 AND 30),
  full_name    TEXT CHECK (full_name IS NULL OR length(full_name) <= 120),
  bio          TEXT CHECK (bio IS NULL OR length(bio) <= 500),
  location     TEXT CHECK (location IS NULL OR length(location) <= 120),
  photo_url    TEXT,
  banner_url   TEXT,
  visibility   TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'private')),
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Ejecuciones de migración Firestore → D1/R2.
CREATE TABLE migration_runs (
  id           TEXT PRIMARY KEY,
  mode         TEXT NOT NULL CHECK (mode IN ('audit', 'dry-run', 'staging', 'production')),
  status       TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed', 'aborted')),
  started_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  finished_at  TEXT,
  report_json  TEXT CHECK (report_json IS NULL OR json_valid(report_json))
);

-- Puntos de control por colección para reanudar una ejecución.
CREATE TABLE migration_checkpoints (
  run_id         TEXT NOT NULL REFERENCES migration_runs (id) ON DELETE CASCADE,
  collection     TEXT NOT NULL,
  last_doc_id    TEXT,
  processed      INTEGER NOT NULL DEFAULT 0,
  inserted       INTEGER NOT NULL DEFAULT 0,
  skipped        INTEGER NOT NULL DEFAULT 0,
  failed         INTEGER NOT NULL DEFAULT 0,
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (run_id, collection)
);
