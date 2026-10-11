-- Edición de publicaciones propias (se muestra "editado").
ALTER TABLE posts ADD COLUMN edited_at TEXT;
-- Búsqueda de personas por nombre de usuario y nombre visible.
CREATE INDEX IF NOT EXISTS idx_profiles_username_lower ON profiles (lower(username));
CREATE INDEX IF NOT EXISTS idx_profiles_full_name_lower ON profiles (lower(full_name));
