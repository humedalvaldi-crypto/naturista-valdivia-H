# Plan de migración Firestore → Cloudflare D1/R2

> Estado: **Fase 8 — herramientas listas y probadas con datos ficticios.** No se ha leído ningún dato real todavía y no se ha migrado nada.

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
| B. Exportación de solo lectura a instantánea local | `npm run export` | **Lista** |
| C. Mapeo Firestore → D1 e informe (sin conexión) | `npm run plan` — `scripts/transform/` | **Lista**; ajustar campos tras la auditoría real |
| D. Copia Storage → R2 (limpia GPS, verifica tamaño) | `npm run copy-media` | **Lista** (ensayo sin `--confirm`) |
| E. Aplicación a D1 con respaldo y puntos de control | `npm run apply` | **Lista** (probada en D1 local) |
| F. Validación: conteos, claves foráneas, ubicaciones protegidas, hashes | `npm run validate` | **Lista** |
| G. Ensayo en staging + informe | — | Pendiente: requiere credenciales y una base de staging |
| H. Migración definitiva | — | Solo con tu autorización |

Las URLs de archivos no se "reescriben": cada documento pasa a apuntar a una
fila de `media_assets` (ID determinista por ruta de Storage), y la app sirve
el archivo desde R2 con los permisos de la API.

Pendiente de la auditoría real: la lista "Campos sin mapear" del informe dirá
si algún dato importante de la app antigua quedó fuera del mapeo.

## 5. Cómo ejecutar las herramientas

Ver `migration/README.md` (pasos, garantías y credenciales). El resultado de la auditoría (`migration/output/audit-*.md|json`) no contiene valores de documentos, solo nombres de campos, tipos y conteos, y está ignorado por git.
