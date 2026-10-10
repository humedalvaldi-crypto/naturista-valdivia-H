-- Mensajes al equipo desde Configuración → Contacto. Los lee quien administra
-- el proyecto (consulta directa a D1); no son públicos.
CREATE TABLE feedback (
  id          TEXT PRIMARY KEY,
  user_id     TEXT REFERENCES users (id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('bug', 'idea', 'question', 'other')),
  message     TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 2000),
  app_version TEXT CHECK (app_version IS NULL OR length(app_version) <= 40),
  platform    TEXT CHECK (platform IS NULL OR length(platform) <= 40),
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'read', 'closed')),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_feedback_status ON feedback (status, created_at);
