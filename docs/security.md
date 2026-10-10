# Seguridad

## Implementado en la Fase 1

| Control | Dónde | Probado |
|---|---|---|
| Verificación de Firebase ID token (firma RS256 con JWKS de Google, `iss`, `aud`, `exp`, `iat`, `auth_time`, `sub`) | `worker/src/services/firebase-auth.ts` | Sí: 9 casos (sin token, malformado, otra clave, kid desconocido, audiencia, emisor, expirado, `auth_time` futuro, válido) |
| La identidad sale solo del token, nunca del cuerpo/URL | `worker/src/routes/me.ts` | Sí: un usuario no modifica las preferencias de otro |
| Validación estricta de entrada (rechaza campos desconocidos) | `worker/src/validators/` | Sí |
| Límite de cuerpo JSON (64 KB) | `worker/src/app.ts` | Sí (413) |
| CORS con lista blanca, sin `*` | `worker/src/middleware/common.ts` | Sí |
| Errores uniformes sin trazas internas; registros sin tokens | `worker/src/middleware/` | Parcial |
| `X-Content-Type-Options`, `Referrer-Policy`, `Cache-Control: no-store` | `worker/src/middleware/common.ts` | Sí |
| Auditoría de migración sin escrituras | `migration/test/read-only-guard.test.ts` | Sí |
| Secretos fuera del repo (`.gitignore`, `.env.example`, `.dev.vars.example`) | raíz | Revisión manual |

## Implementado en la Fase 4

| Control | Dónde | Probado |
|---|---|---|
| Archivos: tipo comprobado por la firma del archivo (no solo por Content-Type), lista blanca por uso | `worker/src/services/media-types.ts` | Sí (HTML disfrazado de JPEG, PNG declarado como JPEG, audio como foto) |
| Límite de tamaño por uso, cortando la lectura al superarlo | `worker/src/routes/media.ts` | Sí (413) |
| Clave de objeto generada por el servidor (`u/{uid}/{uso}/{uuid}.{ext}`) | `routes/media.ts` | Sí |
| Archivos privados por defecto; solo el dueño, archivo público (fotos de perfil) o URL firmada HMAC de 1 h | `routes/media.ts`, `services/signed-url.ts` | Sí (otra persona y anónimo reciben 404; firma alterada y caducidad alterada fallan) |
| Borrado coordinado D1 + R2; barrido diario de borrados pendientes y huérfanos (> 24 h) | `services/maintenance.ts`, cron | Sí |
| Respuestas de archivos con `nosniff`, `Content-Security-Policy: sandbox` | `routes/media.ts` | Sí |
| Límites de frecuencia por usuario o IP (429 + `Retry-After`) | `middleware/rate-limit.ts`, `wrangler.toml` | Sí |
| Paginación por cursor con tope de 50 por página | `services/pagination.ts` | Sí |
| Perfil: nombre de usuario único, campos validados, imágenes solo propias y del tipo correcto | `routes/profiles.ts` | Sí |
| Perfiles privados ocultos (404) a terceros | `routes/profiles.ts` | Sí |
| Token inválido en ruta pública → 401 (no se ignora) | `middleware/auth.ts` | Sí |
| Despliegue solo manual, con aprobación y respaldo previo de D1 | `.github/workflows/deploy-api.yml` | — |

## Implementado en la Fase 5

| Control | Dónde | Probado |
|---|---|---|
| Regla de visibilidad única para publicaciones (perfil privado, solo seguidores, bloqueos) | `worker/src/repositories/social.ts` | Sí |
| Solo el autor borra su publicación; un comentario lo borra su autor o el de la publicación | `repositories/posts.ts` | Sí |
| No se comenta ni se da "me gusta" a lo que no se puede ver | `routes/posts.ts` | Sí |
| Bloquear deshace el seguimiento, oculta perfil y publicaciones, impide seguir y escribir | `repositories/social.ts`, `routes/messages.ts` | Sí |
| Conversaciones visibles solo para sus dos participantes (404 a terceros) | `repositories/messages.ts` | Sí |
| Publicar en una comunidad exige ser miembro; quien la creó no puede abandonarla | `routes/communities.ts` | Sí |
| Búsqueda de comunidades con comodines `%`/`_` escapados | `routes/communities.ts` | Sí |
| Notificaciones: nunca a uno mismo; marcar leídas solo afecta a las propias | `repositories/notifications.ts` | Sí |
| Denuncias idempotentes con motivos de una lista cerrada | `routes/notifications.ts` | Sí |

## Pendiente (con fase)

- Autorización por recurso y propietario en cada módulo, con pruebas cruzadas entre usuarios (Fases 5–7).
- Ubicaciones sensibles: ocultar o degradar coordenadas de especies amenazadas (Fase 7).
- Panel de moderación para revisar denuncias (las denuncias ya se guardan).

## Hallazgos en la app antigua (requieren acción)

1. **No hay reglas de seguridad en el código fuente.** El repositorio antiguo no contiene `firestore.rules` ni `storage.rules`, y `firebase.json` solo configura Hosting. No se puede saber desde el código si Firestore y Storage están protegidos. **Acción**: revisar en Firebase Console → Firestore → Reglas y Storage → Reglas que no estén en modo abierto (`allow read, write: if true`) mientras la app antigua siga activa.
2. **Datos personales sensibles en `profiles`**: RUT, fecha de nacimiento, edad, teléfono, WhatsApp, género y dirección en Valdivia. Si las reglas permiten leer `profiles` a cualquier usuario autenticado (la app antigua lee perfiles ajenos), estos datos podrían estar expuestos. **Propuesta**: en D1 separarlos en `profile_private`, legible solo por su dueño, y migrar únicamente lo que tenga un uso real. *Decisión pendiente tuya.*
3. **"Verificación en dos pasos" no real**: `SecurityScreen.tsx` genera códigos de respaldo con `Math.random()` en el navegador y solo guarda un indicador en `settings`. No protege la cuenta. No se migrará como si fuera una función de seguridad.
4. **UIDs ficticios**: hay escrituras con `userId: 'anon'` y `senderId: 'guest'`. La migración los contará y no los asociará a ningún usuario.
5. **La clave de Gemini** vivía en el servidor Express (`GEMINI_API_KEY`). En la nueva arquitectura será un secreto del Worker (`wrangler secret put`), nunca un valor en la app.

## Gestión de secretos

| Secreto | Dónde vive |
|---|---|
| Cuenta de servicio de Firebase (solo migración) | Fuera del repo; ruta en `GOOGLE_APPLICATION_CREDENTIALS`. Usar una cuenta con roles de **solo lectura** para la auditoría. |
| Claves de API de terceros (Gemini, geocodificación) | `wrangler secret put` |
| Configuración de Firebase cliente | `flutterfire configure` → archivos ignorados por git. No son secretos, pero son por entorno. |

No se afirma cumplimiento de ninguna normativa (p. ej. Ley 19.628 de Chile sobre datos personales) sin una revisión específica.
