# Despliegue de la API (Cloudflare, plan gratuito)

La API funciona en el **plan gratuito de Cloudflare, sin tarjeta**: usa Workers
y D1. R2 (almacenamiento de archivos) es opcional, porque Cloudflare pide
registrar un medio de pago para activarlo. **Sin R2, las fotos se guardan en la
propia base D1.**

El despliegue lo hace solo el workflow **"Desplegar API (Cloudflare, plan
gratuito)"**. Lo único que tienes que hacer tú es crear la cuenta y pegar dos
claves en GitHub (nadie más debe manejarlas).

## Paso 1 — Cuenta de Cloudflare (gratis, sin tarjeta)

1. Crea una cuenta en https://dash.cloudflare.com/sign-up y confirma tu correo.
2. Entra a **Workers y Pages** (menú lateral) una vez. Si te pide elegir un
   **subdominio `workers.dev`**, elige uno (por ejemplo `naturista-valdivia`).
   La API quedará en `https://naturista-valdivia-api.<tu-subdominio>.workers.dev`.
3. Copia tu **Account ID**: aparece a la derecha en *Workers y Pages*
   (o en la URL del panel: `dash.cloudflare.com/<ACCOUNT_ID>/…`).

## Paso 2 — Token de API

1. Arriba a la derecha: **perfil → My Profile → API Tokens → Create Token**.
2. Elige la plantilla **"Edit Cloudflare Workers"** → *Use template*.
3. En *Permissions* añade una fila: **Account → D1 → Edit**.
   (Si algún día activas R2, añade también **Account → Workers R2 Storage → Edit**.)
4. *Account Resources*: tu cuenta. *Continue to summary → Create Token*.
5. Copia el token: **solo se muestra una vez**. No lo compartas con nadie ni lo pegues en el chat.

## Paso 3 — Pegar las claves en GitHub

En el repositorio `naturista-valdivia-H` → **Settings → Secrets and variables
→ Actions → New repository secret**, crea:

| Nombre | Valor |
|---|---|
| `CLOUDFLARE_API_TOKEN` | el token del paso 2 |
| `CLOUDFLARE_ACCOUNT_ID` | el Account ID del paso 1 |

## Paso 4 — Desplegar

**Actions → "Desplegar API (Cloudflare, plan gratuito)" → Run workflow**.
Tarda unos 3 minutos y hace todo:

1. Pruebas y comprobación de tipos.
2. Crea la base D1 `naturista-valdivia-db` si no existe.
3. Usa R2 si tu cuenta lo tiene; si no, guarda los archivos en D1.
4. Respaldo de la base (artefacto de 30 días) y migraciones.
5. Despliega el Worker y crea su clave de enlaces firmados (una sola vez).
6. Comprueba que `…/api/v1/health` responde.
7. Guarda la URL en `deploy/api-url.txt` y **vuelve a publicar la app web**
   ya conectada al servidor.

Desde ese momento, cada cambio en `worker/` que llegue a `main` se despliega
solo. Sin los dos secretos, el workflow termina sin hacer nada (no falla).

Si quieres que nada se despliegue sin tu aprobación: **Settings →
Environments → production → Required reviewers** y elígete.

### Si algo falla

| Mensaje | Qué hacer |
|---|---|
| "Faltan los secretos…" | Revisa el paso 3 (nombres exactos). |
| "Falta elegir el subdominio workers.dev" | Paso 1.2 y vuelve a ejecutar. |
| Error de permisos / `Authentication error` | El token no tiene **D1 Edit** o es de otra cuenta (paso 2). |
| "La cuenta no admite los límites de frecuencia" (aviso) | No es un error: se despliega sin ellos. |

## Conectar la app publicada

Es automático (paso 4.7). Si prefieres fijar otra URL, crea la variable
`API_BASE_URL` en *Settings → Secrets and variables → Actions → Variables*:
tiene prioridad sobre `deploy/api-url.txt`.

El Worker acepta peticiones de `https://humedalvaldi-crypto.github.io`
(`ALLOWED_ORIGINS` en `worker/wrangler.toml`).

## Límites del plan gratuito (comprobados en la documentación de Cloudflare, oct. 2026)

| Servicio | Límite gratuito | Qué significa aquí |
|---|---|---|
| Workers | 100 000 peticiones/día; 10 ms de CPU por petición | Suficiente para el proyecto escolar. Guardar páginas de cuaderno con dibujos **muy** grandes podría superar los 10 ms; si pasa, se verá como error al guardar esa página. |
| D1 | 500 MB por base, 5 GB por cuenta; 2 MB por valor | Sin R2 las fotos cuentan aquí: con fotos de ~400 KB caben unas 1000 junto con el resto de datos. |
| Cron | 5 por cuenta | Se usa 1 (limpieza diaria de archivos). |
| R2 (opcional) | 10 GB; requiere registrar medio de pago | Si se activa, las fotos nuevas van a R2 y las antiguas siguen sirviéndose desde D1. |

Fuentes: [límites de D1](https://developers.cloudflare.com/d1/platform/limits/),
[límites de Workers](https://developers.cloudflare.com/workers/platform/limits/).
Pueden cambiar; revisa el uso en el panel de Cloudflare.

## Mapas base

La app usa las teselas públicas de OpenStreetMap y OpenTopoMap, con atribución
visible. Sus servidores son para uso moderado (ver
https://operations.osmfoundation.org/policies/tiles/). Si el uso crece, cambiar
a un proveedor con cuenta propia en `app/lib/shared/map/map_tiles.dart`.

## Reversión

- **Código**: en el panel *Workers → naturista-valdivia-api → Deployments → Rollback*,
  o vuelve a ejecutar el workflow desde un commit anterior.
- **Datos**: D1 Time Travel (`npx wrangler d1 time-travel restore …`) o el
  respaldo `.sql` del artefacto. Ver `backup-and-recovery.md`.
