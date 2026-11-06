#!/bin/bash
# Session signals, turn start and interruptions for every agent.
# Usage: on_turn.sh [codex|claude-code|opencode|muse|antigravity] [event]
# Antigravity hooks carry no hook_event_name or source: both come as arguments.
set -uo pipefail
INPUT="$(cat)"
SUPPORT="$HOME/Library/Application Support/Prisma"
RUNTIME="$SUPPORT/runtime.json"
field() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

SOURCE="${1:-}"
EVENT="$(field '.hook_event_name')"
[ -n "$EVENT" ] || EVENT="${2:-}"
TRANSCRIPT="$(field '.transcript_path')"
[ -n "$TRANSCRIPT" ] || TRANSCRIPT="$(field '.transcriptPath')"
# A Codex transcript identifies Codex even through an older or shared hook.
# Older Claude Code hooks pass no argument; their transcript identifies them.
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && head -n 5 "$TRANSCRIPT" 2>/dev/null | grep -q '"type":"session_meta"'; then
  SOURCE=codex
elif [ -z "$SOURCE" ] && [ -n "$TRANSCRIPT" ]; then
  SOURCE=claude-code
fi

# Every session of these agents has its own orb, which waits between turns.
case "$SOURCE" in
  codex|claude-code|opencode|muse|antigravity) PERSISTENT=1 ;;
  *) PERSISTENT=0 ;;
esac
case "$EVENT" in
  SessionStart) [ "$PERSISTENT" = 1 ] || { echo '{}'; exit 0; }; ENDPOINT=session/start ;;
  SessionEnd) if [ "$PERSISTENT" = 1 ]; then ENDPOINT=session/end; else ENDPOINT=interrupt; fi ;;
  UserPromptSubmit|PreInvocation) ENDPOINT=thinking ;;
  Interrupt|StopFailure) ENDPOINT=interrupt ;;
  *) echo '{}'; exit 0 ;;
esac
SESSION="$(field '.session_id')"
[ -n "$SESSION" ] || SESSION="$(field '.conversationId')"

# The Claude Code window's process lets Prisma remove its orb when the window
# closes and keep the orb in place when it moves on to a new conversation.
# OpenCode runs its hooks in a shared service: Prisma finds its windows
# itself and matches sessions to them by folder.
agent_pid() {
  local pid="$PPID" name
  for _ in 1 2 3 4 5; do
    name="$(ps -o comm= -p "$pid" 2>/dev/null)"
    name="${name##*/}"
    case "${name#-}" in
      sh|bash|zsh|dash|ksh|fish|tcsh|csh|env) pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" ;;
      *) break ;;
    esac
    [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || return 0
  done
  printf '%s' "$pid"
}
PID=""
WATCH=""
FOLDER=""
case "$SOURCE" in
  claude-code|muse|antigravity)
    case "$ENDPOINT" in
      session/start|thinking) PID="$(agent_pid)" ;;
    esac
    ;;
esac
if [ "$SOURCE" = claude-code ] && [ "$ENDPOINT" = thinking ]; then
  # Claude Code has no interrupt hook; Prisma notices Escape in the transcript.
  WATCH="$TRANSCRIPT"
fi
case "$SOURCE" in
  opencode) FOLDER="$(field '.directory')" ;;
  muse) FOLDER="$(field '.cwd')" ;;
  antigravity) FOLDER="$(field '.workspacePaths[0]')" ;;
esac
case "$PID" in *[!0-9]*) PID="" ;; esac

# Only launch on start; interruption must not start a new instance.
if { [ "$ENDPOINT" = thinking ] || [ "$ENDPOINT" = session/start ]; } && [ ! -f "$RUNTIME" ]; then
  open -a Prisma >/dev/null 2>&1 || true
fi
for _ in $(seq 1 20); do
  if [ -f "$RUNTIME" ]; then
    PORT="$(jq -r '.port // empty' "$RUNTIME" 2>/dev/null)"
    TOKEN="$(jq -r '.token // empty' "$RUNTIME" 2>/dev/null)"
    if [ -n "$PORT" ] && [ -n "$TOKEN" ] && curl -fsS --max-time 0.3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      PAYLOAD="$(jq -n --arg session "$SESSION" --arg source "$SOURCE" --arg pid "$PID" \
        --arg transcript "$WATCH" --arg folder "$FOLDER" '
        {session_id: $session, source: $source}
        + (if $pid != "" then {pid: ($pid | tonumber)} else {} end)
        + (if $transcript != "" then {transcript_path: $transcript} else {} end)
        + (if $folder != "" then {directory: $folder} else {} end)')"
      curl -fsS --max-time 1 -X POST "http://127.0.0.1:$PORT/$ENDPOINT" -H "Content-Type: application/json" -H "X-Prisma-Token: $TOKEN" --data-binary "$PAYLOAD" >/dev/null 2>&1 || true
      break
    fi
  fi
  { [ "$ENDPOINT" = interrupt ] || [ "$ENDPOINT" = session/end ]; } && break
  if [ "${LAUNCHED:-0}" = 0 ]; then open -a Prisma >/dev/null 2>&1 || true; LAUNCHED=1; fi
  sleep 0.2
done
echo '{}'
