-- Cuentas eliminadas por su dueña o dueño. Sirve para que una nueva copia
-- desde la app antigua (Firebase) NO vuelva a traer sus datos.
-- Solo se guarda el UID y la fecha: ningún otro dato personal.
CREATE TABLE deleted_accounts (
  uid        TEXT PRIMARY KEY,
  deleted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
