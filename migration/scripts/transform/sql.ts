/** Generación de SQL para D1 (SQLite). Todos los valores se escapan aquí. */

export type SqlValue = string | number | boolean | null | { raw: string };

export function lit(v: SqlValue | undefined): string {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'object') return v.raw;
  if (typeof v === 'boolean') return v ? '1' : '0';
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) return 'NULL';
    return String(v);
  }
  // Comillas simples duplicadas; se quitan NUL y sustitutos sueltos que SQLite no acepta bien.
  return `'${v.replace(/\u0000/g, '').replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, '').replace(/'/g, "''")}'`;
}

/** Referencia opcional a un archivo: NULL si el archivo no llegó a copiarse. */
export const mediaRef = (id: string | null): SqlValue => (id ? { raw: `(SELECT id FROM media_assets WHERE id = ${lit(id)})` } : null);

/**
 * INSERT idempotente: si la fila ya existe (misma clave primaria o
 * `legacy_id`), no hace nada. Las violaciones de CHECK o de claves
 * foráneas SÍ fallan: no se ocultan errores de datos.
 */
export function insert(table: string, row: Record<string, SqlValue | undefined>, onConflict = 'DO NOTHING'): string {
  const cols = Object.keys(row).filter((k) => row[k] !== undefined);
  return `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map((c) => lit(row[c])).join(', ')}) ON CONFLICT ${onConflict};`;
}

/** Límite práctico por sentencia en D1 (100 KB); se deja margen. */
export const MAX_STATEMENT_BYTES = 90_000;
