-- Notas de audio en las páginas: se añade 'audio' a los tipos de elemento.
-- SQLite no permite cambiar un CHECK: se reconstruye la tabla conservando los datos.
PRAGMA defer_foreign_keys = true;

CREATE TABLE notebook_elements_new (
  id             TEXT NOT NULL,
  page_id        TEXT NOT NULL REFERENCES notebook_pages (id) ON DELETE CASCADE,
  type           TEXT NOT NULL CHECK (type IN ('text', 'photo', 'drawing', 'sticker', 'species', 'coordinates', 'audio')),
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
INSERT INTO notebook_elements_new (id, page_id, type, x, y, width, height, rotation, z, data_json, media_asset_id)
  SELECT id, page_id, type, x, y, width, height, rotation, z, data_json, media_asset_id FROM notebook_elements;
DROP TABLE notebook_elements;
ALTER TABLE notebook_elements_new RENAME TO notebook_elements;
