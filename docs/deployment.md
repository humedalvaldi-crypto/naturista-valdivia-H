# Despliegue de la API (Cloudflare)

La API se despliega **solo a mano**, con el workflow **"Desplegar API (Cloudflare)"** de GitHub Actions. Antes de migrar la base de datos exporta un respaldo y lo guarda 30 días como artefacto del workflow.

## Una sola vez: preparar Cloudflare

1. Crea una cuenta en https://dash.cloudflare.com (el plan gratuito sirve para empezar).
2. **Base de datos D1**: *Storage & Databases → D1 → Create* con el nombre `naturista-valdivia-db`. Copia su **Database ID**.
3. **Bucket R2**: *R2 → Create bucket* con el nombre `naturista-valdivia-media`. Déjalo **privado** (sin acceso público): la API controla quién ve cada archivo.
4. **Token de API**: *My Profile → API Tokens → Create Token → "Edit Cloudflare Workers"*, y añade permisos de edición de **D1** y **R2**. Copia el token (solo se muestra una vez).
5. Copia tu **Account ID** (aparece en la barra lateral de *Workers & Pages*).

## Una sola vez: preparar GitHub

En el repositorio → *Settings*:

1. *Secrets and variables → Actions → New repository secret*:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
   - `D1_DATABASE_ID`
2. *Environments → New environment* `production` → activa **Required reviewers** y elígete. Así ningún despliegue corre sin tu aprobación.
3. Clave para enlaces temporales de archivos (una vez desplegado el Worker):
   `npx wrangler secret put MEDIA_SIGNING_KEY` (pega una cadena aleatoria larga), o desde el panel del Worker → *Settings → Variables and Secrets*.

## Desplegar

*Actions → Desplegar API (Cloudflare) → Run workflow*. El workflow:

1. Verifica que los secretos existan.
2. Ejecuta la comprobación de tipos y las pruebas.
3. Exporta un respaldo de D1 (si se aplican migraciones).
4. Aplica las migraciones pendientes.
5. Despliega el Worker con `APP_ENV=production`.

Al terminar, Cloudflare muestra la URL del Worker (p. ej. `https://naturista-valdivia-api.<tu-subdominio>.workers.dev`). Compruébala en `…/api/v1/health`.

## Conectar la app publicada

En GitHub → *Settings → Secrets and variables → Actions → Variables* crea `API_BASE_URL` con la URL del Worker (sin barra final). El siguiente despliegue de la app web la usará y el perfil mostrará "Cuenta sincronizada con el servidor".

El Worker ya acepta peticiones de `https://humedalvaldi-crypto.github.io` (`ALLOWED_ORIGINS` en `worker/wrangler.toml`).

## Límites y costes (comprobar los vigentes en cloudflare.com)

| Servicio | Plan gratuito (referencia) | Qué consume |
|---|---|---|
| Workers | 100 000 peticiones/día | Cada llamada a la API |
| D1 | 5 GB, 5 M filas leídas/día | Consultas |
| R2 | 10 GB, 1 M escrituras/mes, sin coste de salida | Fotos, audios, PDF |
| Rate Limiting | Incluido | Límites por usuario: 60 escrituras/min, 20 subidas/min, 300 lecturas públicas/min |

Estas cifras son orientativas y pueden cambiar; no se garantiza ninguna capacidad sin pruebas de carga (Fase 9).

## Reversión

- **Código**: vuelve a ejecutar el workflow desde un commit anterior, o en el panel *Workers → Deployments → Rollback*.
- **Datos**: D1 Time Travel (`npx wrangler d1 time-travel restore …`) o el respaldo `.sql` del artefacto. Ver `backup-and-recovery.md`.
