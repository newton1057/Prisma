# Research: Prisma integrations and the macOS overlay

Date: 2026-10-29
Test machine: macOS 26.4, Apple Silicon, 16 GB RAM
Codex CLI: 0.165.0

These are historical research notes. For the current Windows implementation, see the [Windows guide](windows.md).

## 1. Detecting the end of a turn

### 1.1 `notify` in `config.toml`

`~/.codex/config.toml` accepts a command such as:

```toml
notify = ["python3", "/path/to/notify.py"]
```

Codex runs it on `agent-turn-complete`, passing JSON with `last-assistant-message`, `thread-id`, `turn-id`, `cwd`, and `input-messages`.

This approach is simple but supports **only one command**. On the test machine it was already used by Codex Computer Use (`SkyComputerUseClient turn-ended`), so replacing it would break that integration. It was not adopted.

### 1.2 User-level `Stop` hook

The adopted approach uses `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/Users/example/Library/Application Support/Prisma/on_stop.sh\"",
            "timeout": 10,
            "statusMessage": "Prisma"
          }
        ]
      }
    ]
  }
}
```

The event fires at the end of the main turn and receives data such as:

```json
{
  "session_id": "thr_...",
  "turn_id": "...",
  "cwd": "/path/to/project",
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "Final assistant response..."
}
```

`on_stop.sh` reads the JSON, extracts `last_assistant_message` or reads `transcript_path` for Claude Code, and posts to the local app. It normally takes milliseconds if the app is already open; otherwise it launches the app and waits up to five seconds.

### 1.3 Finding: plugin hooks did not run in `codex exec`

The `prisma` plugin was packaged with `hooks/hooks.json` and installed with `codex plugin add`. It appeared as installed and enabled, but its `Stop` hook did not run during `codex exec`, even with `--dangerously-bypass-hook-trust`. An equivalent user hook in `~/.codex/hooks.json` did run (`hook: Stop Completed`).

For Codex CLI 0.165.0, the user hook was therefore the reliable mechanism. The plugin remains useful for the Prisma skill, desktop Codex and Claude Code plugin support, and package distribution. The app deduplicates requests with the same `session_id` and text within two seconds, avoiding duplicate speech if both hooks run.

### 1.4 Plugin layout

```text
plugin/
├── plugin.json
├── .codex-plugin/plugin.json
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── opencode/prisma.ts
├── scripts/on_stop.sh
└── skills/prisma/SKILL.md
```

Local marketplaces are exposed in `~/Desktop/Prisma/.agents/plugins/marketplace.json` and `~/Desktop/Prisma/.claude-plugin/marketplace.json`. Installation commands:

```bash
codex plugin marketplace add ~/Desktop/Prisma
codex plugin add prisma@prisma-local
claude plugin marketplace add ~/Desktop/Prisma
claude plugin install prisma@prisma-local
```

Unmanaged hooks must be trusted through `/hooks`.

## 2. Floating macOS overlay

A plugin cannot draw over other applications, so the overlay is a separate native app. Its AppKit `NSPanel` uses:

- `styleMask = [.borderless, .nonactivatingPanel]`
- `isOpaque = false` and `backgroundColor = .clear`
- `level = .screenSaver`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
- `orderFrontRegardless()` to avoid taking focus
- `ignoresMouseEvents = true` so clicks pass through

`.fullScreenAuxiliary` allows the window to join a full-screen space, such as Chrome playing a YouTube video. The panel does not activate the app, so video and keyboard focus remain in Chrome.

The SwiftUI animation uses a liquid-glass lens with a curved prismatic horizon, blur and `blendMode(.plusLighter)` layers, audio-reactive waves, and a 60 fps `TimelineView(.animation)`. It slides down from the top edge below the notch. The app lives in the menu bar using `NSStatusItem` and can be launched by the hook.

## 3. macOS architecture

1. **Prisma.app** (SwiftUI + AppKit): authenticated HTTP server on `127.0.0.1`; floating `NSPanel`; Edge Neural TTS and local Piper with chunking and streaming playback; `AVSpeechSynthesizer` fallback; settings for voice, reading mode, speed, and position.
2. **Hooks and plugins:** Codex uses `~/.codex/hooks.json` and `prisma@prisma-local`; Claude Code uses the local plugin and transcript; OpenCode uses `~/.config/opencode/plugins/prisma.ts` and its Prisma skill. Hooks send `POST /speak` to the app.
3. **`install.sh`:** builds and installs `Prisma.app` in `~/Applications`, copies Piper and `edge-tts` to Application Support, and installs hooks and plugins.

## 4. Voice findings

Piper `es_MX-claude-high` synthesized 4.78 seconds of audio in 1.18 seconds, including startup, without a GPU or network. Piper was originally selected as the primary voice, with Apple Paulina as a fallback. Edge Ava Multilingual is now the default. See the [voice comparison](voces.md).

## 5. Sources

- [Codex advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [Codex hooks](https://developers.openai.com/codex/hooks)
- [Codex plugins](https://developers.openai.com/plugins/build/plugins)
- [Piper](https://github.com/rhasspy/piper) and [Piper voices](https://huggingface.co/rhasspy/piper-voices)
- [Kokoro 82M](https://huggingface.co/hexgrad/Kokoro-82M)
- [Supertonic 3](https://huggingface.co/Supertone/supertonic-3)
