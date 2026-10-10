# Migración Firestore → Cloudflare

Herramientas para auditar y, más adelante, migrar los datos de la app antigua
(proyecto Firebase `humedalvaldivia-c7d08`). Plan completo: `../docs/migration-plan.md`.

**Estado (Fase 8): herramientas listas y probadas con datos ficticios.** No se ha leído
ni migrado ningún dato real. La migración real requiere tu autorización explícita.

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
un conteo por colección. Con ~20 colecciones y muestra 500 son unas 10 000## Migrar (fase 8)

Cinco pasos. Los tres primeros no escriben en ningún servicio; los dos de
escritura exigen una opción de confirmación explícita.

| Paso | Comando | Lee | Escribe |
|---|---|---|---|
| 1. Exportar | `npm run export -- --project humedalvaldivia-c7d08` | Firebase (solo lectura) | `output/snapshot-<fecha>/` |
| 2. Planificar | `npm run plan -- --snapshot output/snapshot-<fecha>` | la instantánea | `output/plan/` (SQL, manifiesto, informe) |
| 3. Archivos (ensayo) | `npm run copy-media -- --plan output/plan --project humedalvaldivia-c7d08` | Firebase Storage (solo lectura) | nada |
| 3b. Archivos (real) | igual + `--r2-bucket <bucket> --confirm` y credenciales R2 | Firebase Storage | R2 + `output/plan/sql/035-*.sql` |
| 4. Aplicar | `npm run apply -- --plan output/plan` (D1 local) | plan | D1 **local** |
| 4b. Aplicar remoto | `npm run apply -- --plan output/plan --remote --mode staging --confirm <base>` | plan | respaldo + D1 remota |
| 5. Validar | `npm run validate -- --plan output/plan [--remote]` | D1 | `output/plan/validation-*.md` |

Garantías:

- **Firebase nunca se modifica.** Una prueba automática verifica que los
  scripts que leen Firebase no contienen operaciones de escritura.
- **Idempotente.** Cada fila tiene un ID determinista derivado del ID antiguo
  y el SQL usa `ON CONFLICT DO NOTHING`: repetir o reanudar no duplica.
  Los errores de datos (CHECK, claves foráneas) sí detienen la ejecución.
- **Reanudable.** `apply` guarda qué archivos aplicó (`applied-*.json` y la
  tabla `migration_checkpoints`); `copy-media` guarda lo copiado en
  `media-done.jsonl`.
- **Orden indiferente entre contenido y archivos.** Si el contenido se aplica
  antes de copiar las fotos, la etapa `910-relink-media` las enlaza al repetir.
- **Respaldo previo.** `apply --remote` hace `wrangler d1 export` antes de escribir.
- **Mismas reglas que la app.** Los archivos pasan por la misma validación de
  tipo y tamaño que una subida nueva y pierden el GPS de sus metadatos; las
  observaciones de especies sensibles quedan con la ubicación protegida.

### Qué se migra y qué no

Lo decide el informe `output/plan/report.md`, que hay que revisar antes del
paso 3. Por defecto:

- **Datos personales** (RUT, fecha de nacimiento, teléfono, WhatsApp, género,
  dirección): **no se migran** (decisión D2 pendiente). El informe cuenta
  cuántos hay.
- **Contenido de `anon`/`guest`** o de UID que no existen en Auth: **no se
  migra** (decisión D3 pendiente).
- No se migran: avisos antiguos, "me gusta" de cuadernos, álbum y colecciones
  de especies, visitas a perfiles, mensajes de contacto (`reports`), notas de
  audio y pegatinas antiguas de las páginas. Todo queda contado en el informe.
- **Campos sin mapear**: el informe lista los campos que ningún mapeo leyó.
  Los nombres de campos se tomaron del código antiguo y de variantes
  probables; tras la auditoría real hay que revisar esa lista y ajustar
  `scripts/transform/mappers.ts` si algo importante quedó fuera.

### Credenciales

- Firebase: cuenta de servicio de **solo lectura** (ver arriba).
- R2 (solo paso 3b): un token de API de R2 con permiso de escritura **solo**
  sobre el bucket de archivos, en variables de entorno `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. Nunca en archivos del repositorio.
- D1 remota (paso 4b): `wrangler login` o `CLOUDFLARE_API_TOKEN`.

### Ensayo recomendado (etapa F)

1. Crear una base D1 y un bucket R2 de **staging** (`docs/deployment.md`, con otros nombres).
2. Pasos 1 → 5 contra staging. Revisar `report.md` y `validation-remote.md`.
3. Abrir la app apuntando a la API de staging y revisar cuentas reales de prueba.
4. Solo entonces, con tu autorización, repetir 3b → 5 en producción.

La instantánea y el plan contienen datos personales: guárdalos cifrados,
no los compartas y bórralos al terminar (`output/` está ignorado por git).


lecturas (dentro de la cuota gratuita diaria de 50 000 de Firestore).

## Pruebas

```bash
npm test         # inferencia de esquema, referencias, guardia de solo lectura,
                 # transformación completa aplicada sobre SQLite con el esquema real,
                 # idempotencia, archivos y validación
npm run typecheck
```

## Carpetas

- `scripts/` — auditoría, exportación, plan, copia de archivos, aplicación y validación.
- `scripts/transform/` — mapeo Firestore → D1 (sin conexión a nada; probado).
- `schemas/`, `validation/` — notas; la lógica vive en `scripts/transform/`.
