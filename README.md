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

**Fases 1, 3 a 7 completadas; Fase 8: herramientas de migración listas (falta el ensayo con datos reales, con tu autorización).** App publicada: https://humedalvaldi-crypto.github.io/naturista-valdivia-H/
Qué funciona hoy y qué está planificado: ver la pantalla de inicio de la app o
`app/lib/core/router/app_modules.dart`, y `docs/`.

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Auditoría del entorno y estructura | ✅ |
| 2 | App Flutter: navegación, temas, idiomas | Base hecha en Fase 1 (navegación adaptable, tema claro/oscuro, es/en) |
| 3 | Firebase Auth + Google Sign-In | ✅ Google y correo/contraseña, registro, verificación, recuperación, rutas protegidas |
| 4 | Worker, D1, R2, seguridad | ✅ Perfiles, archivos en R2, límites de frecuencia, despliegue manual (falta crear la cuenta de Cloudflare: `docs/deployment.md`) |
| 5 | Perfiles, publicaciones, social | ✅ API completa (publicaciones, comentarios, me gusta, seguir, bloquear, comunidades, mensajes, notificaciones, denuncias); en la app: feed, publicar, comentarios, comunidades, notificaciones, mensajes, perfil de otras personas y fotos en publicaciones |
| 6 | Cuadernos de campo y editor de dibujo | ✅ Cuadernos (crear, duplicar, privado/público, borrar), páginas (agregar, reordenar, duplicar, borrar), editor con lápiz/pincel/marcador/borrador y presión de lápiz óptico, texto, pegatinas, fotos, mover/rotar/escalar, deshacer/rehacer, guardado automático con control de conflictos. Exportar PNG/PDF pendiente |
| 7 | Mapa, observaciones, capas | ✅ Mapa real (OpenStreetMap / OpenTopoMap) con observaciones de la zona visible, filtros por grupo, capas (mías, lugares), mi ubicación; registrar con GPS o tocando el mapa, catálogo de especies, foto, privacidad; ubicación protegida para especies amenazadas y fotos sin GPS |
| 8 | Herramientas de migración y validación | ✅ Exportación de solo lectura, plan idempotente con informe, copia de archivos a R2 sin GPS, aplicación con respaldo y puntos de control, validación. Pendiente: ensayo en staging con datos reales |
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
- `docs/deployment.md` — cómo desplegar la API en Cloudflare y conectarla a la app.

## Seguridad

No subas credenciales. `.env`, `.dev.vars`, claves de cuentas de servicio y
archivos de configuración de Firebase por entorno están en `.gitignore`.
