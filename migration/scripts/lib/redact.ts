/**
 * Censura de mensajes antes de imprimirlos. Los registros de GitHub Actions de
 * un repositorio público los puede leer cualquiera: un error de SQL o de
 * Storage podría incluir datos de una persona (textos, correos, rutas con UID).
 */
export function redact(message: string): string {
  return message
    .replace(/X'[0-9a-fA-F]*'/g, "X'…'") // bytes de archivos
    .replace(/'(?:[^']|'')*'/g, "'…'") // literales de SQL
    .replace(/"(?:[^"\\]|\\.){3,}"/g, '"…"') // cadenas JSON
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '<correo>')
    .replace(/user-files\/[^\s'"]+/g, 'user-files/<ruta>')
    .replace(/\b[A-Za-z0-9]{28}\b/g, '<uid>'); // UID de Firebase
}
