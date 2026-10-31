#!/bin/bash
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/Prisma"
APP="$HOME/Applications/Prisma.app"
if [ ! -d "$APP" ]; then
  APP="$HOME/Desktop/Prisma/app/Prisma.app"
fi

ENGINE=""
VOICE=""
TEXT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -e|--engine)
      ENGINE="${2:-}"
      shift 2
      ;;
    -v|--voice)
      VOICE="${2:-}"
      shift 2
      ;;
    *)
      if [ -z "$TEXT" ]; then
        TEXT="$1"
      elif [ -z "$VOICE" ]; then
        VOICE="$1"
      fi
      shift
      ;;
  esac
done

TEXT="${TEXT:-Hola. Prisma está funcionando.}"

if [ ! -f "$SUPPORT/runtime.json" ]; then
  echo "Abriendo Prisma…"
  open "$APP"
  sleep 2
fi

if [ ! -f "$SUPPORT/runtime.json" ]; then
  echo "❌ No se encontró runtime.json. ¿Está instalada la app?"
  exit 1
fi

PORT="$(jq -r '.port' "$SUPPORT/runtime.json")"
TOKEN="$(jq -r '.token' "$SUPPORT/runtime.json")"

PAYLOAD="$(jq -n \
  --arg text "$TEXT" \
  --arg cwd "$PWD" \
  --arg engine "$ENGINE" \
  --arg voice "$VOICE" \
  '{text: $text, cwd: $cwd}
   + (if $engine != "" then {engine: $engine} else {} end)
   + (if $voice != "" then {voice: $voice} else {} end)')"

curl -sS --max-time 5 -X POST "http://127.0.0.1:${PORT}/speak" \
  -H "Content-Type: application/json" \
  -H "Expect:" \
  -H "X-Prisma-Token: ${TOKEN}" \
  --data-binary "$PAYLOAD"

echo
