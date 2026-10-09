# Migración Firestore → Cloudflare

Herramientas para auditar y, más adelante, migrar los datos de la app antigua
(proyecto Firebase `humedalvaldivia-c7d08`). Plan completo: `../docs/migration-plan.md`.

**Estado (Fase 1): solo auditoría de lectura.** No existe todavía ningún script que escriba datos.

## Requisitos

- Node.js 20+.
- Una cuenta de servicio de Google Cloud con **roles de solo lectura**:
  `Cloud Datastore Viewer`, `Firebase Authentication Viewer` y `Storage Object Viewer`.
  Descarga su clave JSON y guárdala **fuera** del repositorio.

## Ejecutar la auditoría

```bash
cd migration
npm install
export GOOGLE_APPLICATION_CREDENTIALS=/ruta/fuera/del/repo/service-account.json
npm run audit -- --project humedalvaldivia-c7d08            # muestra de 500 docs por colección
npm run audit -- --project humedalvaldivia-c7d08 --sample 2000
```

Genera en `migration/output/` (ignorado por git):
- `audit-<fecha>.md` — resumen legible.
- `audit-<fecha>.json` — datos completos para construir el mapeo.

El informe incluye: usuarios por proveedor de acceso, documentos por colección,
campos y tipos (sin valores), campos opcionales o con tipos mezclados, URLs de
Storage e imágenes Base64 incrustadas, referencias a usuarios inexistentes,
y tamaño de los archivos en Storage.

Lecturas facturables: aproximadamente `colecciones × muestra` documentos más
un conteo por colección. Con ~20 colecciones y muestra 500 son unas 10 000
lecturas (dentro de la cuota gratuita diaria de 50 000 de Firestore).

## Pruebas

```bash
npm test         # inferencia de esquema, verificación de referencias, guardia de solo lectura
npm run typecheck
```

## Carpetas

- `scripts/` — auditoría (y migradores en la Fase 8).
- `schemas/` — mapeo Firestore → D1/R2 (Fase 8, a partir del informe real).
- `validation/` — comprobaciones de conteo, referencias y hashes (Fase 8).
