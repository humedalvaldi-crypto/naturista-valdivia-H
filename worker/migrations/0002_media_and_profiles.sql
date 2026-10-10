-- Fase 4: metadatos de archivos en R2.
-- Los bytes viven en R2; aquí solo se guarda lo necesario para permisos,
-- listados, borrado coordinado y trazabilidad de la migración.

CREATE TABLE media_assets (
  id                  TEXT PRIMARY KEY,                      -- UUID generado por el servidor
  owner_id            TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  purpose             TEXT NOT NULL CHECK (purpose IN (
                        'observation-photo', 'notebook-photo', 'notebook-audio', 'notebook-export',
                        'profile-photo', 'profile-banner', 'community-photo', 'post-photo', 'map-place-photo')),
  object_key          TEXT NOT NULL UNIQUE,                  -- clave en R2, nunca elegida por el cliente
  content_type        TEXT NOT NULL,
  size_bytes          INTEGER NOT NULL CHECK (size_bytes > 0),
  sha256              TEXT NOT NULL CHECK (length(sha256) = 64),
  visibility          TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public')),
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deleted')),
  created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at          TEXT,
  purged_at           TEXT,                                  -- objeto R2 eliminado
  -- Migración desde Firebase Storage (Fase 8).
  legacy_storage_path TEXT UNIQUE,
  legacy_asset_id     TEXT UNIQUE
);

CREATE INDEX idx_media_owner_created ON media_assets (owner_id, created_at DESC, id DESC) WHERE status = 'active';
CREATE INDEX idx_media_pending_purge ON media_assets (deleted_at) WHERE status = 'deleted' AND purged_at IS NULL;

-- Foto y portada del perfil apuntan a archivos propios.
ALTER TABLE profiles ADD COLUMN photo_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL;
ALTER TABLE profiles ADD COLUMN banner_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL;
