#!/bin/bash
# Prisma: hook Stop compatible con Codex, Claude Code y OpenCode.
set -uo pipefail

INPUT="$(cat)"
SUPPORT="$HOME/Library/Application Support/Prisma"
RUNTIME="$SUPPORT/runtime.json"
LOG="$SUPPORT/hook.log"

mkdir -p "$SUPPORT"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

if ! command -v jq >/dev/null 2>&1; then
  log "jq no está disponible; no se puede procesar el hook."
  echo '{}'
  exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "Stop"' 2>/dev/null)"
if [ -n "$EVENT" ] && [ "$EVENT" != "Stop" ]; then
  echo '{}'
  exit 0
fi

# 1. Intentar leer last_assistant_message directo (Codex, OpenCode y versiones nuevas de Claude Code)
MESSAGE="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "codex"' 2>/dev/null)"

# 2. Si viene vacío, extraer el último mensaje de assistant desde transcript_path (Claude Code JSONL)
if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    SOURCE="claude-code"
    for _ in 1 2 3; do
      LAST_LINES="$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 100 || true)"
      if [ -n "$LAST_LINES" ]; then
        MESSAGE="$(printf '%s\n' "$LAST_LINES" | jq -rs '
          map(.message.content[]? | select(.type == "text") | .text) | map(select(length > 0)) | last // empty
        ' 2>/dev/null || true)"
      fi
      if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "null" ]; then
        break
      fi
      sleep 0.15
    done
  fi
fi

if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  log "Stop recibido sin texto de asistente."
  echo '{}'
  exit 0
fi

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"

app_is_alive() {
  local port="$1"
  curl -sS --max-time 1 "http://127.0.0.1:${port}/health" 2>/dev/null | grep -qE '"app":"(Prisma|CodexVoz)"'
}

find_port() {
  local candidate
  for candidate in $(seq 8787 8798); do
    if app_is_alive "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

launch_app() {
  if open -a "Prisma" >/dev/null 2>&1; then
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/Applications/Prisma.app" \
    "$HOME/Desktop/Prisma/app/Prisma.app" \
    "/Applications/Prisma.app"; do
    if [ -d "$candidate" ]; then
      open "$candidate" >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

PORT=""
TOKEN=""
if [ -f "$RUNTIME" ]; then
  PORT="$(jq -r '.port // empty' "$RUNTIME" 2>/dev/null)"
  TOKEN="$(jq -r '.token // empty' "$RUNTIME" 2>/dev/null)"
fi

if [ -z "$PORT" ] || ! app_is_alive "$PORT"; then
  FOUND_PORT="$(find_port || true)"
  if [ -n "$FOUND_PORT" ]; then
    PORT="$FOUND_PORT"
  else
    log "App no disponible; intentando abrir Prisma."
    launch_app || log "No se encontró Prisma.app."
    for _ in $(seq 1 20); do
      if [ -f "$RUNTIME" ]; then
        PORT="$(jq -r '.port // empty' "$RUNTIME" 2>/dev/null)"
        TOKEN="$(jq -r '.token // empty' "$RUNTIME" 2>/dev/null)"
        if [ -n "$PORT" ] && app_is_alive "$PORT"; then
          break
        fi
      fi
      FOUND_PORT="$(find_port || true)"
      if [ -n "$FOUND_PORT" ]; then
        PORT="$FOUND_PORT"
        break
      fi
      sleep 0.25
    done
  fi
fi

if [ -z "$TOKEN" ] && [ -f "$SUPPORT/config.json" ]; then
  TOKEN="$(jq -r '.token // empty' "$SUPPORT/config.json" 2>/dev/null)"
fi

if [ -z "$PORT" ]; then
  log "No se pudo obtener el puerto de Prisma."
  echo '{}'
  exit 0
fi

PAYLOAD="$(jq -n \
  --arg text "$MESSAGE" \
  --arg cwd "$CWD" \
  --arg session "$SESSION" \
  --arg source "$SOURCE" \
  '{text: $text, cwd: $cwd, session_id: $session, source: $source}')"

if [ -n "$TOKEN" ]; then
  curl -sS --max-time 5 -X POST "http://127.0.0.1:${PORT}/speak" \
    -H "Content-Type: application/json" \
    -H "Expect:" \
    -H "X-Prisma-Token: ${TOKEN}" \
    --data-binary "$PAYLOAD" >/dev/null 2>&1
else
  curl -sS --max-time 5 -X POST "http://127.0.0.1:${PORT}/speak" \
    -H "Content-Type: application/json" \
    -H "Expect:" \
    --data-binary "$PAYLOAD" >/dev/null 2>&1
fi

log "Aviso (${SOURCE}) enviado al puerto ${PORT}."
echo '{}'
exit 0
