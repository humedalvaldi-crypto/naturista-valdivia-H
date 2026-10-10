-- Fase 6: cuadernos de campo. Firestore: notebooks, notebook_pages.

CREATE TABLE notebooks (
  id             TEXT PRIMARY KEY,
  owner_id       TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  title          TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  description    TEXT CHECK (description IS NULL OR length(description) <= 500),
  -- Formato #RRGGBB validado en la API; aquí una comprobación simple (D1 limita la complejidad de GLOB).
  color          TEXT NOT NULL DEFAULT '#2E5B2A' CHECK (length(color) = 7 AND substr(color, 1, 1) = '#'),
  cover_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL,
  visibility     TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public')),
  page_count     INTEGER NOT NULL DEFAULT 0 CHECK (page_count >= 0),
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at     TEXT,
  legacy_id      TEXT UNIQUE
);
CREATE INDEX idx_notebooks_owner ON notebooks (owner_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE notebook_pages (
  id              TEXT PRIMARY KEY,
  notebook_id     TEXT NOT NULL REFERENCES notebooks (id) ON DELETE CASCADE,
  position        INTEGER NOT NULL CHECK (position >= 0),
  title           TEXT CHECK (title IS NULL OR length(title) <= 120),
  page_date       TEXT,                 -- fecha de la salida a terreno (YYYY-MM-DD)
  location_name   TEXT CHECK (location_name IS NULL OR length(location_name) <= 120),
  latitude        REAL CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  longitude       REAL CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  location_source TEXT CHECK (location_source IS NULL OR location_source IN ('gps', 'manual')),
  weather         TEXT CHECK (weather IS NULL OR length(weather) <= 80),
  paper           TEXT NOT NULL DEFAULT 'plain' CHECK (paper IN ('plain', 'lined', 'grid', 'dots')),
  -- Concurrencia optimista: cada guardado debe enviar la versión que leyó.
  version         INTEGER NOT NULL DEFAULT 1,
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  legacy_id       TEXT UNIQUE
);
CREATE INDEX idx_pages_notebook ON notebook_pages (notebook_id, position);

-- Elementos de una página (texto, foto, dibujo, pegatina, especie, coordenadas).
-- Posición y tamaño en unidades de página (lienzo de 1000 × 1414, proporción A4).
CREATE TABLE notebook_elements (
  id             TEXT NOT NULL,
  page_id        TEXT NOT NULL REFERENCES notebook_pages (id) ON DELETE CASCADE,
  type           TEXT NOT NULL CHECK (type IN ('text', 'photo', 'drawing', 'sticker', 'species', 'coordinates')),
  x              REAL NOT NULL,
  y              REAL NOT NULL,
  width          REAL NOT NULL CHECK (width > 0),
  height         REAL NOT NULL CHECK (height > 0),
  rotation       REAL NOT NULL DEFAULT 0,
  z              INTEGER NOT NULL DEFAULT 0,
  data_json      TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(data_json)),
  media_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL,
  PRIMARY KEY (page_id, id)
);
