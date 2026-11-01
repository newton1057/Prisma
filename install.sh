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
mkdir -p "$SUPPORT/scripts"
cp "$PROJECT_ROOT/plugin/scripts/on_stop.sh" "$SUPPORT/scripts/on_stop.sh"
chmod +x "$SUPPORT/scripts/on_stop.sh"
cp "$PROJECT_ROOT/plugin/scripts/on_turn.sh" "$SUPPORT/on_turn.sh"
chmod +x "$SUPPORT/on_turn.sh"

mkdir -p "$CODEX_HOME"
CODEX_AGENTS_FILE="$CODEX_HOME/AGENTS.md"
if [ ! -f "$CODEX_AGENTS_FILE" ]; then
  cat "$PROJECT_ROOT/plugin/AGENTS.md" > "$CODEX_AGENTS_FILE"
elif ! grep -q "<ForPrisma>" "$CODEX_AGENTS_FILE" 2>/dev/null; then
  if [ -s "$CODEX_AGENTS_FILE" ]; then
    printf '\n\n' >> "$CODEX_AGENTS_FILE"
  fi
  cat "$PROJECT_ROOT/plugin/AGENTS.md" >> "$CODEX_AGENTS_FILE"
elif [ "$(wc -l < "$CODEX_AGENTS_FILE")" -le 20 ]; then
  cat "$PROJECT_ROOT/plugin/AGENTS.md" > "$CODEX_AGENTS_FILE"
fi

HOOK_COMMAND="bash \"$SUPPORT/on_stop.sh\""
OLD_HOOK_COMMAND="bash \"$HOME/Library/Application Support/CodexVoz/on_stop.sh\""

install_hook_event() {
  local event="$1"
  local matcher="$2"
  local timeout=10
  if [ "$event" = "Interrupt" ] || [ "$event" = "SessionEnd" ]; then timeout=3; fi
  if [ -f "$HOOKS_FILE" ]; then
    jq --arg event "$event" --arg matcher "$matcher" --arg cmd "$HOOK_COMMAND" --arg old "$OLD_HOOK_COMMAND" --argjson timeout "$timeout" '
      .hooks = (.hooks // {}) |
      .hooks[$event] = (
        ((.hooks[$event] // [])
          | map(.hooks = ((.hooks // []) | map(select(
              .command != $cmd and .command != $old
              and .statusMessage != "CodexVoz" and .statusMessage != "Prisma"
            ))))
          | map(select((.hooks | length) > 0)))
        + [(
            {hooks: [{type: "command", command: $cmd, timeout: $timeout, statusMessage: "Prisma"}]}
            + (if $matcher != "" then {matcher: $matcher} else {} end)
          )]
      )
    ' "$HOOKS_FILE" > "$HOOKS_FILE.tmp"
    mv "$HOOKS_FILE.tmp" "$HOOKS_FILE"
  else
    jq -n --arg event "$event" --arg matcher "$matcher" --arg cmd "$HOOK_COMMAND" --argjson timeout "$timeout" '
      {
        hooks: {
          ($event): [(
            {hooks: [{type: "command", command: $cmd, timeout: $timeout, statusMessage: "Prisma"}]}
            + (if $matcher != "" then {matcher: $matcher} else {} end)
          )]
        }
      }
    ' > "$HOOKS_FILE"
  fi
}

TURN_HOOK_COMMAND="bash \"$SUPPORT/on_turn.sh\" codex"
SPEAK_HOOK_COMMAND="$HOOK_COMMAND"
HOOK_COMMAND="$TURN_HOOK_COMMAND"
install_hook_event "UserPromptSubmit" ""
install_hook_event "Interrupt" ""
install_hook_event "SessionStart" ""
install_hook_event "SessionEnd" ""
HOOK_COMMAND="$SPEAK_HOOK_COMMAND"
install_hook_event "Stop" ""
install_hook_event "PreToolUse" "AskUserQuestion|request_user_input|request_user_input_async|send_user_message_async|send_message_to_user_async|question"
install_hook_event "PermissionRequest" ""

if command -v codex >/dev/null 2>&1; then
  codex features enable default_mode_request_user_input >/dev/null 2>&1 || true
  python3 - "$PROJECT_ROOT" "$HOOKS_FILE" "$CODEX_HOME/app-server-control/app-server-control.sock" <<'PY' >/dev/null 2>&1 || true
import base64, json, os, socket, struct, subprocess, sys

cwd, hooks_file, sock_path = sys.argv[1], sys.argv[2], sys.argv[3]

proc = subprocess.Popen(
    ["codex", "app-server"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def send(msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()

def wait_id(target_id):
    while True:
        line = proc.stdout.readline()
        if not line:
            return None
        obj = json.loads(line)
        if obj.get("id") == target_id:
            return obj

updates = {}
try:
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"clientInfo": {"name": "prisma-installer", "version": "1.0.0"}}})
    wait_id(1)
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    send({"jsonrpc": "2.0", "id": 2, "method": "hooks/list", "params": {"cwds": [cwd]}})
    res = wait_id(2) or {}
    entries = (res.get("result") or {}).get("data") or []
    for entry in entries:
        for h in entry.get("hooks") or []:
            if h.get("sourcePath") == hooks_file and h.get("statusMessage") == "Prisma":
                key = h.get("key")
                current_hash = h.get("currentHash")
                if key and current_hash:
                    updates[key] = {"trusted_hash": current_hash}
    if updates:
        send({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "config/batchWrite",
            "params": {
                "edits": [{
                    "keyPath": "hooks.state",
                    "value": updates,
                    "mergeStrategy": "upsert",
                }],
                "reloadUserConfig": True,
            },
        })
        wait_id(3)
finally:
    proc.terminate()

# Si el daemon compartido de Codex está activo, pedirle también que recargue la configuración en vivo
if updates and os.path.exists(sock_path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect(sock_path)
        key = base64.b64encode(os.urandom(16)).decode()
        s.sendall((
            "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = s.recv(4096)
            if not chunk:
                break
            resp += chunk

        def ws_send(obj):
            payload = json.dumps(obj).encode("utf-8")
            mask = os.urandom(4)
            header = bytearray([0x81])
            n = len(payload)
            if n < 126:
                header.append(0x80 | n)
            elif n < 65536:
                header.append(0x80 | 126)
                header.extend(struct.pack("!H", n))
            else:
                header.append(0x80 | 127)
                header.extend(struct.pack("!Q", n))
            header.extend(mask)
            s.sendall(bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

        def ws_recv():
            def rx(n):
                buf = b""
                while len(buf) < n:
                    c = s.recv(n - len(buf))
                    if not c:
                        raise EOFError()
                    buf += c
                return buf
            _, b2 = rx(2)
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack("!H", rx(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", rx(8))[0]
            if b2 & 0x80:
                m = rx(4)
                data = bytes(b ^ m[i % 4] for i, b in enumerate(rx(n)))
            else:
                data = rx(n)
            return json.loads(data.decode("utf-8"))

        ws_send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"clientInfo": {"name": "prisma-installer", "version": "1.0.0"}}})
        while ws_recv().get("id") != 1:
            pass
        ws_send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        ws_send({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "config/batchWrite",
            "params": {
                "edits": [{
                    "keyPath": "hooks.state",
                    "value": updates,
                    "mergeStrategy": "upsert",
                }],
                "reloadUserConfig": True,
            },
        })
        while ws_recv().get("id") != 2:
            pass
    finally:
        s.close()
PY
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
  mkdir -p "$HOME/.claude"
  CLAUDE_MD_FILE="$HOME/.claude/CLAUDE.md"
  if [ ! -f "$CLAUDE_MD_FILE" ] || ! grep -q "<ForPrisma>" "$CLAUDE_MD_FILE" 2>/dev/null; then
    if [ -s "$CLAUDE_MD_FILE" ]; then
      printf '\n\n' >> "$CLAUDE_MD_FILE"
    fi
    cat "$PROJECT_ROOT/plugin/AGENTS.md" >> "$CLAUDE_MD_FILE"
  fi
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
