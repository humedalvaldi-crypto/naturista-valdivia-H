#!/usr/bin/env bash
# Agrega al manifiesto de Android (generado con `flutter create`) los permisos
# que usa la app: internet (API y mapas) y ubicación (GPS de observaciones).
# Idempotente: se puede ejecutar varias veces.
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=android/app/src/main/AndroidManifest.xml
[ -f "$manifest" ] || { echo "No existe $manifest (ejecuta flutter create primero)"; exit 0; }
for perm in INTERNET ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
  if ! grep -q "android.permission.$perm" "$manifest"; then
    sed -i "s#<application#<uses-permission android:name=\"android.permission.$perm\" />\n    <application#" "$manifest"
    echo "Permiso agregado: $perm"
  fi
done
