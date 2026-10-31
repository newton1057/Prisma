# Investigación: plugin Prisma (Codex, Claude Code y OpenCode) + overlay tipo Siri AI iOS 27

Fecha: 2026-10-29
Equipo: macOS 26.4, Apple Silicon, 16 GB RAM
Codex CLI: 0.165.0

## 1. Engancharse al final de un turno

### 1.1 `notify` (config.toml)

`~/.codex/config.toml` acepta:

```toml
notify = ["python3", "/ruta/notify.py"]
```

Codex ejecuta ese programa cuando emite `agent-turn-complete` y le pasa un JSON
con `last-assistant-message`, `thread-id`, `turn-id`, `cwd` e `input-messages`.

Ventaja: simple. Desventaja: **solo admite un comando**. En este equipo ya está
ocupado por Codex Computer Use (`SkyComputerUseClient turn-ended`), así que
reemplazarlo rompería esa integración. Se descartó.

### 1.2 Hook `Stop` de usuario (solución adoptada)

`~/.codex/hooks.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/Users/newton1057/Library/Application Support/Prisma/on_stop.sh\"",
            "timeout": 10,
            "statusMessage": "Prisma"
          }
        ]
      }
    ]
  }
}
```

El evento `Stop` se dispara al terminar el turno principal y recibe:

```json
{
  "session_id": "thr_...",
  "turn_id": "...",
  "cwd": "/ruta/del/proyecto",
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "Texto final del asistente..."
}
```

El script `on_stop.sh` lee el JSON, extrae `last_assistant_message` (o lee `transcript_path` en Claude Code) y hace un
`POST` a la app local. Es síncrono y tarda milisegundos si la app ya está
abierta. Si no lo está, la lanza y espera hasta 5 s.

### 1.3 Hallazgo: los hooks del plugin no se ejecutaron en `codex exec`

Se empaquetó el plugin `prisma` con `hooks/hooks.json` y se instaló con
`codex plugin add`. El plugin aparece como `installed, enabled`, pero durante
`codex exec` **no se ejecutó su hook `Stop`**, ni siquiera con
`--dangerously-bypass-hook-trust`. Un hook equivalente en
`~/.codex/hooks.json` sí se ejecutó (`hook: Stop Completed`).

Conclusión: en Codex CLI 0.165.0 el mecanismo fiable es el hook de usuario.
El plugin se conserva para:
- la skill `prisma`;
- la app de escritorio de Codex y Claude Code, donde los hooks de plugin sí están soportados;
- la distribución del paquete.

La app deduplica peticiones con el mismo `session_id` y texto en una ventana de
2 s, así que si ambos hooks llegaran a ejecutarse no hablaría dos veces.

### 1.4 Estructura del plugin Prisma

```
plugin/
├── plugin.json
├── .codex-plugin/plugin.json
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── opencode/prisma.ts
├── scripts/on_stop.sh
└── skills/prisma/SKILL.md
```

Se expone con marketplaces locales en
`~/Desktop/Prisma/.agents/plugins/marketplace.json` y `~/Desktop/Prisma/.claude-plugin/marketplace.json`, y se instala con:

```bash
codex plugin marketplace add ~/Desktop/Prisma
codex plugin add prisma@prisma-local
claude plugin marketplace add ~/Desktop/Prisma
claude plugin install prisma@prisma-local
```

Los hooks no gestionados hay que confiarlos una vez con `/hooks`.

## 2. Overlay flotante sobre Chrome/YouTube en pantalla completa

Un plugin no puede dibujar sobre otras apps: el overlay es una app nativa aparte.

La pieza clave es un `NSPanel` de AppKit con:

- `styleMask = [.borderless, .nonactivatingPanel]`
- `isOpaque = false`, `backgroundColor = .clear`
- `level = .screenSaver` (por encima de casi todo)
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
- `orderFrontRegardless()` para no robar el foco
- `ignoresMouseEvents = true` para que los clics atraviesen el orbe

`.fullScreenAuxiliary` permite que la ventana acompañe a un espacio en pantalla
completa, que es el caso de YouTube en Chrome. El panel no activa la app, así
que el vídeo sigue reproduciéndose y el teclado sigue en Chrome.

La animación usa SwiftUI:

- Lente de cristal líquido (`Liquid Glass`) con horizonte prismático curvado.
- Capas con `blur`, `blendMode(.plusLighter)` y ondas reactivas a la voz.
- `TimelineView(.animation)` a 60 fps.
- Se desliza desde el borde superior debajo del Notch.

La app vive en la barra de menús (`NSStatusItem`) y se abre sola desde el hook.

## 3. Arquitectura final

1. **Prisma.app** (SwiftUI + AppKit):
   - Servidor HTTP local en `127.0.0.1` con token.
   - Overlay `NSPanel` arriba al centro (debajo del Notch).
   - Edge Neural TTS (`en-US-AvaMultilingualNeural`) y Piper local con chunking y reproducción en streaming.
   - Fallback a `AVSpeechSynthesizer` (Apple Paulina).
   - Ajustes: motor, lectura, velocidad, posición.

2. **Hooks y Plugins (Codex, Claude Code y OpenCode)**:
   - Codex: `~/.codex/hooks.json` + `prisma@prisma-local` → `on_stop.sh` → `POST /speak`.
   - Claude Code: `prisma@prisma-local` → `on_stop.sh` (leyendo `transcript_path`) → `POST /speak`.
   - OpenCode: `~/.config/opencode/plugins/prisma.ts` + `~/.config/opencode/skills/prisma/SKILL.md`.

3. **Instalador (`install.sh`)**:
   - Compila `Prisma.app` y la instala en `~/Applications/Prisma.app`.
   - Copia Piper y `edge-tts` a `~/Library/Application Support/Prisma/`.
   - Instala el hook y los plugins en Codex, Claude Code y OpenCode.

## 4. Voz

Se verificaron las voces del sistema y Piper. Piper
`es_MX-claude-high` sintetizó 4,78 s de audio en 1,18 s (incluyendo arranque),
sin GPU y sin red. Es la voz principal. Apple Paulina queda como fallback.

Ver `docs/voces.md` para la comparativa completa.

## 5. Fuentes

- Config avanzada de Codex (`notify`):
  https://learn.chatgpt.com/docs/config-file/config-advanced
- Hooks de Codex:
  https://developers.openai.com/codex/hooks
- Plugins de Codex:
  https://developers.openai.com/plugins/build/plugins
- Piper:
  https://github.com/rhasspy/piper
- Voces Piper:
  https://huggingface.co/rhasspy/piper-voices
- Kokoro 82M:
  https://huggingface.co/hexgrad/Kokoro-82M
- Supertonic 3:
  https://huggingface.co/Supertone/supertonic-3
