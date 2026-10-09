# Naturista Valdivia

Plataforma de biodiversidad y naturaleza de Valdivia y sus humedales:
observaciones de flora, fauna y funga, cuadernos de campo digitales, mapa de
biodiversidad y comunidad naturalista. App para **Android y web**.

| Capa | Tecnología |
|---|---|
| App | Flutter (Android + web), español e inglés |
| Identidad | Firebase Authentication (se conservan los UID existentes) |
| API | Cloudflare Workers + TypeScript (Hono) |
| Datos | Cloudflare D1 |
| Archivos | Cloudflare R2 |
| Migración | Scripts Node de solo lectura sobre Firestore (Fase 1) |

## Estado

**Fase 1 completada: estructura, base de la app, API mínima, documentación y auditoría de migración.**
Qué funciona hoy y qué está planificado: ver la pantalla de inicio de la app o
`app/lib/core/router/app_modules.dart`, y `docs/`.

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Auditoría del entorno y estructura | ✅ |
| 2 | App Flutter: navegación, temas, idiomas | Base hecha en Fase 1 (navegación adaptable, tema claro/oscuro, es/en) |
| 3 | Firebase Auth + Google Sign-In | Pendiente |
| 4 | Worker, D1, R2, seguridad | API base hecha (`/health`, `/me`, verificación de tokens) |
| 5 | Perfiles, publicaciones, social | Pendiente |
| 6 | Cuadernos de campo y editor de dibujo | Pendiente |
| 7 | Mapa, observaciones, capas | Pendiente |
| 8 | Herramientas de migración y validación | Auditoría lista |
| 9 | Pruebas integrales, rendimiento, publicación | Pendiente |

## Puesta en marcha

### API (worker/)
```bash
cd worker
cp .dev.vars.example .dev.vars
npm install
npm run db:migrate:local
npm run dev              # http://localhost:8787/api/v1/health
npm test                 # pruebas en el runtime de Workers con D1 local
```

### App (app/)
Requiere Flutter estable (3.35 o superior).
```bash
cd app
# La primera vez, genera las carpetas de plataforma sin tocar lib/:
flutter create . --platforms=android,web --project-name naturista_valdivia --org cl.naturistavaldivia
rm -f test/widget_test.dart
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8787
flutter test
```

### Migración (migration/)
Ver `migration/README.md`. Solo lectura; requiere credenciales de Firebase de lectura.

## Documentación

- `docs/architecture.md` — arquitectura, decisiones, entornos y configuración manual.
- `docs/database.md` — esquema D1 y reglas de migraciones SQL.
- `docs/security.md` — controles implementados y **hallazgos de la app antigua**.
- `docs/backup-and-recovery.md` — respaldos antes de migrar y reversión.
- `docs/migration-plan.md` — plan de migración y **decisiones pendientes**.

## Seguridad

No subas credenciales. `.env`, `.dev.vars`, claves de cuentas de servicio y
archivos de configuración de Firebase por entorno están en `.gitignore`.
