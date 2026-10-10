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

## Esquema previsto (fases 6–7)

| Tabla | Origen Firestore | Fase |
|---|---|---|
| `profile_private` | `profiles` (rut, fechaNacimiento, telefono, whatsapp, genero, addressValdivia) | 4 — **pendiente de decisión**, ver `security.md` |
| `notebooks`, `notebook_pages`, `notebook_elements` | `notebooks`, `notebook_pages` | 6 |
| `observations`, `species` | `observations`, `species_catalog`, `species_album`, `user_collections` | 7 |
| `map_layers`, puntos del mapa | `wetlands`, `places` | 7 |

El mapeo definitivo se fija con el informe real de la auditoría (`migration/`), no solo con el código antiguo.

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
