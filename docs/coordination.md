# Coordinación del trabajo (Claude + GitHub Copilot)

Claude es el jefe técnico: define contratos, hace el servidor, la seguridad,
la migración y la sincronización, y **revisa e integra** los PR de Copilot
(lee el diff, ejecuta CI, prueba). Un informe de Copilot no basta como prueba.

## Reparto de archivos (para no editar lo mismo a la vez)

| Área | Responsable | Archivos |
|---|---|---|
| API, D1, seguridad (`worker/`) | Claude | todo `worker/` |
| Migración y sincronización Firebase → Cloudflare (`migration/`, workflows) | Claude | `migration/`, `.github/workflows/` |
| Configuración, idiomas, bloqueo biométrico, consentimiento | Claude | `app/lib/features/{settings,security}/`, `app/lib/core/` |
| Buscador de personas y sugerencias | Copilot (issue #1) | `app/lib/features/people/**` (nuevo `search_people_page.dart`, `people_search_api.dart`), una línea de ruta en `app/lib/core/router/app_router.dart` |
| Perfil de otra persona: «Te sigue» | Copilot (issue #2) | `app/lib/features/people/presentation/person_page.dart`, `app/lib/features/social/domain/models.dart` (solo el campo `followsMe`) |
| Editar y compartir publicaciones | Copilot (issue #3) | `app/lib/features/social/**` |
| Textos nuevos | quien crea la pantalla | las 12 traducciones `app/l10n/app_*.arb` excepto `app_arn.arb` |

Si dos tareas necesitan el mismo archivo, se asigna un responsable y el otro
espera o toma otra tarea.

## Contratos de la API (ya desplegados, con pruebas en `worker/test/`)

- `GET /api/v1/users?q=<texto>&limit=<1..50>&cursor=<opaco>` → `{ data: Person[], nextCursor: string|null }`
  `Person = { id, name, username, photo, followedByMe, followsMe }`. `q` de 2 a 60
  caracteres; sin límite total (paginar con `nextCursor`). Excluye perfiles
  privados y bloqueos. Con o sin sesión.
- `GET /api/v1/users/suggestions` (sesión) → `{ data: (Person & { mutuals })[] }`:
  personas que siguen quienes sigues. Lista vacía si no hay red (no se inventa).
- `GET /api/v1/users/:id` → incluye `followsMe` y `followedByMe`.
- `PUT|DELETE /api/v1/users/:id/follow` → seguir / dejar de seguir (idempotente).
- `PATCH /api/v1/posts/:id` (autor) `{ body?, visibility?: public|followers, locationName? }`
  → `{ data: Post }` con `editedAt`. 404 si no es tuya. Requiere términos aceptados (428).
- Enlace de una publicación: la app web usa rutas con `#`:
  `https://humedalvaldi-crypto.github.io/naturista-valdivia-H/#/posts/<id>`
  (ruta `/posts/:id` ya existe en la app).

## Registro

| Tarea | Responsable | Estado | Archivos | Pruebas | Pendiente |
|---|---|---|---|---|---|
| Contratos de búsqueda, sugerencias, «te sigue», editar | Claude | Hecho | `worker/src/routes/{people,posts}.ts`, `repositories/social.ts`, migración 0013 | `worker/test/people-search.test.ts` (4) | — |
| Idiomas (12 + mapudungun borrador) | Claude | Hecho | `app/l10n/`, `settings_sections.dart` | `l10n_test`, `settings_test` | revisión por hablantes |
| Buscador de personas (#1) | Claude (reasignado desde Copilot) | Hecho | `people/presentation/search_people_page.dart`, `social_api.dart`, `models.dart`, `app_router.dart` | `test/people_search_test.dart` (4) | — |
| «Te sigue» en perfil (#2) | Claude (reasignado) | Hecho | `person_page.dart`, `follow_confirm.dart` | `test/people_search_test.dart` (3) | — |
| Editar y compartir publicaciones (#3) | Claude (reasignado) | Hecho | `post_actions.dart`, `post_card.dart`, `post_detail_page.dart`, `social_page.dart` | `test/people_search_test.dart` (2) | — |
| Comunidad de cuadernos (Explorar, Mis cuadernos, Personas) | Claude | Hecho (código); datos antiguos pendientes de la copia | `worker/src/routes/notebooks.ts`, `repositories/notebooks.ts`, `people.ts`, migración 0014, `migration/scripts/transform/*`, `app/lib/features/notebooks/presentation/notebook_community_page.dart`, `notebook_card.dart`, `person_page.dart` | `worker/test/notebook-community.test.ts` (6), `migration/test/transform.test.ts` (+2), `app/test/notebook_community_test.dart` (11) | ejecutar la copia «migrar» (necesita autorización) |
| Publicación en Google Play | Claude + dueña de la cuenta | Preparado | `.github/workflows/android-release.yml`, `app/store/`, `app/branding_android/`, `docs/play-store.md` | CI comprueba ícono, nombre y parche de firma | cuenta Play, clave de subida, Firebase Android, prueba cerrada |
| Sincronización Firebase → Cloudflare + panel técnico | Claude | Pendiente | `migration/`, `worker/` | — | requiere autorización para escrituras recurrentes |
