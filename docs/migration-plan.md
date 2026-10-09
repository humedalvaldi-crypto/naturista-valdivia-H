# Plan de migración Firestore → Cloudflare D1/R2

> Estado: **Fase 1 — solo auditoría preparada.** No se ha leído ningún dato real todavía y no se ha migrado nada.

## 1. Principios

- La migración es un proyecto separado, en `migration/`, y nunca se ejecuta automáticamente.
- Firestore, Firebase Storage y Firebase Auth no se borran, sobrescriben ni desactivan.
- Los UID de Firebase se conservan como `users.id`. Los ID de documentos se conservan en `legacy_id`.
- Sin escrituras dobles Firebase↔Cloudflare hasta diseñar y probar un mecanismo consistente.
- Primero un ensayo en *staging*; la migración definitiva requiere tu autorización explícita.

## 2. Decisiones que necesito de ti

| # | Decisión | Por qué importa |
|---|---|---|
| D1 | **¿Se mantiene el inicio de sesión con correo y contraseña?** La app antigua tenía registro con email (`Register.tsx`). | Si hay usuarios con contraseña y la nueva app solo ofrece Google, esos usuarios perderán el acceso a su cuenta y su contenido. La auditoría cuenta usuarios por proveedor para decidir con datos. |
| D2 | **¿Qué datos personales se migran?** (RUT, fecha de nacimiento, teléfono, WhatsApp, género, dirección) | Minimizar datos reduce riesgo. Ver `security.md`. |
| D3 | **¿Qué hacer con contenido de `anon`/`guest`?** | No tiene dueño verificable. Opciones: no migrarlo, o migrarlo como contenido sin autor. |
| D4 | **Licencia de las ilustraciones** de `Base de Datos` (aves, flora, funga, fotos históricas, stickers). | Las fotos históricas de Valdivia pueden tener derechos de terceros; hay que registrar su fuente antes de publicarlas. |

## 3. Inventario (desde el código antiguo)

Colecciones raíz usadas por la app React: `profiles`, `settings`, `posts`, `observations`, `notebooks`, `notebook_pages`, `notebook_likes`, `follows`, `groups`, `group_members`, `chat_messages`, `notifications`, `places`, `wetlands`, `species_catalog`, `species_album`, `user_collections`, `user_file_assets`, `profile_views`, `reports`. Subcolección: `users/{uid}/notifications`.

Detalle (campos con UID, IDs compuestos, tabla destino): `migration/scripts/lib/legacy-inventory.ts`.

Archivos: Firebase Storage bajo `user-files/{uid}/{propósito}/{archivo}`, con metadatos en `user_file_assets` y URLs de descarga copiadas en los documentos (`imageUrl`, `photoURL`, `bannerURL`, `audioNoteUrl`, `coverImageUrl`).

## 4. Etapas

| Etapa | Herramienta | Estado |
|---|---|---|
| A. Auditoría de solo lectura | `npm run audit -- --project humedalvaldivia-c7d08` | **Lista para ejecutar** (requiere credenciales de lectura) |
| B. Mapa de correspondencias Firestore → D1/R2 | `migration/schemas/` | Fase 8, con el informe de A |
| C. Migrador idempotente por lotes con puntos de control | `migration/scripts/` | Fase 8 |
| D. Copia de archivos Storage → R2, reescritura de URLs | `migration/scripts/` | Fase 8 |
| E. Validación: conteos, referencias, hashes | `migration/validation/` | Fase 8 |
| F. Ensayo en staging + informe | — | Fase 8 |
| G. Migración definitiva | — | Solo con tu autorización |

## 5. Cómo ejecutar la auditoría (etapa A)

Ver `migration/README.md`. El resultado (`migration/output/audit-*.md|json`) no contiene valores de documentos, solo nombres de campos, tipos y conteos, y está ignorado por git.
