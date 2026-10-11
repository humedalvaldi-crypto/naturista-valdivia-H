# Ficha de Google Play — Naturista Valdivia

Textos listos para copiar en Play Console. Todo lo descrito existe en la app actual: no se mencionan funciones que no estén implementadas.

## Nombre (máx. 30)
Naturista Valdivia

## Descripción breve (máx. 80)
Observa, registra y comparte la biodiversidad de los humedales de Valdivia.

## Descripción completa (máx. 4000)
Naturista Valdivia es la libreta de campo del proyecto «Vivir entre Humedales» (Explora 25-26) para conocer y cuidar la naturaleza de Valdivia.

OBSERVA Y REGISTRA
• Registra observaciones de aves, mamíferos, flora, hongos e insectos con foto, fecha y ubicación (GPS o punto en el mapa).
• Mapa de biodiversidad con las observaciones de la comunidad y lugares de interés.
• Las especies amenazadas se muestran a otras personas solo con ubicación aproximada, para protegerlas.

CUADERNO DE CAMPO
• Cuadernos con páginas para escribir, dibujar, pegar stickers y fotos, y grabar notas de audio.
• Álbum de especies: desbloquea ilustraciones a medida que observas, con logros.

COMUNIDAD
• Publica lo que viste, comenta y da «me gusta».
• Busca personas, síguelas y mira quién te sigue.
• Únete a comunidades y escribe mensajes privados.
• Comparte publicaciones con un enlace.

TU PRIVACIDAD
• Tú decides quién ve tu perfil, tus publicaciones, tus observaciones y tus cuadernos, y quién puede escribirte.
• Bloquea y reporta cuando lo necesites.
• Descarga una copia de todos tus datos o elimina tu cuenta desde Configuración.
• Desbloqueo opcional con huella o rostro: lo verifica tu teléfono y nunca se envía al servidor.
• Sin publicidad y sin venta de datos.

ACCESIBLE
• Tamaño de texto, alto contraste, reducir movimiento y formato de 24 horas.
• Disponible en español, inglés, portugués, francés, alemán, italiano, chino, japonés, coreano, árabe, ruso e hindi, además de una versión preliminar en mapudungun.

Naturista Valdivia es un proyecto educativo. Para usar la comunidad necesitas una cuenta (correo o Google). Edad mínima: 14 años.

## Categoría
Educación. Etiquetas sugeridas: naturaleza, ciencia ciudadana.

## Recursos gráficos
- Ícono: `app/store/icono-512.png` (512×512, PNG).
- Gráfico destacado: `app/store/grafico-destacado-1024x500.png`.
- Capturas: de 2 a 8, de teléfono, tomadas desde la app real con datos de prueba (pendiente).

## Seguridad de los datos (respuestas sugeridas, verificadas con el código)
- ¿Recopila o comparte datos? **Sí recopila; no comparte con terceros.** Los proveedores (Firebase y Cloudflare) actúan en nombre de la app y no cuentan como «compartir».
- ¿Cifrado en tránsito? **Sí** (HTTPS).
- ¿Se puede pedir la eliminación? **Sí**, desde la app y en https://humedalvaldi-crypto.github.io/naturista-valdivia-H/eliminar-cuenta.html

| Tipo de dato | ¿Se recopila? | Obligatorio | Finalidad |
|---|---|---|---|
| Información personal → Correo electrónico | Sí | Obligatorio (cuenta) | Funcionalidad de la app, administración de la cuenta |
| Información personal → Nombre, ID de usuario | Sí | Opcional (perfil) | Funcionalidad de la app, administración de la cuenta |
| Ubicación → Ubicación precisa | Sí | Opcional (observaciones y mapa) | Funcionalidad de la app |
| Mensajes → Otros mensajes de la app (mensajes privados) | Sí | Opcional | Funcionalidad de la app |
| Fotos y videos → Fotos | Sí | Opcional | Funcionalidad de la app |
| Archivos de audio → Grabaciones de voz o sonido | Sí | Opcional (notas de audio) | Funcionalidad de la app |
| Actividad en la app → Otro contenido generado por el usuario (publicaciones, comentarios, cuadernos, observaciones) | Sí | Opcional | Funcionalidad de la app |
| Actividad en la app → Interacciones (me gusta, seguir, guardados) | Sí | Opcional | Funcionalidad de la app |
| Datos biométricos | **No** (los compara el teléfono) | — | — |
| Identificadores de dispositivo, publicidad, analítica, registros de fallos | **No** | — | — |

## Clasificación de contenido (cuestionario IARC)
- Categoría: Social / comunicación, más referencia/educación.
- Usuarios interactúan entre sí: **Sí** (comentarios, mensajes y publicaciones). Hay herramientas para bloquear y reportar.
- Comparte la ubicación del usuario con otros: **Sí**, la ubicación de las observaciones públicas (aproximada para especies sensibles o si la persona la oculta).
- Compras digitales: No. Publicidad: No. Violencia, sexo, drogas, apuestas: No.

## Público objetivo
13–15, 16–17 y 18+. La app pide 14 años o más en la aceptación de condiciones. **No** incluir menores de 13.

## Anuncios
La app **no** contiene anuncios.

## Acceso a la app
Algunas funciones requieren iniciar sesión. Crea una cuenta exclusiva para la revisión de Google, sin datos reales, y entrega sus credenciales **solo** en el formulario de Play Console.

## Permisos declarados y por qué
- `INTERNET`: API y mapas.
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`: ubicación de observaciones y «mi ubicación», solo en primer plano y a pedido.
- `RECORD_AUDIO`: notas de audio en los cuadernos, solo mientras se graba.
- `USE_BIOMETRIC`: desbloqueo opcional con huella o rostro.
