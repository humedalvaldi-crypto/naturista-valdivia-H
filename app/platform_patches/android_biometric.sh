#!/usr/bin/env bash
# Ajustes de Android para el desbloqueo con huella o rostro (local_auth):
# - MainActivity debe ser FlutterFragmentActivity (lo exige BiometricPrompt).
# - Permiso USE_BIOMETRIC.
# - LaunchTheme basado en Theme.AppCompat (evita cierres en Android 8 o menor).
# - minSdk 24 (local_auth 3 y flutter_secure_storage 10).
# Idempotente.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d android ] || { echo "No existe android/ (ejecuta flutter create primero)"; exit 0; }

activity=$(grep -rl "class MainActivity" android/app/src/main | head -n1 || true)
if [ -n "$activity" ]; then
  sed -i 's/import io.flutter.embedding.android.FlutterActivity$/import io.flutter.embedding.android.FlutterFragmentActivity/' "$activity"
  sed -i 's/import io.flutter.embedding.android.FlutterActivity;/import io.flutter.embedding.android.FlutterFragmentActivity;/' "$activity"
  sed -i 's/: FlutterActivity()/: FlutterFragmentActivity()/; s/extends FlutterActivity/extends FlutterFragmentActivity/' "$activity"
  echo "MainActivity: $(grep -o 'FlutterFragmentActivity' "$activity" | head -n1)"
fi

manifest=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.USE_BIOMETRIC" "$manifest"; then
  sed -i "s#<application#<uses-permission android:name=\"android.permission.USE_BIOMETRIC\" />\n    <application#" "$manifest"
  echo "Permiso agregado: USE_BIOMETRIC"
fi

for styles in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  [ -f "$styles" ] || continue
  sed -i 's#<style name="LaunchTheme" parent="[^"]*"#<style name="LaunchTheme" parent="Theme.AppCompat.DayNight.NoActionBar"#' "$styles"
  sed -i 's#<style name="NormalTheme" parent="[^"]*"#<style name="NormalTheme" parent="Theme.AppCompat.DayNight.NoActionBar"#' "$styles"
done

for gradle in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$gradle" ] || continue
  sed -i 's/minSdk = flutter.minSdkVersion$/minSdk = maxOf(flutter.minSdkVersion, 24)/' "$gradle"
  sed -i 's/minSdkVersion flutter.minSdkVersion$/minSdkVersion Math.max(flutter.minSdkVersion, 24)/' "$gradle"
  grep -n "minSdk" "$gradle" || true
  # Theme.AppCompat necesita la biblioteca appcompat.
  if ! grep -q "androidx.appcompat:appcompat" "$gradle"; then
    if [[ "$gradle" == *.kts ]]; then
      printf '\ndependencies {\n    implementation("androidx.appcompat:appcompat:1.7.0")\n}\n' >> "$gradle"
    else
      printf "\ndependencies {\n    implementation 'androidx.appcompat:appcompat:1.7.0'\n}\n" >> "$gradle"
    fi
  fi
done
