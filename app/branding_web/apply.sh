#!/usr/bin/env bash
# Aplica la marca a la carpeta web/ generada por `flutter create`.
# Uso (desde app/): bash branding_web/apply.sh
set -euo pipefail
cp branding_web/favicon.png web/favicon.png
mkdir -p web/icons
cp branding_web/Icon-*.png web/icons/
python3 - <<'PY'
import json, re
m = json.load(open('web/manifest.json'))
m.update({
    "name": "Naturista Valdivia",
    "short_name": "Naturista",
    "description": "Observa, registra y comparte la biodiversidad de Valdivia y sus humedales.",
    "background_color": "#1C3320",
    "theme_color": "#2E5B2A",
    "lang": "es",
})
json.dump(m, open('web/manifest.json', 'w'), ensure_ascii=False, indent=2)
html = open('web/index.html', encoding='utf-8').read()
html = re.sub(r'<title>.*?</title>', '<title>Naturista Valdivia</title>', html, flags=re.S)
html = re.sub(r'<meta name="description" content="[^"]*">',
              '<meta name="description" content="Observa, registra y comparte la biodiversidad de Valdivia y sus humedales.">', html)
html = html.replace('<html>', '<html lang="es">')
html = re.sub(r'<meta name="apple-mobile-web-app-title" content="[^"]*">',
              '<meta name="apple-mobile-web-app-title" content="Naturista">', html)
open('web/index.html', 'w', encoding='utf-8').write(html)
PY
echo "Marca web aplicada."
