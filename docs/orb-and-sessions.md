# Orb animation and session orbs on macOS

Date: 2026-11-05
Status: implemented and verified on macOS 27.2 (Apple Silicon) with Codex, Claude Code and OpenCode 2.2.5; Muse Code 1.4 and Antigravity CLI 1.3 integration added (hook mechanics verified, model replies pending billing). See the [handoff notes](handoff.md).

This document describes how the macOS orb is drawn and animated, how the row of session orbs is laid out, and how each agent's sessions reach their orb. User-facing behavior is in the [README](../README.md#settings).

## 1. What the user sees

- **One orb per agent session.** Every Codex, Claude Code, OpenCode, Muse Code and Antigravity session has its own orb. The orbs sit side by side at the top of one screen and wrap into more rows if needed.
- **Three states of the same light:**
  - *Waiting*: broad, slowly turning folds of warm, white and blue light.
  - *Thinking*: the light closes into a thin, softly spinning ring of iridescent bands.
  - *Voice*: the light opens into a horizon arc (dark sky above, glass below) that reacts to the audio.
- **Transitions bend one beam.** The ring opens at the bottom and unrolls into the horizon; the horizon curls back into a loop. Nothing cross-fades between separate drawings.
- **Liquid entrances and exits.** An orb grows from a droplet at the screen edge and shrinks back into it. When an orb arrives or leaves, its neighbours slide to their new places.
- **Other sources** (for example *Probar voz* in the menu) still use the single overlay orb, which has no waiting state and hides after speaking.

## 2. Files

| File | Role |
|---|---|
| `app/Sources/Prisma/OverlayView.swift` | Animation model (`OverlayModel`, `SmoothBlend`, `OrbMotion`), the orb view (`SiriLiquidGlassOrbView`) and the beam (`PrismaBeam`). |
| `app/Sources/Prisma/OverlayController.swift` | One borderless panel per orb: show and hide, position in the row, sliding. |
| `app/Sources/Prisma/AppDelegate.swift` | Session registry: which orb belongs to which session, process monitors, speech queue. |
| `app/Sources/Prisma/AgentConnections.swift` | Connects Prisma with Codex, Claude Code, OpenCode, Muse Code and Antigravity from Ajustes: status, hooks, plugins, Codex hook trust. |
| `app/Sources/Prisma/HTTPServer.swift` | Local API used by the hooks. |
| `app/Sources/Prisma/CodexSessionsMonitor.swift` | `ps` snapshot; detects `codex resume <id>` clients. |
| `app/Sources/Prisma/ClaudeCodeWindows.swift` | Detects open Claude Code windows (and a session named with `--resume`). |
| `app/Sources/Prisma/OpenCodeWindows.swift` | Detects open OpenCode windows and their folders. |
| `app/Sources/Prisma/MuseWindows.swift` | Detects open Muse Code windows (and a session named with a UUID). |
| `app/Sources/Prisma/AntigravityWindows.swift` | Detects open Antigravity CLI windows (and a `--conversation` UUID). |
| `plugin/scripts/on_turn.sh` | Session start and end, turn start, interruption. |
| `plugin/scripts/on_stop.sh` | Turn completion and questions: extracts the `<ForPrisma>` text and sends it to `/speak`. |
| `plugin/hooks/hooks.json` | Claude Code plugin hooks (`claude-code` argument). |
| `plugin/opencode/prisma.ts` | OpenCode plugin. |
| `install.sh` | Builds and installs the app, scripts, and the integrations it finds (Codex, Claude Code, OpenCode, Muse Code, Antigravity). |
| `tools/orb-renderer/` | Offline frame-by-frame renderer for the animation (section 8.2). |

## 3. Animation model

### 3.1 States and pose weights

`OverlayModel` turns its published flags into a target pose: `isThinking` wins, then `isSpeaking`, then waiting if `hasIdleState`, otherwise voice. The pose is three weights `(voice, thinking, idle)` that always add up to one; `frame(at:)` returns them in an `OrbFrame` together with the other animated values.

| Target | Duration |
|---|---|
| Thinking | 1.15 s |
| Voice | 1.05 s |
| Waiting | 1.4 s |
| Talking energy (`speaking`) | 0.45 s |

`SmoothBlend` is a quintic Hermite blend. A new target restarts the blend from the current value, velocity and acceleration, so an interrupted transition bends smoothly into the next one. For weights (`bounded`), the momentum carried into a new blend is scaled down just enough to keep every weight within 0…1; this only happens on abrupt reversals. A hidden orb (`visible == false`) snaps to its new pose, so it appears directly in its current shape.

`isMorphing` is published while a transition runs; together with `isThinking` and `isSpeaking` it switches the timeline to 60 fps.

### 3.2 Values integrated per frame

`OrbMotion` advances with the real time between frames (capped at 0.1 s):

- `spin`, the colour rotation: 0.03, 0.1035 and 0.038 turns per second for voice, thinking and waiting.
- `sweep`, the bright region travelling around the loop: 0.75, 1.40 and 0.75 rad/s.
- `audio`, the meter smoothed every frame (rise rate 24/s, fall 9/s); the meter itself updates at 30 Hz.

Changing state changes the speeds, never the phases, so the light keeps travelling instead of jumping. Everything else is an analytic function of time.

### 3.3 Frame rate

`TimelineView(.animation(minimumInterval:))` uses **1/90 s** while thinking, speaking or morphing and **1/36 s** otherwise. That gives 60 fps and 30 fps on 60 Hz displays and 60 fps and 30–36 fps on ProMotion displays. Do not use exactly 1/60 s: display jitter then skips about every other frame (measured 31–38 fps). `audioLevel` is deliberately not `@Published`; the timeline reads it, so the 30 Hz meter does not add uneven redraws.

## 4. The orb view

### 4.1 Layers

`SiriLiquidGlassOrbView(frame:)` draws, from back to front:

| Layer | Shown in | Notes |
|---|---|---|
| Drop shadow, aura | all | Static gradients; the aura's opacity follows the energy. |
| `VisualEffectBlur` (`.hudWindow`, behind window) | all | Masked to a circle by `MaskedVisualEffectView`. |
| Smoked glass and lower glow | voice | Removed from the tree when the voice weight is zero. |
| Obsidian interior | all | Masked by `(1 − voice)` plus the sky above the horizon, so the lower glass darkens as the light curls and never flashes. |
| Night sky | voice | Pure black above the horizon, following its waves. |
| Ambient glow | waiting | A static radial gradient moved with `offset`. |
| `PrismaBeamView` | all | The light; the only layer scaled by the breathing. |
| Side reflections, caustics | all / voice | |
| Rim strokes | all | |

### 4.2 The beam (`PrismaBeam`)

The light is one beam with seven bands: two blooms, four spectral bands and an incandescent core. All of them share one centre line:

- **Bend.** The centre line is a circular arc whose total turn is `open·Θv + (1 − open)·2π`, where `Θv = 8·archHeight/198` is the voice horizon and `open = ((voice − 0.1)/0.9)^1.5`. The arc length blends from 198 pt to the loop circumference (ring radius 41.34 pt, breathing ±3.5 %; waiting radius 60.44 pt). The arc's centroid stays in the middle of the glass; at full voice the brightest point sits exactly at the centre.
- **End fade.** While the loop opens, its ends fade before they part (`endFade = smoothstep(0, 0.16, voice)` over the last 14 % of the length). The light retracts from the gap instead of being cut, and closing reverses it.
- **Band offsets** run along the outward normal. The side below the core on the horizon faces the centre of the loop, so bands never cross while the beam bends.
- **Pose features** are offsets weighted by the pose: audio waves and a lens-shaped thickness for voice; ripples, a travelling sweep, a slight ellipse and tilt for thinking; lobes, sliding folds and a thick inner glow for waiting. Loop-only motion is multiplied by `closure²`, so the open arc never wobbles.
- **Colour follows the beam.** Each band is filled with a conic gradient centred on the arc's centre of curvature, with one stop for every fourth outline sample, placed at that sample's actual angle. Colours are blended in premultiplied space: the voice colours of the band, and the shared iridescent palette for thinking (opacity 1) and waiting (0.28). `HaloTheme` provides ten selectable colour palettes (the original Prisma amber/sapphire palette plus nine additional themes), configurable independently per agent (`codexTheme`, `claudeTheme`, `openCodeTheme`, `museTheme`, `antigravityTheme`) in Settings so each agent's orbs have their own halo colours across all three states.
- `outline(_:)` returns the band geometry without drawing it; `tests/test_overlay_motion.swift` uses it to check continuity.

Bloom and spectral bands are drawn in one `Canvas` with two blurred layers (screen blend; blur 9→6 pt and 2.6→0.9 pt from voice to thinking). The core uses a second canvas (plus-lighter, blur 1.2→0.5 pt).

### 4.3 Performance rules

Measured with seven waiting orbs on the main thread (`sample`): CPU went from about 44 % to 25–29 % after these changes. Keep them:

- Never scale or resize `NSVisualEffectView` per frame. A per-frame `scaleEffect` on the glass made it re-render its material and re-apply its mask image on every frame. Only the light breathes.
- Do not reassign `NSVisualEffectView` properties in `updateNSView` unless they changed. `MaskedVisualEffectView` rebuilds its mask only when its size or corner radius changes.
- Prefer animating opacity over gradient colours: a gradient whose colours change every frame is re-encoded, colour space included.
- Remove layers of a pose with no weight (`if frame.voice > 0.001`).
- Pose features with no weight are skipped in `outline(_:)`.

## 5. Row layout and sliding

`OverlayController.position` gives waiting (inactive) orbs a 78 pt slot (scale `0.34`, ~67 pt diameter, opacity `0.50`) and active orbs—thinking, speaking, or hovered by the pointer—a 110 pt slot (scale `0.50`, ~99 pt diameter, opacity `0.95`). Both states use a translucent smoked-glass interior and softened backdrop blur so the menu bar and windows behind the orbs remain visible. When a specific orb becomes active or hovered, it smoothly expands and brightens while its neighbours slide 16 pt aside to keep an even ~11 pt gap; all other idle orbs remain compact and semi-transparent. A row is centred at the top (or bottom or centre); in the corner setting it is right-aligned. Rows wrap when the screen is full.

- **One screen per row & display selection.** `AppDelegate.arrangeSessions` sets `rowScreen` on every orb from `settings.resolvedScreen()` (which can target any connected physical display by `CGDirectDisplayID`, the active display, or the pointer display). Pressing the global screen shortcut (`⌃⌥M` by default, configurable in **Ajustes → Animación → Atajo para cambiar pantalla**) cycles directly to the next connected monitor and moves the entire row or column there at once.
- **Click to focus terminal & fused hover info chip.** While the pointer hovers inside an orb's circle, `OverlayController.setInteractive(true)` enables mouse hit-testing on that panel alone and—when `settings.showHoverInfo` is enabled—`OrbInfoBadgeView` unfolds directly fused to the orb container without separating (`hoverBadge` `SmoothBlend`, 14 pt inner margin from the orb rim), showing the session title on top and the agent indicator + name (`Codex`, `Claude Code`, `OpenCode`, `Muse Code` or `Antigravity` in the agent's `HaloTheme` palette) below, left-aligned in a Consolas-style monospaced font. Clicking the orb runs `AppDelegate.focusSession(_:)`, which resolves the agent process's controlling TTY (`proc_pidinfo` + `devname`) and activates the owning terminal app and tab (`Terminal.app` or `iTerm2`).
- **Sliding.** A visible orb on the same screen slides to its new origin with a `CADisplayLink` (preferred 60 fps) stepping an unbounded `SmoothBlend` on the window origin. The duration is `min(0.95, 0.52 + 0.14·log2(1 + distance/110))` s; a redirected slide keeps its momentum. When an orb leaves, its neighbours wait 0.18 s so the bubble starts shrinking first. Measured in the app: ticks at 16.7 ms median, worst 22 ms.
- **Global position shortcut.** Pressing the global hotkey (`⌃⌥P` by default, configurable in **Ajustes → Animación → Atajo para cambiar posición** via Carbon `RegisterEventHotKey`) cycles `settings.position` (`Arriba al centro` → `Izquierda al centro (Columna)` → `Derecha al centro (Columna)` → `Abajo al centro` → `Centro de pantalla` → `Esquina inferior derecha`) and slides all visible orbs smoothly to the new screen edge or vertical column.
- A liquid stretch while sliding was tried and removed: it forced every moving orb to redraw at 60 fps, and the slide dropped to about 33 updates per second.

## 6. Session orbs

### 6.1 Lifecycle by agent

| | Codex | Claude Code | OpenCode | Muse Code | Antigravity |
|---|---|---|---|---|---|
| Orb appears | `SessionStart` hook, first prompt, or a detected `codex resume <id>` client | Detected window (placeholder `claude:<pid>` or the `--resume` id), `SessionStart` hook, or first prompt | Detected window (placeholder `opencode:<pid>`), `session.created`, or first prompt | Detected window (placeholder `muse:<pid>` or a `resume` UUID), `SessionStart` hook, or first prompt | Detected window (placeholder `agy:<pid>` or a `--conversation` UUID), `SessionStart` hook, or first prompt |
| Identity | session id | session id; owner = window process | session id; owner = window process found by folder | session id (`session_id`); owner = window process | conversation id, reported as `session_id`; owner = window process |
| Thinking | `UserPromptSubmit` | `UserPromptSubmit` | prompt hook | `UserPromptSubmit` | `PreInvocation` (fires before every model call) |
| Speaking | `Stop`, questions, permissions → `/speak` | same | `session.execution.succeeded`, questions → `/speak` | `Stop` (`last_assistant_message`), questions, permissions → `/speak` | `Stop` (last `PLANNER_RESPONSE` in the transcript), `ask_question` / `ask_permission` → `/speak` |
| Back to waiting | after speech; `Interrupt` hook | after speech; `StopFailure`; Escape noticed in the transcript | after speech; `session.execution.failed` or `interrupted` | after speech; `Interrupt` and `StopFailure` hooks | after speech; a failed `Stop` sends `interrupt` |
| New conversation in the same window | new session | the orb moves to the new id (`/clear`, `/resume`) | the orb moves to the new session if it is idle | the orb moves to the new session | the orb moves to the new conversation |
| Orb leaves | `SessionEnd` hook or the `codex resume` client closes | the window process exits (`SessionEnd` waits 1.5 s in case the window continues) | the window process exits | the window process exits (`SessionEnd` waits 1.5 s) | the window process exits |

An orb never closes while its speech is playing or queued; it closes when that speech ends.

### 6.2 Local API

All requests except `/health` need the `X-Prisma-Token` header (the token is in `~/Library/Application Support/Prisma/runtime.json`, along with the port; the port can change).

| Endpoint | Body | Effect |
|---|---|---|
| `GET /health` | — | `{"ok":true,"app":"Prisma"}` |
| `POST /speak` | `text`, `session_id`, `source`, `cwd`, `pid`, `engine`, `voice` | Queues speech on the session's orb. |
| `POST /thinking` | `session_id`, `source`, `pid`, `transcript_path`, `directory` | Thinking state. |
| `POST /interrupt` | `session_id` | Back to waiting (or hides the overlay orb). |
| `POST /session/start` | `session_id`, `source`, `pid`, `directory` | Ensures the session's orb. |
| `POST /session/end` | `session_id` | Ends the session's orb. |
| `POST /stop` | — | Stops speech and every thinking state. |

`source` is `codex`, `claude-code`, `opencode`, `muse` or `antigravity`; other sources use the overlay orb. `pid` is only honoured for Claude Code, OpenCode, Muse Code and Antigravity.

### 6.3 Hooks

`on_turn.sh [codex|claude-code|opencode|muse|antigravity] [evento]` maps `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Interrupt` and `StopFailure` to the endpoints above; Antigravity passes its event name as a second argument (`PreInvocation` behaves like `UserPromptSubmit`) because its payload has no `hook_event_name` or `source`.

- A Codex transcript (`"type":"session_meta"`) means Codex even if the argument says otherwise. Without an argument, any other transcript means Claude Code (hooks installed before this change pass no argument). A command-line source (Muse Code, Antigravity) is never overridden.
- For Claude Code, Muse Code and Antigravity it walks up from its parent past shells (`sh`, `bash`, `zsh`, …) to the agent process and sends it as `pid`; Claude Code also sends `transcript_path` on `UserPromptSubmit`.
- For OpenCode it forwards the session `directory`; for Muse Code the `cwd`; for Antigravity the first `workspacePaths` entry.
- Antigravity key names are camelCase (`conversationId`, `transcriptPath`, `workspacePaths`); `on_turn.sh` and `on_stop.sh` read both spellings.
- It only launches Prisma for a start or a turn, never for an interruption or an end.

`on_stop.sh [source] [evento]` adds the same `pid` for Claude Code, Muse Code and Antigravity replies. Its output must be valid JSON: Antigravity denies a tool when its `PreToolUse` hook answers `{}`, so that path answers `{"decision":"allow"}`, which keeps the tool's normal permission policy. Codex hooks live in `~/.codex/hooks.json` (written by **Ajustes → Agentes** or by `install.sh`); Claude Code hooks come from the plugin (`plugin/hooks/hooks.json`, cached under `~/.claude/plugins/cache/prisma-local/prisma/<version>`); Muse Code hooks live in `$XDG_CONFIG_HOME/muse/settings.json` (or `~/.config/muse/settings.json`), which requires `"schema_version": 1` and marks cancellation hooks `"async": true`; Antigravity hooks are the `prisma` entry in `~/.gemini/config/hooks.json`.

### 6.4 Claude Code

- `ClaudeCodeWindows` finds `claude` processes, excluding `-p`/`--print` runs and non-chat subcommands (`mcp`, `config`, `doctor`, …). Each window without an orb gets `claude:<pid>`, or the session id given with `--resume`/`--session-id`.
- Any event that carries the same `pid` and an unknown session id takes over that window's idle orb (`handOver`), which keeps the orb's place in the row. A session end with the window still alive is deferred 1.5 s for the same reason.
- Claude Code has no interrupt hook; it writes `{"type":"text","text":"[Request interrupted by user]"}` to the transcript. While an orb is thinking, Prisma reads only the bytes added since the turn began (at most the last 64 KB per check, every 2 s) and looks for that unescaped text. Quoted in a reply or tool call, the text appears escaped and does not count.

### 6.5 OpenCode

OpenCode 2.x runs plugins inside one shared background service (`opencode serve --service`, started by launchd). The plugin runs once per project folder, and that instance is evicted after about an hour without use. Its `process.pid` is the service, not a window, and the service exposes no client connect or disconnect events. So:

- `OpenCodeWindows` finds `opencode` processes that open a conversation (no subcommand, `run`, `attach`, or a path; not `serve`, `web`, `auth`, …). A helper started by another `opencode` process is not counted. Each window's folder is its working directory (`proc_pidinfo`).
- Each window without an orb gets `opencode:<pid>`. A session event with a folder takes over an idle OpenCode orb whose window was opened in that folder or one of its subfolders: the waiting placeholder first, otherwise the orb idle the longest.
- A session with no matching window gets an orb with no owner; a window detected later in that folder adopts it. An orphan that stays idle for 20 s leaves (for example, a reply that finishes after its window closed, or a client Prisma cannot see). An orphan with no window process also leaves after 15 minutes of silence whatever its state: a one-shot `opencode run` exits with SIGTERM about 15 ms after its turn, so its end event can reach the plugin before the process dies, and the orb would otherwise stay stuck thinking forever (seen 2026-11-04 with three model-test runs, two of them failed by an exhausted quota).
- The plugin sends `SessionStart` on `session.created` (skipping subagents, which have a `parentID`), and `UserPromptSubmit` from its prompt hook, both with the session folder. Speech goes through `on_stop.sh` with `cwd`. Completion and failure events (`session.execution.*`, `session.error`, `session.idle`) clear thinking in interactive sessions; one-shot runs may still die before delivering them, which the 15-minute reap covers.

### 6.6 Muse Code

- `MuseWindows` finds `muse` / `muse-bin-<version>` processes, excluding one-shot or non-chat subcommands (`exec`, `serve`, `export`, …). The launcher execs into the versioned binary, so either name counts. Each window without an orb gets `muse:<pid>`, or the session id when `muse resume` names a UUID.
- User hooks are merged into the `hooks` block of `$XDG_CONFIG_HOME/muse/settings.json` (or `~/.config/muse/settings.json`) with the eight events listed above; the file keeps the `"schema_version": 1` that Muse Code requires, a first-change `.prisma-backup` is kept, and disconnecting removes only Prisma's entries (and the file when nothing else was in it). User hooks need no workspace trust step, unlike project hooks.
- The cancellation hook declares `"async": true`; Muse Code refuses synchronous `Interrupt` hooks and would skip the entry with a startup warning.
- `Stop` carries `last_assistant_message`, so the reply text needs no transcript parsing; `request_user_input` questions and `PermissionRequest` prompts are read from `tool_input` like Codex's.
- The `<ForPrisma>` instructions are appended to Muse Code's user rules file, `$XDG_CONFIG_HOME/muse/AGENTS.md`.

### 6.7 Antigravity

- `AntigravityWindows` finds `agy` processes, excluding `-p`/`--print` runs and non-chat subcommands (`update`, `plugin`, `mcp`, …). Each window without an orb gets `agy:<pid>`, or the conversation id when `--conversation` names a UUID.
- The `prisma` entry of `~/.gemini/config/hooks.json` (the global customization directory shared by the App, CLI and IDE) declares `SessionStart`, `PreInvocation`, `Stop` and a `PreToolUse` gate limited by matcher to `ask_question|ask_permission`. Other named hooks are preserved; a first-change `.prisma-backup` is kept.
- The hook commands run with the working directory set to `~/.gemini/config`, so they use absolute paths to the support scripts.
- `Stop` has no message field: the reply is the last `MODEL` / `PLANNER_RESPONSE` entry of the session transcript (`transcriptPath`, normally `…/brain/<conversationId>/.system_generated/logs/transcript_full.jsonl`). A `Stop` with a non-empty `error` stays silent and only clears the thinking orb.
- `PreToolUse` questions are read from `toolCall.args`; the hook answers `{"decision":"allow"}` so that Antigravity's own policy (or the user) still decides, and any other answer would deny the tool.
- The `<ForPrisma>` instructions are appended to `~/.gemini/config/AGENTS.md`, a global rules file loaded by every Antigravity surface.

### 6.8 Monitors

Every 2 s a background timer takes one `ps -axo pid=,args=` snapshot and then, on the main thread:

1. Updates `codex resume` sessions.
2. Ends Claude Code, OpenCode, Muse Code and Antigravity orbs whose window process has exited.
3. Gives new Claude Code, OpenCode, Muse Code and Antigravity windows their orbs, and ends idle OpenCode orphans.
4. Checks the transcripts of thinking Claude Code orbs.

### 6.9 Connecting agents from Ajustes

**Ajustes → Agentes** configures each agent without the repository. The app ships the integrations in `Prisma.app/Contents/Resources/plugin-dist`; pressing **Conectar** copies them to `~/Library/Application Support/Prisma/plugin-dist`, copies `on_stop.sh` and `on_turn.sh` to the support folder and points the Codex and Claude Code marketplaces at that copy.

| Agent | What **Conectar** does | What **Desconectar** removes |
|---|---|---|
| Codex | Merges the seven hook events into `~/.codex/hooks.json` keeping other hooks, adds the `<ForPrisma>` block to `~/.codex/AGENTS.md`, registers the marketplace and installs `prisma@prisma-local`, then marks the hook hashes as trusted through `codex app-server`. | Only the Prisma hook entries, the instruction block, and the plugin and marketplace it installed. |
| Claude Code | Registers the marketplace, installs and enables `prisma@prisma-local`, and adds the block to `~/.claude/CLAUDE.md`. | Only that plugin, its marketplace entry and the instruction block. |
| OpenCode | Copies `prisma.ts` to `~/.config/opencode/plugins/` and `SKILL.md` to `~/.config/opencode/skills/prisma/`, then runs `opencode reload`. | Those two files. |
| Muse Code | Merges the eight hook events into `~/.config/muse/settings.json` (keeping `schema_version` and other settings) and adds the block to `~/.config/muse/AGENTS.md`. | Only the Prisma hooks and the instruction block; the file goes away when nothing else was in it. |
| Antigravity | Writes the `prisma` entry into `~/.gemini/config/hooks.json` keeping other named hooks, and adds the block to `~/.gemini/config/AGENTS.md`. | That entry and the instruction block; the file goes away when nothing else was in it. |

Each row reports *Conectado*, *Falta: …* for a partial install, or that the agent's CLI is missing. Claude Code counts as connected when any Prisma marketplace root holds `plugin/plugin.json`, so an install made earlier by `install.sh` from the repository also counts. The hooks depend on `jq`; when it is missing the section shows a warning instead of failing silently. Codex may restart its app server after answering `hooks/list`, so the trust step uses two short sessions with the messages batched in each.

## 7. Speech queue

Requests are spoken one at a time in arrival order on the orb of their session (`playNextSpeech`); thinking ends when a session's speech starts. When an orb is handed over to a new session id, queued requests and the active speech move with it.

## 8. Verification

### 8.1 Automated tests

```bash
# Animation continuity: pose weights under random interruptions, beam geometry, seamless loop, row slide
swiftc -O -swift-version 5 -parse-as-library app/Sources/Prisma/OverlayView.swift \
  app/Sources/Prisma/SettingsStore.swift tests/test_overlay_motion.swift -o /tmp/prisma-motion && /tmp/prisma-motion

# Window detection for Claude Code, OpenCode, Muse Code and Antigravity
swiftc -parse-as-library app/Sources/Prisma/OpenCodeWindows.swift app/Sources/Prisma/ClaudeCodeWindows.swift \
  app/Sources/Prisma/MuseWindows.swift app/Sources/Prisma/AntigravityWindows.swift \
  tests/test_agent_windows.swift -o /tmp/prisma-windows && /tmp/prisma-windows

# codex resume detection
swiftc app/Sources/Prisma/CodexSessionsMonitor.swift tests/test_codex_sessions_monitor.swift \
  -o /tmp/prisma-codex && /tmp/prisma-codex

# Ajustes → Agentes: hook merge, instruction blocks, OpenCode files and status detection
swiftc -parse-as-library app/Sources/Prisma/AgentConnections.swift app/Sources/Prisma/Config.swift \
  tests/test_agent_connections.swift -o /tmp/prisma-agents && /tmp/prisma-agents

# Hook scripts (macOS), the Windows app and its agent connections
python3 -m unittest discover -s tests

# OpenCode plugin flow with a mocked OpenCode
node tests/test_opencode_flow.mjs

# Update manifest signature, tampering and SHA-256
(cd app && swift test)
```

### 8.2 Offline renderer

`tools/orb-renderer` draws the orb frame by frame through a scripted sequence (`cycle`: waiting → thinking at 1.0 s → voice at 3.6 s → waiting at 6.6 s; `silent`: the same without audio; `interrupt`: rapid changes):

```bash
tools/orb-renderer/render.sh /tmp/orb 30 cycle
python3 tools/orb-renderer/sheet.py /tmp/orb /tmp/orb.png 30 1.0,3.6,6.6
tools/orb-renderer/render.sh /tmp/orb-silent 60 silent
python3 tools/orb-renderer/diffs.py /tmp/orb-silent 60 1.0,3.6,6.6
```

Look at the contact sheet before claiming a transition is smooth: knots, slits, flips and cross-fades are obvious there and invisible in two or three screenshots. The renderer replaces the native blur with a dark stand-in, so judge the glass in the real app.

### 8.3 In the real app

- **Drive states** with the local API. Use a test session id and end it afterwards so no extra orb stays on screen:

  ```bash
  RT="$HOME/Library/Application Support/Prisma/runtime.json"
  PORT=$(jq -r .port "$RT"); TOKEN=$(jq -r .token "$RT")
  post() { curl -s -X POST "http://127.0.0.1:$PORT/$1" -H "X-Prisma-Token: $TOKEN" -H 'Content-Type: application/json' -d "$2"; }
  post thinking '{"session_id":"test-orb","source":"codex"}'
  post speak '{"session_id":"test-orb","source":"codex","engine":"apple","text":"Listo."}'
  post session/end '{"session_id":"test-orb"}'
  ```

- **Record** with `screencapture -x -v -V 10 -R<x>,0,<width>,300 out.mov`. The orb windows are layer 1000 windows owned by `Prisma` in `CGWindowListCopyWindowInfo`. Extract frames with `ffmpeg -fps_mode passthrough` to keep real timestamps.
- **Frame rate.** Screen recordings and window polling cannot measure 60 fps reliably. For a real number, count frames inside the app with a temporary build: log from the `TimelineView` closure or from `stepGlide`, then remove the logging.
- **Main-thread load:** `sample <pid> 5`.
- **OpenCode window without a prompt:** `script -q /dev/null opencode` in a folder opens a real terminal window; close it with `pkill -f "script -q /dev/null"`.

## 9. Known limitations

- **OpenCode:**
  - With several windows in the same folder, Prisma cannot tell which session belongs to which window.
  - Clients Prisma does not see (remote or desktop) get temporary orbs.
  - The `session.created` payload shape (`info.id`, `info.directory`) is covered only by the mocked test; in the real run the prompt hook already delivered the session.
- **Claude Code:**
  - One-shot `claude -p` runs show an orb while they run, from their hooks.
  - Interruptions are detected by the transcript marker, which could change between Claude Code versions, and with a delay of up to 2 s.
- **Codex** (unchanged): an empty session may not emit its start hook until the first prompt, and a closed terminal can leave the session running.
- **Tests:** the session registry in `AppDelegate` has no unit tests; it was verified live.
- **Windows:** the Windows implementation has none of these features.
