# Copias de seguridad y recuperación

## Antes de cualquier migración de datos (obligatorio)

1. **Exportar Firestore completo** a un bucket de Google Cloud que no use la app:
   ```bash
   gcloud firestore export gs://<bucket-de-respaldo>/firestore-$(date +%Y%m%d) --project humedalvaldivia-c7d08
   ```
2. **Copiar Firebase Storage**:
   ```bash
   gsutil -m rsync -r gs://humedalvaldivia-c7d08.firebasestorage.app gs://<bucket-de-respaldo>/storage-$(date +%Y%m%d)
   ```
3. **Exportar usuarios de Auth** (incluye hashes de contraseña si existen):
   ```bash
   firebase auth:export users-$(date +%Y%m%d).json --project humedalvaldivia-c7d08
   ```
   Este archivo es sensible: guardarlo cifrado y fuera del repositorio.
4. Anotar fecha, tamaño y conteos en `migration_runs` / informe de auditoría.

Firestore, Storage y Auth **no se borran ni se desactivan** durante ni después de la migración hasta una decisión explícita.

## Cloudflare D1

- **Time Travel**: D1 permite restaurar la base a cualquier minuto de los últimos 30 días (plan de pago; 7 días en el gratuito — verificar el plan vigente):
  ```bash
  npx wrangler d1 time-travel info naturista-valdivia-db
  npx wrangler d1 time-travel restore naturista-valdivia-db --timestamp=<ISO8601>
  ```
- **Exportación SQL** antes de cada migración de esquema en remoto:
  ```bash
  npx wrangler d1 export naturista-valdivia-db --remote --output=backup-$(date +%Y%m%d).sql
  ```

## Cloudflare R2

R2 no tiene restauración a un punto en el tiempo. Medidas previstas (Fase 4):
- Los objetos no se sobrescriben: cada subida genera una clave nueva.
- Borrado en dos pasos: marcar en `media_assets` y eliminar el objeto tras un periodo de gracia.
- Copia periódica a un segundo bucket o proveedor (por definir según volumen y coste).

## Plan de reversión de la migración

- La app antigua sigue funcionando sobre Firebase mientras la nueva se prueba en *staging*.
- Si la migración falla: se descarta la base D1 de destino (o se restaura con Time Travel) y se vuelve a ejecutar desde el último punto de control; Firestore no habrá cambiado.
- El cambio de la app antigua a la nueva se hace solo cuando el informe de validación (conteos, referencias y hashes) cuadra.
