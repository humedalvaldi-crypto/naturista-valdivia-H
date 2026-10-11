# Publicar Naturista Valdivia en Google Play

Estado: la compilación firmada, el ícono, las páginas legales y los textos de la ficha están listos en el repositorio. Los pasos marcados con 👤 **solo los puede hacer la persona dueña de la cuenta**: requieren identidad, pago o aceptar contratos. Nadie más debe hacerlos por ti, y nunca compartas contraseñas ni claves en un chat.

| Dato | Valor |
|---|---|
| Paquete (applicationId) | `cl.naturistavaldivia.naturista_valdivia`. No se puede cambiar después de publicar. |
| Versión | `0.1.0`. El número de compilación es 100 + n.º de ejecución del flujo y sube solo. |
| Compilación | Flujo **Android para Google Play** (`.github/workflows/android-release.yml`) |
| Política de privacidad | https://humedalvaldi-crypto.github.io/naturista-valdivia-H/privacidad.html |
| Eliminar cuenta | https://humedalvaldi-crypto.github.io/naturista-valdivia-H/eliminar-cuenta.html |
| Ícono 512×512 | `app/store/icono-512.png` |
| Gráfico destacado 1024×500 | `app/store/grafico-destacado-1024x500.png` |

## 1. 👤 Cuenta de desarrollador

1. Entra en https://play.google.com/console y crea la cuenta de desarrollador. Cuesta US$25, se paga una vez, y Google verifica tu identidad.
2. Elige el tipo de cuenta:
   - **Personal**: antes de pasar a producción, Google exige una **prueba cerrada con al menos 12 personas durante 14 días seguidos**.
   - **Organización**: requiere un número D-U-N-S y no tiene ese requisito.

## 2. 👤 Clave de subida (en tu computador)

Hay dos formas de crearla:

- **Con Android Studio:** Build → Generate Signed Bundle → Create new.
- **Con Java instalado:**

```bash
keytool -genkeypair -v -keystore naturista-upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

Guarda `naturista-upload.jks` y sus contraseñas en un lugar seguro, como un gestor de contraseñas, con copia de respaldo. **No la subas al repositorio** (es público).

Para pasarla a GitHub, conviértela en texto:

```bash
base64 -w0 naturista-upload.jks > naturista-upload.b64   # Linux
base64 -i naturista-upload.jks -o naturista-upload.b64   # macOS
```

## 3. 👤 Secretos en GitHub

En el repositorio, ve a Settings → Secrets and variables → Actions → **New repository secret** y crea estos secretos:

| Secreto | Contenido |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | El contenido de `naturista-upload.b64` |
| `ANDROID_UPLOAD_KEYSTORE_PASSWORD` | La contraseña del almacén |
| `ANDROID_UPLOAD_KEY_ALIAS` | `upload` (o el alias que elegiste) |
| `ANDROID_UPLOAD_KEY_PASSWORD` | La contraseña de la clave |

Después borra `naturista-upload.b64` de tu computador. El `.jks` sí se conserva.

## 4. Compilar el AAB

Ve a Actions → **Android para Google Play** → Run workflow, con pista `none`.

El flujo hace lo siguiente:

1. Ejecuta las pruebas.
2. Compila el `.aab` firmado.
3. Verifica la firma.
4. Muestra en el resumen las huellas SHA-1 y SHA-256 de tu clave de subida.
5. Deja el archivo en *Artifacts*, donde se guarda 14 días.

## 5. 👤 Crear la app en Play Console y primera subida

1. En Play Console, entra en **Crear app**:
   - Nombre: «Naturista Valdivia».
   - Idioma: español (Latinoamérica).
   - Tipo: App.
   - Precio: Gratis.
2. Acepta las declaraciones.
3. Ve a Pruebas → **Prueba interna** → Crear versión.
4. Acepta **Firma de apps de Play**. Google guarda la clave de firma final y tú solo usas la de subida.
5. Sube el `.aab` descargado en el paso 4.

## 6. 👤 Firebase: registrar el paquete nuevo

La app Android que hoy existe en Firebase usa el paquete `App_val.nat`, que es de la app anterior. Para registrar esta app:

1. En Firebase Console (proyecto `humedalvaldivia-c7d08`), ve a Configuración del proyecto → Agregar app → Android, con el paquete `cl.naturistavaldivia.naturista_valdivia`.
2. Agrega dos pares de huellas SHA-1 y SHA-256:
   - Los de la **clave de subida**, que salen en el resumen del paso 4.
   - Los de la **clave de firma de Play**, que están en Play Console → Configuración → Integridad de la app → Firma de apps.
3. Copia el **App ID** (`1:207771391405:android:…`) a GitHub, en Settings → Variables → `FIREBASE_ANDROID_APP_ID`. No es secreto.
4. Vuelve a ejecutar el paso 4.

Si la app anterior ya está publicada en Play con el paquete `App_val.nat`, hay que decidir entre dos caminos:

- **Ficha nueva** (este documento).
- **Actualizar la app anterior.** Para eso hace falta el mismo paquete y la clave de subida de esa ficha.

## 7. 👤 Ficha de Play Store

Copia los textos de `app/store/ficha-play.md` y completa las secciones de Play Console:

- Ficha principal.
- Clasificación de contenido.
- Público objetivo: 13 años o más. La app pide 14.
- Seguridad de los datos.
- Acceso a la app.

El **acceso a la app** necesita credenciales para la revisión de Google. Crea tú una cuenta de prueba exclusiva para eso, sin datos reales, y escríbela solo en el formulario de Play Console.

## 8. 👤 Prueba cerrada (cuentas personales)

1. Ve a Pruebas → Prueba cerrada → crea una lista con al menos 12 correos de Google.
2. Envíales el enlace de participación.
3. Deben instalar la app y mantenerse inscritos **14 días seguidos**.
4. Después, Play Console habilita «Solicitar acceso a producción».

## 9. Publicaciones siguientes (opcional, automático)

1. 👤 En Google Cloud, crea una cuenta de servicio.
2. 👤 En Play Console, ve a Usuarios y permisos e invítala con permiso de *versiones* solo para esta app.
3. 👤 Guarda su JSON como secreto `PLAY_SERVICE_ACCOUNT_JSON`.

Con eso, al ejecutar el flujo con pista `internal`, `alpha` o `beta`, la versión se sube como **borrador**. Tú la revisas y la publicas desde Play Console.

## Seguridad

- La clave de subida existe solo en tu computador y en los secretos de GitHub. El flujo la escribe en el equipo temporal y la borra al terminar.
- Si la clave de subida se pierde o se filtra, se puede pedir a Google que la reemplace (Integridad de la app). La clave de firma final la guarda Google.
- Si falta la configuración de firma, la versión de publicación **no se compila**: nunca se sube una versión firmada con la clave de depuración.

## Pendiente antes de producción

- Revisión legal de la política de privacidad y de la edad mínima (14 años).
- Correo de contacto público para la ficha y la política.
- Decidir si «Eliminar cuenta» debe borrar también el acceso de Firebase. Hoy no lo borra, porque se comparte con la app anterior; se elimina a pedido. Google Play exige que la eliminación de la cuenta sea efectiva.
- Capturas de pantalla: de 2 a 8 de teléfono. Se toman desde la app instalada en la prueba interna, con datos de prueba.
