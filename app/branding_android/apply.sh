#!/usr/bin/env bash
# Aplica la marca a la carpeta android/ generada por `flutter create`:
# nombre visible "Naturista Valdivia" e ícono del proyecto (logo "Vivir entre Humedales").
# Idempotente. Uso (desde app/): bash branding_android/apply.sh
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=android/app/src/main/AndroidManifest.xml
[ -f "$manifest" ] || { echo "No existe $manifest (ejecuta flutter create primero)"; exit 0; }
sed -i 's#android:label="[^"]*"#android:label="Naturista Valdivia"#' "$manifest"
cp -r branding_android/res/. android/app/src/main/res/
grep -o 'android:label="[^"]*"' "$manifest"
echo "Marca Android aplicada."
