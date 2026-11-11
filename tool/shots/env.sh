#!/usr/bin/env bash
# Helpers for tool/shots/release.toml. Usage: env.sh <repo|paseo|forward|paseo-stop>
# SHOTS_SCRATCH = work dir for the demo repo and logs (required).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="${SHOTS_SCRATCH:?set SHOTS_SCRATCH}"
REPO="$SC/shop-app"
PASEO_DIR=${SHOTS_PASEO_DIR:?set it in private.env}
PASEO=${SHOTS_PASEO_BIN:?set it in private.env}
PHOME="$SC/paseo-home"   # fresh copy of the config each run, so old conversations never show
bw() { bwrap --dev-bind / / --tmpfs /srv --bind "$REPO" /srv/shop-app --die-with-parent --chdir /srv/shop-app "$@"; }

case "${1:?command}" in
repo)
  rm -rf "$REPO"; mkdir -p "$REPO/src" "$REPO/docs"
  cd "$REPO"
  printf '__pycache__/\n*.pyc\n' > .gitignore
  printf '# Shop app\n\nA tiny shop with a cart.\n' > README.md
  printf 'def total(items):\n    return sum(i["price"] * i["qty"] for i in items)\n' > src/cart.py
  printf 'Spring sale: apply a discount to the whole cart.\nFree shipping over 50.\n' > docs/notes.txt
  git init -q -b main
  git -c user.name=Demo -c user.email=demo@example.com add -A
  git -c user.name=Demo -c user.email=demo@example.com commit -q -m "Initial shop app"
  printf '\n\ndef count(items):\n    return sum(i["qty"] for i in items)\n' >> src/cart.py
  ;;
paseo)  # foreground; the tool detaches it and kills its process group at the end
  export PASEO_PASSWORD="$(cat "$PASEO_DIR/daemon-password.txt")"
  export PYTHONDONTWRITEBYTECODE=1 PASEO_DICTATION_ENABLED=false PASEO_VOICE_MODE_ENABLED=false
  cd "$PASEO_DIR"
  rm -rf "$PHOME"; mkdir -p "$PHOME"; cp "$PASEO_DIR/home/config.json" "$PHOME/config.json"
  cd "$PASEO_DIR"
  bw "$PASEO" daemon run --home "$PHOME"
  ;;
paseo-stop)
  "$PASEO" daemon stop --home "$PHOME" >/dev/null 2>&1 || true
  ;;
forward)
  exec python3 "$HERE/forward.py" 127.0.0.1:16767 "${SHOTS_PASEO_HOST:?set it in private.env}:6767"
  ;;
*) echo "unknown command" >&2; exit 2;;
esac
