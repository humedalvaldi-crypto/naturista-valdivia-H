# Base de datos (Cloudflare D1)

## Reglas

- Esquema versionado en `worker/migrations/NNNN_descripcion.sql`. **Una migración aplicada nunca se edita**; los cambios van en una migración nueva.
- Todas las consultas usan parámetros (`?1`, `?2`…). Nunca se concatena texto del usuario en SQL.
- Fechas en ISO 8601 UTC (`TEXT`), generadas por `strftime('%Y-%m-%dT%H:%M:%fZ','now')` o por el Worker.
- Identificadores: `users.id` es el UID de Firebase. Las tablas con origen en Firestore guardan el ID original en una columna `legacy_id` única (desde la Fase 5).
- Listados paginados por cursor (`created_at`, `id`) con límite máximo por petición.

## Estado actual — migración `0001_initial.sql`

| Tabla | Propósito |
|---|---|
| `users` | Cuenta. PK = UID de Firebase. Estado (`active/suspended/deleted`), trazabilidad `legacy_source`, `migrated_at`. |
| `user_settings` | Idioma (`es/en`), tema (`system/light/dark`) y `extra_json` para secciones heredadas. |
| `profiles` | Perfil **público** (usuario, nombre, bio, ubicación, fotos, visibilidad). |
| `migration_runs` | Cada ejecución de auditoría/migración y su informe. |
| `migration_checkpoints` | Último documento procesado por colección, para reanudar. |

Pruebas: `worker/test/api.test.ts` aplica esta migración sobre un D1 local y verifica creación idempotente de usuarios y aislamiento de preferencias entre usuarios.

## Migración `0002_media_and_profiles.sql` (Fase 4)

| Tabla / columna | Propósito |
|---|---|
| `media_assets` | Metadatos de cada archivo en R2: dueño, uso, clave del objeto (única), tipo real, tamaño, SHA-256, visibilidad, estado de borrado y de purga, y trazabilidad de Firebase Storage (`legacy_storage_path`, `legacy_asset_id`). |
| `profiles.photo_asset_id`, `profiles.banner_asset_id` | Foto y portada del perfil apuntan a archivos propios (`ON DELETE SET NULL`). |

## Migración `0003_social.sql` (Fase 5)

| Tabla | Propósito | Origen Firestore |
|---|---|---|
| `follows` | Quién sigue a quién (PK compuesta, sin seguirse a sí mismo) | `follows` |
| `blocks` | Bloqueos entre personas | — |
| `posts` | Publicaciones (texto ≤ 2000, imagen opcional, comunidad opcional, visibilidad, contadores, borrado lógico) | `posts` |
| `comments` | Comentarios (≤ 1000, borrado lógico) | — |
| `reactions` | "Me gusta" (uno por persona y publicación) | `notebook_likes` (parcial) |
| `bookmarks` | Publicaciones guardadas | — |
| `communities`, `community_members` | Comunidades y sus miembros con rol | `groups`, `group_members` |
| `conversations`, `messages` | Mensajes privados 1 a 1 (par único) | `chat_messages` (`chatId`) |
| `notifications` | Avisos guardados en el servidor | `notifications`, `users/{uid}/notifications` |
| `reports` | Denuncias (una por persona y objetivo) | `reports` |

Todas las tablas que vienen de Firestore tienen `legacy_id` único para migrar sin duplicar.

## Migración `0004_notebooks.sql` (Fase 6)

| Tabla | Propósito | Origen Firestore |
|---|---|---|
| `notebooks` | Cuaderno: dueño, título (1–120), descripción (≤ 500), color `#RRGGBB`, portada opcional, visibilidad `private`/`public` (privado por defecto), contador de páginas, borrado lógico | `notebooks` |
| `notebook_pages` | Página: posición, título, fecha de salida, lugar y coordenadas (con origen `gps`/`manual`), clima, papel (`plain`, `lined`, `grid`, `dots`) y `version` para concurrencia optimista | `notebook_pages` |
| `notebook_elements` | Elementos de la página (`text`, `photo`, `drawing`, `sticker`, `species`, `coordinates`) con posición, tamaño, rotación, orden `z`, `data_json` validado y foto opcional en `media_assets` | campos internos de `notebook_pages` |

- Lienzo lógico de 1000 × 1414 unidades (proporción A4): la página se ve igual en cualquier pantalla.
- Un dibujo es un elemento `drawing` con sus trazos (`tool`, `color`, `width`, `opacity`, `points` como lista plana `x,y,…` y presión opcional `p`).
- Guardar una página reemplaza todos sus elementos en un solo lote atómico, solo si la `version` enviada es la actual; si no, responde 409 sin tocar nada.
- Límites: 200 elementos por página, 400 000 caracteres por elemento, 2 MB por guardado.

## Migración `0005_observations.sql` (Fase 7)

| Tabla | Propósito | Origen Firestore |
|---|---|---|
| `species` | Catálogo: nombre científico (único), nombres comunes es/en, grupo, estado UICN, origen, `sensitive`, ilustración | `species_catalog` |
| `observations` | Observación: especie del catálogo o nombre libre, cantidad, fecha, ubicación **exacta** (`latitude`, `longitude`, precisión, origen GPS/manual, lugar) y **pública** (`public_latitude`, `public_longitude`), `obscured`, `geoprivacy`, notas, foto, visibilidad, borrado lógico | `observations` |
| `places` | Humedales, senderos y miradores con contorno GeoJSON opcional | `places`, `wetlands` |

- La ubicación pública se calcula al guardar: igual a la exacta, o el centro de una celda de 0,1° si la especie es sensible o quien observa lo pide. Si cambia la sensibilidad de una especie, hay que recalcular sus observaciones (pendiente: script de mantenimiento).
- El catálogo inicial trae 17 especies de los humedales de Valdivia con su estado UICN **global**; el equipo debe validarlo con la clasificación nacional (RCE) y ampliarlo al migrar `species_catalog`.
- `places` empieza vacía: se llena solo con datos reales en la migración.

## Políticas de borrado

- Borrar un usuario: `ON DELETE CASCADE` en sus preferencias y perfil. El contenido social se decidirá en la Fase 5 (anonimizar vs. borrar) y quedará documentado aquí.
- Los archivos en R2 se eliminan de forma coordinada con su fila en `media_assets` (Fase 4), con barrido periódico de huérfanos.

## Comandos

```bash
cd worker
npm run db:migrate:local            # aplica migraciones al D1 local
npx wrangler d1 migrations list naturista-valdivia-db --local
```

Antes de aplicar migraciones a una base remota: ver `backup-and-recovery.md`.
