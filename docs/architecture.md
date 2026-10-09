# Arquitectura

## Visión general

```
┌──────────────────────┐      Firebase ID token       ┌───────────────────────────┐
│  App Flutter          │ ───────────────────────────▶ │  Cloudflare Worker (API)   │
│  Android + Web        │   HTTPS /api/v1/*            │  Hono + TypeScript         │
│                       │ ◀─────────────────────────── │                            │
└─────────┬────────────┘        JSON                  │  ├─ D1  (datos relacionales)│
          │                                            │  └─ R2  (fotos, audio, PDF) │
          │ Google Sign-In                             └─────────────┬─────────────┘
          ▼                                                          │ verifica firma
┌──────────────────────┐                                             │ con JWKS de Google
│ Firebase Auth         │ ◀───────────────────────────────────────────┘
│ (proveedor identidad) │
└──────────────────────┘
          ▲
          │ solo lectura, desde la máquina del administrador
┌─────────┴────────────┐
│ migration/ (Node)     │  Firestore + Storage (sistema antiguo, intacto)
└──────────────────────┘
```

- **Identidad**: Firebase Authentication sigue siendo el proveedor. Los UID existentes se conservan y son la clave primaria de `users` en D1.
- **API**: un único Worker versionado bajo `/api/v1`. Toda autorización ocurre en el servidor; la app nunca envía un UID como prueba de identidad.
- **Datos**: Cloudflare D1 (SQLite) con migraciones SQL versionadas en `worker/migrations/`.
- **Archivos**: Cloudflare R2, bucket privado. Los metadatos de cada objeto viven en D1 (`media_assets`, Fase 4).
- **Migración**: herramientas separadas en `migration/`. Nunca se ejecutan automáticamente.

## Repositorio

| Carpeta | Contenido |
|---|---|
| `app/` | App Flutter. Arquitectura por funcionalidades: `features/<x>/{data,application,presentation}`. |
| `app/l10n/` | Textos en español (plantilla) e inglés (`.arb`). |
| `worker/` | API. `routes/` (HTTP) → `validators/` (zod) → `repositories/` (SQL parametrizado). `middleware/` para auth, CORS, errores. |
| `migration/` | Auditoría de solo lectura (Fase 1) y, en la Fase 8, migración idempotente por lotes. |
| `docs/` | Esta documentación. |

## Decisiones técnicas

| Decisión | Motivo |
|---|---|
| **Hono** como router del Worker | Ligero, tipado, pensado para Workers. |
| **jose** para verificar tokens | Verificación JWT estándar en Web Crypto; Firebase Admin SDK no funciona en Workers. Se valida firma RS256, `iss`, `aud`, `exp`, `iat`, `auth_time` y `sub`. |
| **zod** para validar entradas | Esquemas estrictos que rechazan campos desconocidos. |
| **go_router** + `StatefulShellRoute` | Navegación declarativa con pestañas que conservan su estado; preparada para `redirect` de autenticación (Fase 3). |
| **ChangeNotifier** para estado | Sin dependencias extra en Fase 1. Se reevaluará (Riverpod/Bloc) cuando haya datos remotos (Fase 3–5). |
| **MapLibre** (Fase 7) | Sustituye a Google Maps de la app antigua; evita depender de una clave de pago para el mapa base. El proveedor de teselas se documentará con sus condiciones de uso. |
| Pruebas del Worker en **workerd** (`@cloudflare/vitest-plugin`) | Las pruebas corren en el mismo runtime que producción, con D1 real (local) y las migraciones aplicadas. |

## Entornos

| Entorno | API | D1 | Uso |
|---|---|---|---|
| `development` | `wrangler dev` (local) | local (`.wrangler/`) | Desarrollo. |
| `staging` | Worker separado | base separada | Pruebas de migración. Se crea en la Fase 4. |
| `production` | Worker principal | base principal | Solo tras aprobación explícita. |

El script `npm run deploy` del Worker está **deshabilitado** a propósito en esta fase.

## Configuración manual necesaria (resumen)

1. **Cloudflare**: `wrangler login`, `wrangler d1 create naturista-valdivia-db` y `wrangler r2 bucket create naturista-valdivia-media`; copiar el `database_id` a `worker/wrangler.toml`.
2. **Firebase Console** (proyecto `humedalvaldivia-c7d08`): añadir la app Android (paquete y SHA-1/SHA-256 de la firma) y confirmar los dominios autorizados para la versión web.
3. **Flutter**: `flutterfire configure` en `app/` para generar `firebase_options.dart` (ignorado por git) — Fase 3.
4. **CORS**: definir `ALLOWED_ORIGINS` por entorno con los dominios reales.

## Módulos y fases

El estado real de cada módulo está en `app/lib/core/router/app_modules.dart` y se muestra en la pantalla de inicio. Un módulo marcado "En desarrollo · Fase N" no guarda ni muestra datos.

## Autenticación (Fase 3)

- **Proveedores** (habilitados en Firebase Console): Google y correo/contraseña. Se mantienen ambos para que las cuentas de la app antigua conserven su UID.
- **Web**: Google con ventana emergente (`signInWithPopup`). Dominio autorizado añadido: `humedalvaldi-crypto.github.io`.
- **Android**: Google con `signInWithProvider`. ⚠️ La app Android registrada en Firebase usa el paquete `App_val.nat`, distinto del de esta app (`cl.naturistavaldivia.naturista_valdivia`). Antes de publicar en Android hay que registrar el paquete nuevo en Firebase y añadir sus huellas SHA-1/SHA-256.
- **Verificación en dos pasos por SMS**: está habilitada en el proyecto. Esta versión aún no la admite; quien la tenga activada ve un mensaje claro en lugar de un error genérico.
- **Rutas protegidas**: `/profile`, `/notebooks`, `/drawing`, `/observations`, `/messages`, `/notifications`. El retorno tras el login solo acepta rutas internas (sin redirecciones abiertas).
- **API**: `ApiClient` adjunta el Firebase ID token y, ante un 401, pide uno nuevo y reintenta una sola vez. Mientras `API_BASE_URL` esté vacío (API sin desplegar), la app lo indica y no intenta conectarse.
- La configuración web de Firebase (`lib/core/config/firebase_config.dart`) no es secreta: Firebase la entrega para incluirla en la app.
