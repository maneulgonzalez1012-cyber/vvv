#!/usr/bin/env bash
# Aero / Roblox -- regenera los links cortos ("el corto").
# Uso: ./shorten.sh [SHA_a_congelar]
# No corre dentro del sandbox (salida hacia is.gd/tinyurl cortada); ejecutalo en
# tu maquina. Requiere curl + python3. Los aliases ya creados no se pueden
# reutilizar: si el alias esta ocupado la API devuelve error, cambia el nombre.
set -euo pipefail

OWNER="maneulgonzalez1012-cyber"
REPO="vvv"
BRANCH="arena/6922546f-vvv"
SHA="${1:-5bb615475686e477fd79f6c80a0ceb9eec07dda3}"

raw() { printf 'https://raw.githubusercontent.com/%s/%s/%s/%s' "$OWNER" "$REPO" "$1" "$2"; }
enc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

isgd() {
    local alias="$1" url="$2"
    printf '%-12s ' "$alias"
    curl -fsS "https://is.gd/create.php?format=simple&shorturl=${alias}&url=$(enc "$url")" || echo "FALLO"
    echo
}

isgd aerovvv "$(raw "$BRANCH" aero_roblox.lua)"
isgd aeroldr "$(raw "$BRANCH" loader.lua)"
isgd aeropin "$(raw "$SHA" aero_roblox.lua)"

printf '%-12s ' "tinyurl"
curl -fsS "https://tinyurl.com/api-create.php?alias=aero-vvv&url=$(enc "$(raw "$BRANCH" aero_roblox.lua)")" || echo "FALLO"
echo
