# Roadmap and product notes

Last updated: 2026-11-01

## Current state

The macOS app provides a floating Liquid Glass orb, Edge Ava Multilingual with Piper and Apple Paulina fallbacks, spoken summaries and interactive question notifications for OpenCode, Codex, and Claude Code, system audio ducking with voice compensation and restoration, and settings for voice, speed, position, visibility, and background audio. See [Background audio](audio-ducking.md) for the macOS implementation.

Every Codex, Claude Code and OpenCode session has its own orb in a row: it waits between turns, thinks while the agent works, and turns into the voice horizon to speak. The three states are one beam of light that bends between shapes at 60 fps, and the row slides when orbs arrive or leave. See [Orb animation and session orbs](orb-and-sessions.md); the state of that work and the next steps are in the [handoff notes](handoff.md).

A separate Windows implementation has been added with tray controls, a pulsing orb, voice backends, agent integrations, and per-session ducking. **It still needs end-to-end validation on Windows**; see the [Windows validation checklist](windows.md#validation).

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
