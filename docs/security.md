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

## Pendiente (con fase)

- Límites de frecuencia por usuario e IP (Fase 4, Cloudflare Rate Limiting binding).
- Subidas a R2: tipos MIME por lista blanca, comprobación de firma de archivo, límites de tamaño, nombres de objeto generados por el servidor, URLs de acceso temporal (Fase 4).
- Autorización por recurso y propietario en cada módulo, con pruebas cruzadas entre usuarios (Fases 5–7).
- Ubicaciones sensibles: ocultar o degradar coordenadas de especies amenazadas (Fase 7).
- Moderación y denuncias (Fase 5).

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
