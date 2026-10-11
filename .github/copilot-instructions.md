# Instrucciones para GitHub Copilot — Naturista Valdivia

Lee primero `docs/coordination.md`: dice qué archivos te tocan, cuáles no y los
contratos de la API. Claude (jefe técnico) revisa cada PR antes de integrarlo.

## Reglas
- Responde y escribe la interfaz en **español** (Chile). Comentarios de código en español.
- **Sin datos ficticios**: nada de listas estáticas, contadores simulados ni
  usuarios de ejemplo en `lib/`. Los datos salen de la API (`ApiScope.of(context)`).
- Cada texto visible va en `app/l10n/app_es.arb` (plantilla, con `@clave`
  si tiene marcadores) **y en las otras 11 traducciones** (`app_en`, `pt`, `fr`,
  `de`, `it`, `zh`, `ja`, `ko`, `ar`, `ru`, `hi`). `app_arn.arb` (mapudungun) NO se toca:
  lo revisan hablantes. `test/l10n_test.dart` falla si falta una clave.
- Solo modifica los archivos que tu issue asigna. Si necesitas cambiar otro,
  pregúntalo en el issue en vez de editarlo.
- No cambies `worker/`, `migration/`, `.github/workflows/` ni
  `app/lib/core/` (salvo la línea de ruta que indique tu issue).
- Pruebas: `flutter analyze` sin avisos y `flutter test` en verde. Usa
  `test/support/fake_api_server.dart` (agrega rutas falsas ahí solo para
  probar) y `pumpTestApp`. En 400×800 desplázate con `scrollUntilVisible`
  antes de tocar algo que puede estar fuera de pantalla.
- Accesibilidad: botones con `tooltip` o texto, `Key` estable para pruebas.
- Seguridad: el servidor ya valida permisos; no confíes en el cliente ni
  guardes tokens. No registres datos personales en `debugPrint`.
