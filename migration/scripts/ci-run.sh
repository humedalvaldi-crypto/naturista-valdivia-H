#!/usr/bin/env bash
# Ejecuta un paso en CI mostrando su salida YA CENSURADA (los registros de un
# repositorio público los puede leer cualquiera) y, si falla, publica las
# últimas líneas como aviso (::error::), también censuradas.
set -uo pipefail
log=$(mktemp)
"$@" 2>&1 | python3 -u "$(dirname "$0")/redact_stream.py" "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  python3 - "$log" "$*" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()[-40:]
body = "\n".join(lines).replace("%", "%25").replace("\r", "").replace("\n", "%0A")
print("::error title=Fallo en: " + sys.argv[2][:80] + "::" + body)
PY
fi
rm -f "$log"
exit "$status"
