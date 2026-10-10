-- Consentimiento (términos y edad mínima) y revocación de sesiones.
-- No se guarda la fecha de nacimiento: solo que la persona confirmó la edad mínima.
ALTER TABLE users ADD COLUMN consent_version TEXT;
ALTER TABLE users ADD COLUMN consent_at TEXT;
ALTER TABLE users ADD COLUMN age_confirmed INTEGER NOT NULL DEFAULT 0 CHECK (age_confirmed IN (0, 1));
-- Tokens con auth_time anterior a esta fecha se rechazan ("cerrar sesión en todos los dispositivos").
ALTER TABLE users ADD COLUMN tokens_valid_after TEXT;
