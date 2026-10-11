#!/usr/bin/env bash
# Firma de publicación para Google Play.
# Lee android/key.properties (lo escribe el flujo de publicación a partir de
# secretos de GitHub; nunca se guarda en el repositorio) y lo usa para firmar
# la compilación "release". Si falta key.properties, la compilación release
# FALLA en vez de firmarse con la clave de depuración.
# Idempotente. Uso (desde app/): bash platform_patches/android_release_signing.sh
set -euo pipefail
cd "$(dirname "$0")/.."
gradle=android/app/build.gradle.kts
[ -f "$gradle" ] || { echo "No existe $gradle (ejecuta flutter create primero)"; exit 1; }
grep -q 'create("release")' "$gradle" && { echo "La firma ya estaba configurada."; exit 0; }
python3 - "$gradle" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
loader = '''
val keystoreProperties = java.util.Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) java.io.FileInputStream(f).use { load(it) }
}
'''
s = s.replace('\nandroid {', loader + '\nandroid {', 1)
signing = '''
    signingConfigs {
        create("release") {
            if (keystoreProperties.isEmpty()) {
                throw GradleException("Falta android/key.properties: la versión de publicación solo se firma con la clave de subida.")
            }
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    buildTypes {'''
assert '\n    buildTypes {' in s, 'buildTypes no encontrado'
s = s.replace('\n    buildTypes {', signing, 1)
s, n = re.subn(r'signingConfig = signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', s)
assert n == 1, 'signingConfig debug no encontrado'
open(p, 'w').write(s)
PY
echo "Firma de publicación configurada en $gradle"
