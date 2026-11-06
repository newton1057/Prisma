#!/bin/bash
# Prisma: hook Stop compatible con Codex, Claude Code, OpenCode, Muse Code y Antigravity.
# Uso: on_stop.sh [codex|claude-code|opencode|muse|antigravity] [evento]
set -uo pipefail

INPUT="$(cat)"
SUPPORT="$HOME/Library/Application Support/Prisma"
RUNTIME="$SUPPORT/runtime.json"
LOG="$SUPPORT/hook.log"
SOURCE_HINT="${1:-}"
EVENT_HINT="${2:-}"

mkdir -p "$SUPPORT"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

if ! command -v jq >/dev/null 2>&1; then
  log "jq no está disponible; no se puede procesar el hook."
  echo '{}'
  exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
[ -n "$EVENT" ] || EVENT="$EVENT_HINT"
[ -n "$EVENT" ] || EVENT="Stop"
if [ "$EVENT" != "Stop" ] && [ "$EVENT" != "PreToolUse" ] && [ "$EVENT" != "PermissionRequest" ]; then
  if [ "$SOURCE_HINT" = "antigravity" ] && [ "$EVENT" = "PreToolUse" ]; then
    echo '{"decision":"allow"}'
  else
    echo '{}'
  fi
  exit 0
fi

# Antigravity deniega una herramienta cuando el hook no responde con una decisión.
respond() {
  if [ "$SOURCE_HINT" = "antigravity" ] && [ "$EVENT" = "PreToolUse" ]; then
    echo '{"decision":"allow"}'
  else
    echo '{}'
  fi
}

# 1. Intentar leer last_assistant_message directo (Codex, OpenCode, Muse Code y
#    versiones nuevas de Claude Code)
MESSAGE="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
SOURCE="$SOURCE_HINT"
[ -n "$SOURCE" ] || SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)"

detect_source_from_transcript() {
  local path="$1"
  if [ -n "$path" ] && [ -f "$path" ]; then
    if head -n 5 "$path" 2>/dev/null | grep -q '"type":"session_meta"'; then
      printf 'codex'
    else
      printf 'claude-code'
    fi
    return 0
  fi
  printf '%s' "$SOURCE"
}

# Claude supplies a direct final message too; identify it from its transcript
# even when transcript parsing is not needed to obtain the text. A source hint
# from the command line (Muse Code, Antigravity) is never overridden.
if [ -z "$SOURCE" ] && [ -z "$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)" ]; then
  SOURCE="$(detect_source_from_transcript "$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)")"
fi

# Devuelve el bloque <ForPrisma> del mensaje de asistente inmediatamente anterior
# a una pregunta o solicitud de permiso (sin llamadas a herramientas de por medio)
# únicamente si formula una pregunta (contiene ? o ¿). Así evitamos leer mensajes
# de estado (<ForPrisma> en commentary de Codex) que no corresponden a la pregunta.
recent_question_forprisma_text() {
  local path="$1"
  [ -f "$path" ] || return 0

  local text=""
  if head -n 5 "$path" 2>/dev/null | grep -q '"type":"session_meta"'; then
    # Codex: solo tomar el último response_item relevante si es un mensaje de assistant
    text="$(tail -n 60 "$path" 2>/dev/null | jq -rs '
      [ .[]
        | select(.type == "response_item")
        | .payload
        | select(.type == "message" or .type == "function_call_output" or .type == "custom_tool_call_output")
      ]
      | last
      | if . != null and .type == "message" and .role == "assistant" then
          ([ .content[]? | select(.type == "output_text" or .type == "text") | .text ] | join("\n"))
        else
          ""
        end
    ' 2>/dev/null || true)"
  else
    # Claude Code: última línea de assistant si no hubo tool_result después
    text="$(tail -n 25 "$path" 2>/dev/null | jq -rs '
      [ .[] | select(.type == "assistant" or .type == "user" or (.message.role? != null)) ]
      | last
      | if (.message.role? // .type) == "assistant" then
          ([ .message.content[]? | select(.type == "text") | .text ] | join("\n"))
        else
          ""
        end
    ' 2>/dev/null || true)"
  fi

  if [ -n "$text" ] && printf '%s' "$text" | grep -qiE '<\s*ForPri(s)?ma\s*>' && printf '%s' "$text" | grep -qE '[?¿]'; then
    printf '%s' "$text"
  fi
}

extract_questions_from_tool_input() {
  printf '%s' "$INPUT" | jq -r '
    (.tool_input // {})
    | if type == "string" then (fromjson? // {}) else . end
    | if (.questions | type) == "array" and (.questions | length) > 0 then
        .questions
        | map(
            ((.question // .title // .header // "") | tostring | sub("^\\s+|\\s+$"; "")) as $q
            | ((.options // [])
                | map(
                    if type == "string" then .
                    elif type == "object" then (.label // .title // .value // "")
                    else ""
                    end
                    | tostring
                    | sub("\\s*\\((Recommended|Recomendado)\\)\\s*"; "")
                    | sub("^\\s+|\\s+$"; "")
                  )
                | map(select(length > 0))
              ) as $opts
            | if ($q | length) == 0 then ""
              elif ($opts | length) > 0 then "\($q) Opciones: \($opts | join(", "))."
              else $q
              end
          )
        | map(select(length > 0))
        | join(" ")
      elif (.message | type) == "string" and (.message | length) > 0 then
        .message
      else
        ""
      end
  ' 2>/dev/null || true
}

# 1b. Si es PreToolUse de una herramienta de preguntas
if [ "$EVENT" = "PreToolUse" ] && [ "$SOURCE" != "antigravity" ]; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
  case "$TOOL_NAME" in
    AskUserQuestion|request_user_input|request_user_input_async|send_user_message_async|send_message_to_user_async|question)
      TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
      if [ -z "$SOURCE" ]; then
        SOURCE="codex"
        [ "$TOOL_NAME" = "AskUserQuestion" ] && SOURCE="claude-code"
        SOURCE="$(detect_source_from_transcript "$TRANSCRIPT_PATH")"
        [ -n "$SOURCE" ] || SOURCE="codex"
      fi

      QUESTIONS_TEXT="$(extract_questions_from_tool_input)"
      RECENT_TEXT=""
      if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
        RECENT_TEXT="$(recent_question_forprisma_text "$TRANSCRIPT_PATH")"
      fi

      if [ -n "$QUESTIONS_TEXT" ] && [ "$QUESTIONS_TEXT" != "null" ]; then
        MESSAGE="$QUESTIONS_TEXT"
      elif [ -n "$RECENT_TEXT" ]; then
        MESSAGE="$RECENT_TEXT"
      fi
      ;;
    *)
      respond
      exit 0
      ;;
  esac
fi

# 1c. Si es PermissionRequest (Codex, Claude Code o Muse Code pide confirmación/permiso al usuario)
if [ "$EVENT" = "PermissionRequest" ]; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
  TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  if [ -z "$SOURCE" ]; then
    SOURCE="$(detect_source_from_transcript "$TRANSCRIPT_PATH")"
    [ -n "$SOURCE" ] || SOURCE="codex"
  fi

  QUESTIONS_TEXT="$(extract_questions_from_tool_input)"
  if [ -n "$QUESTIONS_TEXT" ] && [ "$QUESTIONS_TEXT" != "null" ]; then
    MESSAGE="$QUESTIONS_TEXT"
  else
    PERM_DESC="$(printf '%s' "$INPUT" | jq -r '
      (.tool_input // {})
      | if type == "string" then (fromjson? // {}) else . end
      | (.description // .justification // .reason // "")
      | tostring
      | sub("^\\s+|\\s+$"; "")
    ' 2>/dev/null || true)"

    if [ -n "$PERM_DESC" ] && [ "$PERM_DESC" != "null" ]; then
      case "$PERM_DESC" in
        network-access\ *)
          MESSAGE="¿Me permites acceso de red para continuar?"
          ;;
        *)
          MESSAGE="$PERM_DESC"
          ;;
      esac
    fi
  fi

  if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
      MESSAGE="$(recent_question_forprisma_text "$TRANSCRIPT_PATH")"
    fi
  fi

  if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
    case "$TOOL_NAME" in
      apply_patch|Edit|Write)
        MESSAGE="¿Me permites aplicar los cambios en los archivos?"
        ;;
      Bash|write_stdin)
        MESSAGE="¿Me permites ejecutar este comando en la terminal?"
        ;;
      request_permissions)
        MESSAGE="¿Me permites conceder los permisos solicitados para continuar?"
        ;;
      *)
        MESSAGE="¿Me permites continuar con esta acción?"
        ;;
    esac
  fi
fi

# 1d. Antigravity: el payload usa camelCase y no trae hook_event_name ni
#     last_assistant_message; Stop se lee del transcript y PreToolUse de la
#     llamada a ask_question / ask_permission.
if [ "$SOURCE" = "antigravity" ]; then
  if [ "$EVENT" = "PreToolUse" ]; then
    MESSAGE="$(printf '%s' "$INPUT" | jq -r '
      (.toolCall.args // {}) as $args
      | (.toolCall.name // "") as $name
      | if $name == "ask_question" then
          ($args.questions // [])
          | map(
              ((.question // "") | tostring) as $q
              | ((.options // []) | map(
                   (if type == "string" then . else (.label // .title // .value // "") end)
                   | tostring
                   | sub("^\\s*\\((Recommended|Recomendado)\\)\\s*"; "")
                   | sub("^\\s+|\\s+$"; "")
                 ) | map(select(length > 0))) as $opts
              | if ($q | length) == 0 then ""
                elif ($opts | length) > 0 then "\($q) Opciones: \($opts | join(", "))."
                else $q end
            )
          | map(select(length > 0))
          | join(" ")
        elif $name == "ask_permission" then
          (($args.Reason // $args.reason // "") | tostring | sub("^\\s+|\\s+$"; ""))
          | if length > 0 then . else "¿Me permites continuar con esta acción?" end
        else "" end
    ' 2>/dev/null || true)"
  else
    ERROR_TEXT="$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null)"
    if [ -z "$ERROR_TEXT" ] && { [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; }; then
      AGY_TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcriptPath // empty' 2>/dev/null)"
      if [ -n "$AGY_TRANSCRIPT" ] && [ -f "$AGY_TRANSCRIPT" ]; then
        for _ in 1 2 3; do
          MESSAGE="$(tail -n 200 "$AGY_TRANSCRIPT" 2>/dev/null | jq -rs '
            [ .[] | select(.source == "MODEL" and .type == "PLANNER_RESPONSE") ]
            | last
            | if . != null and (.content | type) == "string" then .content else "" end
          ' 2>/dev/null || true)"
          if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "null" ]; then
            break
          fi
          sleep 0.15
        done
      fi
    fi
  fi
fi

# 2. Si viene vacío en Stop, extraer el último mensaje de assistant desde transcript_path (Claude Code o Codex JSONL)
if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    if [ -z "$SOURCE" ]; then
      SOURCE="$(detect_source_from_transcript "$TRANSCRIPT_PATH")"
      [ -n "$SOURCE" ] || SOURCE="codex"
    fi
    for _ in 1 2 3; do
      if [ "$SOURCE" = "codex" ]; then
        MESSAGE="$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | jq -rs '
          map(select(.type == "response_item"
                     and .payload.type == "message"
                     and .payload.role == "assistant")
              | .payload.content[]?
              | select(.type == "output_text" or .type == "text")
              | .text)
          | map(select(length > 0)) | last // empty
        ' 2>/dev/null || true)"
      else
        LAST_LINES="$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 100 || true)"
        if [ -n "$LAST_LINES" ]; then
          MESSAGE="$(printf '%s\n' "$LAST_LINES" | jq -rs '
            map(.message.content[]? | select(.type == "text") | .text) | map(select(length > 0)) | last // empty
          ' 2>/dev/null || true)"
        fi
      fi
      if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "null" ]; then
        break
      fi
      sleep 0.15
    done
  fi
fi

if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  # A completed turn without speech must not leave the thinking orb visible.
  if [ "$EVENT" = "Stop" ] && [ -f "$SUPPORT/on_turn.sh" ]; then
    printf '%s' "$INPUT" | jq '.hook_event_name = "Interrupt"' | bash "$SUPPORT/on_turn.sh" "$SOURCE" >/dev/null 2>&1 || true
  fi
  log "Stop recibido sin texto de asistente (${SOURCE}, ${EVENT})."
  respond
  exit 0
fi

# 3. Si la respuesta incluye un bloque <ForPrisma>...</ForPrisma> (o <ForPrima> / "For Prisma:"),
#    extraer solo ese bloque y limpiarlo de URLs, rutas y Markdown para voz.
EXTRACTED_FOR_PRISMA="$(printf '%s' "$MESSAGE" | perl -CS -0777 -ne '
  my $text = $_;
  $text =~ s/\r\n/\n/g;
  my $chosen = "";

  my $without_code = $text;
  $without_code =~ s/```[\s\S]*?```/ /g;
  $without_code =~ s/~~~[\s\S]*?~~~/ /g;
  $without_code =~ s/`[^`\n]*`/ /g;

  if ($without_code =~ /[\s\S]*<[ \t]*ForPri(?:s)?ma[ \t]*>([\s\S]*?)(?:<[ \t]*\/[ \t]*ForPri(?:s)?ma[ \t]*>|\z)/i) {
    $chosen = $1;
  }

  if ($chosen !~ /\S/) {
    my @lines = split(/\n/, $text);
    for (my $i = $#lines; $i >= 0; $i--) {
      if ($lines[$i] =~ /^\s*(?:#{1,6}\s*)?(?:\*\*)?For\s*Pri(?:s)?ma\b/i) {
        my $inline = $lines[$i];
        $inline =~ s/^\s*(?:#{1,6}\s*)?(?:\*\*)?For\s*Pri(?:s)?ma(?:\*\*)?\s*:?\s*//i;
        my $rest = $i < $#lines ? join("\n", @lines[($i + 1) .. $#lines]) : "";
        $chosen = join("\n", grep { length($_) > 0 } ($inline, $rest));
        last;
      }
    }
  }

  $chosen = $text if $chosen !~ /\S/;

  # Limpieza para voz: sin bloques de código, URLs, rutas locales ni Markdown
  $chosen =~ s/```[\s\S]*?```/ /g;
  $chosen =~ s/~~~[\s\S]*?~~~/ /g;
  $chosen =~ s/!\[([^\]]*)\]\([^)]*\)/$1/g;
  $chosen =~ s/\[([^\]]+)\]\([^)]*\)/$1/g;
  $chosen =~ s/<?https?:\/\/[^\s)>]+>?/ /gi;
  $chosen =~ s/\bwww\.[^\s)>]+/ /gi;
  $chosen =~ s/(?:^|\s)(?:~\/|\/(?:Users|Applications|Library|System|private|tmp|var)\/)[^\s,;)]*/ /gm;
  $chosen =~ s/`([^`]*)`/$1/g;
  $chosen =~ s/^\s{0,3}#{1,6}\s+//gm;
  $chosen =~ s/^\s{0,3}>\s?//gm;
  $chosen =~ s/^\s*[-*+]\s+//gm;
  $chosen =~ s/^\s*\d+[.)]\s+//gm;
  $chosen =~ s/(\*\*|__)(.*?)\1/$2/g;
  $chosen =~ s/(\*|_)(.*?)\1/$2/g;
  $chosen =~ s/~~(.*?)~~/$1/g;
  $chosen =~ s/<\/?\s*ForPri(?:s)?ma\s*>/ /gi;
  $chosen =~ s/[ \t]+/ /g;
  $chosen =~ s/\n{3,}/\n\n/g;
  $chosen =~ s/^\s+|\s+$//g;

  print $chosen if length($chosen) > 0;
' 2>/dev/null || true)"

if [ -n "$EXTRACTED_FOR_PRISMA" ]; then
  MESSAGE="$EXTRACTED_FOR_PRISMA"
fi

[ -n "$SOURCE" ] || SOURCE="codex"

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // empty' 2>/dev/null)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SESSION" ] || SESSION="$(printf '%s' "$INPUT" | jq -r '.conversationId // empty' 2>/dev/null)"

# Process of the Claude Code, Muse Code or Antigravity window, so the reply
# reaches the orb of that window (see on_turn.sh). OpenCode replies are matched
# by their folder.
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
AGENT_PID=""
case "$SOURCE" in
  claude-code|muse|antigravity) AGENT_PID="$(agent_pid)" ;;
esac
case "$AGENT_PID" in *[!0-9]*) AGENT_PID="" ;; esac

# 4. Evitar hablar dos veces el mismo texto seguido dentro de la misma sesión
#    (por ejemplo si PreToolUse y PermissionRequest o Stop disparan sobre la misma pregunta).
DEDUPE_FILE="$SUPPORT/tmp/last_spoken.json"
mkdir -p "$SUPPORT/tmp"
NOW_TS="$(date +%s)"
SIGNATURE="${SESSION}|${MESSAGE}"
if [ -f "$DEDUPE_FILE" ]; then
  PREV_SIG="$(jq -r '.signature // empty' "$DEDUPE_FILE" 2>/dev/null || true)"
  PREV_TS="$(jq -r '.timestamp // 0' "$DEDUPE_FILE" 2>/dev/null || echo 0)"
  if [ "$PREV_SIG" = "$SIGNATURE" ] && [ $((NOW_TS - PREV_TS)) -lt 45 ]; then
    log "Aviso duplicado omitido (${SOURCE}, ${EVENT})."
    if [ "$EVENT" = "Stop" ] && [ -f "$SUPPORT/on_turn.sh" ]; then
      printf '%s' "$INPUT" | jq '.hook_event_name = "Interrupt"' | bash "$SUPPORT/on_turn.sh" "$SOURCE" >/dev/null 2>&1 || true
    fi
    respond
    exit 0
  fi
fi
jq -n --arg sig "$SIGNATURE" --argjson ts "$NOW_TS" '{signature: $sig, timestamp: $ts}' > "$DEDUPE_FILE" 2>/dev/null || true

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
  respond
  exit 0
fi

PAYLOAD="$(jq -n \
  --arg text "$MESSAGE" \
  --arg cwd "$CWD" \
  --arg session "$SESSION" \
  --arg source "$SOURCE" \
  --arg pid "$AGENT_PID" \
  '{text: $text, cwd: $cwd, session_id: $session, source: $source}
   + (if $pid != "" then {pid: ($pid | tonumber)} else {} end)')"

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
respond
exit 0
