#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/Prisma"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="$CODEX_HOME/hooks.json"

echo "✨ Instalando Prisma en $PROJECT_ROOT"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Necesito jq para configurar el hook. Instálalo con: brew install jq"
  exit 1
fi

if [ ! -x "$PROJECT_ROOT/.venv/bin/python3" ] && [ ! -x "$SUPPORT/venv/bin/python3" ]; then
  echo "❌ No encontré el entorno de voz en $SUPPORT/venv."
  echo "   Ejecuta ./setup_voice.sh."
  exit 1
fi

echo "🔨 Compilando la app…"
"$PROJECT_ROOT/app/build.sh" >/dev/null
rm -rf "$PROJECT_ROOT/app/.build"

echo "📲 Instalando la app en ~/Applications/Prisma.app…"
pkill -f 'Prisma.app/Contents/MacOS/Prisma' 2>/dev/null || true
pkill -f 'CodexVoz.app/Contents/MacOS/CodexVoz' 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Prisma.app" "$HOME/Applications/CodexVoz.app"
cp -R "$PROJECT_ROOT/app/Prisma.app" "$HOME/Applications/Prisma.app"

echo "📦 Preparando entorno de voz en Application Support…"
mkdir -p "$SUPPORT/venv" "$SUPPORT/voices" "$SUPPORT/tmp"
if [ -x "$PROJECT_ROOT/.venv/bin/python3" ]; then
  rsync -a --delete "$PROJECT_ROOT/.venv/" "$SUPPORT/venv/"
fi
if [ -f "$PROJECT_ROOT/voices/piper/es_MX-claude-high.onnx" ]; then
  cp "$PROJECT_ROOT/voices/piper/es_MX-claude-high.onnx" "$SUPPORT/voices/"
  cp "$PROJECT_ROOT/voices/piper/es_MX-claude-high.onnx.json" "$SUPPORT/voices/"
fi

echo "🪝 Instalando el hook en Codex…"
cp "$PROJECT_ROOT/plugin/scripts/on_stop.sh" "$SUPPORT/on_stop.sh"
chmod +x "$SUPPORT/on_stop.sh"

mkdir -p "$CODEX_HOME"
HOOK_COMMAND="bash \"$SUPPORT/on_stop.sh\""
OLD_HOOK_COMMAND="bash \"$HOME/Library/Application Support/CodexVoz/on_stop.sh\""
if [ -f "$HOOKS_FILE" ]; then
  jq --arg cmd "$HOOK_COMMAND" --arg old "$OLD_HOOK_COMMAND" '
    .hooks = (.hooks // {}) |
    .hooks.Stop = (
      ((.hooks.Stop // [])
        | map(.hooks = ((.hooks // []) | map(select(.command != $cmd and .command != $old and .statusMessage != "CodexVoz" and .statusMessage != "Prisma"))))
        | map(select((.hooks | length) > 0)))
      + [{"hooks": [{"type": "command", "command": $cmd, "timeout": 10, "statusMessage": "Prisma"}]}]
    )
  ' "$HOOKS_FILE" > "$HOOKS_FILE.tmp"
  mv "$HOOKS_FILE.tmp" "$HOOKS_FILE"
else
  jq -n --arg cmd "$HOOK_COMMAND" '{
    hooks: {
      Stop: [
        {hooks: [{type: "command", command: $cmd, timeout: 10, statusMessage: "Prisma"}]}
      ]
    }
  }' > "$HOOKS_FILE"
fi

echo "🔌 Instalando el plugin Prisma en Codex, Claude Code y OpenCode…"
if command -v codex >/dev/null 2>&1; then
  codex plugin remove codex-voz@codex-voz-local >/dev/null 2>&1 || true
  codex plugin marketplace remove codex-voz-local >/dev/null 2>&1 || true
  codex plugin marketplace add "$PROJECT_ROOT" >/dev/null 2>&1 || true
  codex plugin remove prisma@prisma-local >/dev/null 2>&1 || true
  codex plugin add prisma@prisma-local >/dev/null 2>&1 || true
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin uninstall codex-voz@codex-voz-local >/dev/null 2>&1 || true
  claude plugin marketplace remove codex-voz-local >/dev/null 2>&1 || true
  claude plugin marketplace remove prisma-local >/dev/null 2>&1 || true
  claude plugin marketplace add "$PROJECT_ROOT" >/dev/null 2>&1 || true
  claude plugin uninstall prisma@prisma-local >/dev/null 2>&1 || true
  claude plugin install prisma@prisma-local >/dev/null 2>&1 || true
  claude plugin enable prisma@prisma-local >/dev/null 2>&1 || true
fi

if [ -d "$HOME/.config/opencode" ] || command -v opencode >/dev/null 2>&1; then
  rm -f "$HOME/.config/opencode/plugins/codex-voz.ts"
  rm -rf "$HOME/.config/opencode/skills/codex-voz"
  mkdir -p "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/skills/prisma"
  cp "$PROJECT_ROOT/plugin/opencode/prisma.ts" "$HOME/.config/opencode/plugins/prisma.ts"
  cp "$PROJECT_ROOT/plugin/skills/prisma/SKILL.md" "$HOME/.config/opencode/skills/prisma/SKILL.md"
  opencode reload >/dev/null 2>&1 || true
fi

echo "⚙️  Creando configuración local…"
if [ -f "$SUPPORT/config.json" ]; then
  TOKEN="$(jq -r '.token // empty' "$SUPPORT/config.json")"
else
  TOKEN="$(uuidgen)"
fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(uuidgen)"
fi

jq -n \
  --arg py "$SUPPORT/venv/bin/python3" \
  --arg model "$SUPPORT/voices/es_MX-claude-high.onnx" \
  --arg root "$PROJECT_ROOT" \
  --arg token "$TOKEN" \
  '{port: 8787, token: $token, piperPython: $py, piperModel: $model, projectRoot: $root}' \
  > "$SUPPORT/config.json"

echo "🚀 Abriendo Prisma…"
open "$HOME/Applications/Prisma.app"

cat <<EOF

✅ Prisma instalado en Codex, Claude Code y OpenCode.

- App: ~/Applications/Prisma.app
- Datos: $SUPPORT
- Prueba rápida:
  ~/Desktop/Prisma/test.sh "Hola. Prisma está funcionando."
EOF
