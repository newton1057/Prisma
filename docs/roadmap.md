# Roadmap and product notes

Last updated: 2026-11-04

## Current state

The macOS app provides a floating Liquid Glass orb, Edge Ava Multilingual with Piper and Apple Paulina fallbacks, spoken summaries and interactive question notifications for OpenCode, Codex, and Claude Code, system audio ducking with voice compensation and restoration, and settings for voice, speed, position, visibility, and background audio. See [Background audio](audio-ducking.md) for the macOS implementation.

Every Codex, Claude Code and OpenCode session has its own orb in a row: it waits between turns, thinks while the agent works, and turns into the voice horizon to speak. The three states are one beam of light that bends between shapes at 60 fps, and the row slides when orbs arrive or leave. Since 1.0.1 the app also connects each agent from **Ajustes → Agentes**, installing its hooks and plugin without the repository, so a DMG install can configure Codex, Claude Code and OpenCode on a clean Mac. See [Orb animation and session orbs](orb-and-sessions.md); the state of that work and the next steps are in the [handoff notes](handoff.md).

A separate Windows implementation has been added with tray controls, a pulsing orb, voice backends, agent integrations, and per-session ducking. Windows 1.0.1 adds **Ajustes → Agentes** with the same connect/reconnect/disconnect flow as macOS, backed by the portable `windows/agents.py`, and ships as a ZIP that needs no repository after installation. **It still needs end-to-end validation on Windows**; see the [Windows validation checklist](windows.md#validation).

## Suggested next steps

### Display selection on macOS — high priority

`OverlayController.position` uses `NSScreen.main` with `NSScreen.screens.first` as a fallback. On a machine with an external monitor, `NSScreen.main` may be the focused screen rather than the one with the notch. In the 2026-10-30 test, the panel appeared on the external display:

- Built-in: `(0, 0, 1710, 1112)`, with notch and `visibleFrame.y = 36`.
- External: `(-1920, 32, 1920, 1080)`.
- Panel: `x = -1190`, `y = 752` (top center of the external screen).

| Policy | Advantage | Trade-off |
|---|---|---|
| Menu bar display (`NSScreen.screens.first`) | Matches the notch and expected placement | Ignores where the user is working |
| Pointer display (`NSEvent.mouseLocation`) | Follows the current context | May jump between screens |
| Focused agent's display | Follows the conversation | `NSScreen.main` has proved ambiguous for nonactivating panels |
| Explicit animation setting | Full user control | Adds a setting |

Since 2026-11-01 the session orbs share one screen per row (`rowScreen`, chosen from `NSScreen.main` whenever the row is arranged), so the row no longer splits across displays. A screen policy can now be applied in one place, `AppDelegate.arrangeSessions`.

Acceptance: with two displays, the orb always appears on the chosen screen, moves immediately when the setting changes, and defaults to the display with the notch.

### Per-app ducking on macOS — medium priority

macOS currently lowers global output volume, including notifications and alarms. Evaluate CoreAudio process taps (macOS 14.4+) to attenuate content such as music and video. Validate capture permission and `Info.plist` text, CPU and latency with multiple apps, behavior with AirPlay, Bluetooth, and aggregate devices, and fallback to global ducking if taps fail.

### Automated macOS audio tests — medium priority

Extract `SystemAudioDucker.restoreTarget` into a pure function and cover an in-progress down-ramp, manual volume changes, repeated `duck()` without an intervening `restore()`, zero volume or devices without volume control, and `restoreImmediately()` with and without `pendingRestoreTarget`. Add a reference-tone integration test measuring RMS before and after compensation.

### Audio robustness — low priority

- Observe output device changes and transfer ducking.
- Retry restoration when `AudioObjectSetPropertyData` fails.
- Expose ramp durations if Bluetooth dropouts are observed.

### Product experience — low priority

- Tell session orbs apart (agent accent, project label or click to focus the terminal).
- Orb meter sensitivity for quiet voices.
- Reduced-motion accessibility mode.
- A short history of spoken messages.
- A global shortcut to mute or repeat the last summary.

## Technical debt and risks

- The macOS audio ramp and restoration logic has no automated tests; verification is manual. Portable Windows protocol and hook tests are available.
- Speech logic is duplicated across Edge, Piper, and Apple; speed and normalization changes must be tested across all three.
- `install.sh` uses `pkill` and relies on the `SIGTERM` handler to restore volume. Preserve that signal or call `shutdown()` another way when changing the installer.
- The 10-minute watchdog only protects while the process is alive; `SIGKILL` can leave audio attenuated.
- The Piper voice model (~60 MB) is not included in the repository; `setup_voice.sh` downloads it.
- The server tries the next port when 8787 is occupied. Scripts must read `runtime.json` rather than hard-code a port.
- The session registry in `AppDelegate` (owners, hand-over, deferred ends, OpenCode folders) is verified live only; extract it and add unit tests before extending it.
- OpenCode windows are found by process scan because its plugin runs in a shared service; changes to OpenCode's command line or architecture can break the detection.
- Claude Code interruptions are detected through a transcript marker that is not a documented interface.
- The Codex hook-trust step uses the experimental `codex app-server` protocol (`hooks/list`, `config/batchWrite`); a Codex update can change it. Both apps fall back to a warning asking the user to approve the hooks.
- Agent connections merge JSON and TOML by targeted edits rather than rewriting whole files; keep the unrelated-hook tests when touching `AgentConnections.swift` or `windows/agents.py`.
- Windows agent status relies on `PATH`; an agent installed outside the user or system `PATH` is reported as missing until its CLI is available to the tray app.

## Resume work on macOS

```bash
cd ~/Desktop/Prisma
git pull
./install.sh
~/Desktop/Prisma/test.sh "Hello. Prisma is ready."
```

Check `/health` on the port in `runtime.json`, toggle and adjust **Ajustes → Audio de fondo**, and play music while sending a long test message.

## Decision log

| Date | Decision | Reason |
|---|---|---|
| 2026-10-30 | Global CoreAudio ducking instead of private APIs | Public, stable route; compensate voice with a limiter |
| 2026-10-30 | `AVAudioEngine` + PeakLimiter instead of `AVAudioPlayer` | Positive gain without distortion |
| 2026-10-30 | 0.32-second pre-roll | Background audio drops before the first word |
| 2026-10-30 | Respect manual volume changes during restoration | Avoid overriding the user |
| 2026-10-30 | Ten-minute watchdog refreshed per chunk | Protect against abnormal exits without cutting off long messages |
| 2026-10-30 | Minimum 65% ducking level for Apple voice | `AVSpeechSynthesizer` cannot be gain-compensated |
| 2026-11-01 | One beam whose bend morphs between horizon, ring and fold | Point-by-point interpolation between shapes knotted and cross-faded |
| 2026-11-01 | Quintic Hermite pose blends with momentum limit | Interrupted transitions stay smooth and weights stay valid |
| 2026-11-01 | `minimumInterval` 1/90 s and 1/36 s | Exactly 1/60 s skipped about every other frame |
| 2026-11-01 | Only the light breathes, not the glass | Resizing `NSVisualEffectView` per frame was the largest per-frame cost |
| 2026-11-01 | No liquid stretch while orbs slide | Redrawing every moving orb at 60 fps dropped the slide to ~33 fps |
| 2026-11-01 | Detect OpenCode windows by process and folder | Its plugin runs in a shared service and cannot tell windows apart |
| 2026-11-01 | Claude Code orbs owned by the window process | Keeps the orb through `/clear` and `/resume` and removes it when the window closes |
| 2026-11-01 | Compact inactive orbs (0.34 scale, 50% opacity) vs active/hovered orbs (0.50 scale, 95% opacity) | Keeps many session orbs unobtrusive and lets the user see behind them while highlighting active or hovered orbs |
| 2026-11-01 | Per-agent halo themes (10 palettes) and click-to-focus terminal via TTY | Lets the user tell Codex, Claude Code, and OpenCode orbs apart at a glance and jump straight to any session's terminal tab |
| 2026-11-01 | Fused hover info chip, vertical side columns, display selection, and global hotkeys (`⌃⌥P`, `⌃⌥M`) | Shows session title + agent on hover fused to the orb, supports left/right vertical columns, and switches positions or monitors from any app |
| 2026-11-04 | Connect agents from the app in Swift instead of calling `install.sh` | A DMG install has no repository, and writing hooks natively removes the `jq` dependency for configuration |
| 2026-11-04 | Ship `plugin/`, `.agents/` and `.claude-plugin/` inside the app under `Contents/Resources/plugin-dist` | The app has a stable source for both marketplaces and can re-stage it after every update |
| 2026-11-04 | Mark Codex hooks trusted with two batched `app-server` sessions | Codex restarts the server after `hooks/list`, so a later write on the same session fails |
| 2026-11-04 | Accept any Prisma marketplace root for Claude Code | Installs made earlier from the repository must keep counting as connected |
| 2026-11-04 | Windows keeps direct hooks and a direct OpenCode plugin instead of plugin marketplaces | The Windows app is a separate Python implementation; marketplaces would add a second install path with no benefit there |
| 2026-11-04 | Windows stages `plugin/` and its runtime under `%LOCALAPPDATA%\Prisma\plugin-dist` | Ajustes and the hooks must work after the ZIP folder is moved or deleted |
| 2026-11-04 | Windows release is a ZIP and a separate `windows-v1.0.1` tag marked not-latest | A Windows EXE cannot be built from macOS, and the macOS DMG remains the Latest release |
| 2026-11-04 | Document agent connections as local-session only | Cloud and remote sessions do not execute local hooks; the desktop apps were not validated |
| 2026-11-04 | Update from a dedicated public bucket with a signed manifest, keeping the DMG on GitHub | The bucket can be checked without authentication; the signature prevents a tampered package from being installed |
| 2026-11-04 | One signing key per app, stored in the login keychain | Sharing IconicOS Studio's key would let a leak affect both apps |
| 2026-11-04 | Disable the updater in the development copy next to `Package.swift` | A local build must not replace itself or depend on a release bucket |
| 2026-11-04 | The first updater version is installed by hand | Earlier versions do not contain the updater |
| 2026-11-05 | Windows update checks use `windows-latest.json`, separate from macOS `latest.json` | The two apps have independent build numbers and packages, and neither should announce the other |
| 2026-11-05 | Windows verifies the Ed25519 signature in pure Python | It avoids a compiled crypto dependency and keeps the check available even if a package install fails |
| 2026-11-05 | Windows applies updates with a helper that waits for the app to exit | Windows cannot replace modules a running process has open; settings, the venv and the voice model stay in place |
| 2026-11-05 | The Latest badge follows the most recently published release, Windows or macOS | The user wants the newest release visible on the repository sidebar; GitHub allows only one Latest and each publisher now claims it for its own release |
| 2026-11-05 | One release per version with the same version and build for macOS and Windows | The user wants a single download page and one version number; the per-platform publishers were replaced by `tools/publicar.sh`, while each app keeps its own bucket manifest |
| 2026-11-05 | Muse Code connects through user hooks in `~/.config/muse/settings.json` and user rules in `~/.config/muse/AGENTS.md` | User hooks need no workspace trust, match how Codex is connected, and keep the settings file's required `schema_version`; `Interrupt` must be declared `async` or Muse Code skips it |
| 2026-11-05 | Antigravity connects through the `prisma` entry in the shared `~/.gemini/config/hooks.json` and global rules in `~/.gemini/config/AGENTS.md` | One customizable directory covers the app, CLI and IDE; the named entry preserves other hooks, and `PreToolUse` must answer `{"decision":"allow"}` or the tool is denied |
| 2026-11-05 | Antigravity replies are read from the session transcript; Muse Code's Stop already carries the final message | Antigravity's Stop payload has no message field, while its `PLANNER_RESPONSE` transcript entries give the last reply reliably |
