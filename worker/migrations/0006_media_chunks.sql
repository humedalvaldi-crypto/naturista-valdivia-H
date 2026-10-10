-- Almacenamiento de archivos en D1 cuando no hay R2 (plan gratuito sin tarjeta).
-- Cada archivo se guarda en trozos (D1 limita el tamaño de cada valor a ~2 MB).
-- Si más adelante se activa R2, los archivos nuevos van a R2 y estos siguen
-- sirviéndose desde aquí.
CREATE TABLE media_chunks (
  object_key TEXT NOT NULL,
  part       INTEGER NOT NULL CHECK (part >= 0),
  bytes      BLOB NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (object_key, part)
);
