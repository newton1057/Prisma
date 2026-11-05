# Handoff: orb animation and session orbs

Date: 2026-11-04
For: the next agent continuing work on Prisma (macOS)
Technical reference: [Orb animation and session orbs](orb-and-sessions.md)

## 1. State of the repository

- **v1.0.0 released.** Tag `v1.0.0` points at `5e9d152` on `origin/main`; the DMG is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.0) (SHA-256 `abae9fd3…`).
- **v1.0.1 released (macOS).** Tag `v1.0.1` points at `94bb53b`; the DMG is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.1) (SHA-256 `455eff272ee804a6795061cb7e95ba49091c0af250aa237a9443fcb488976a54`). The app connects Codex, Claude Code and OpenCode from **Ajustes → Agentes** without the repository.
- **v1.0.2 released (macOS, 2026-11-04).** Tag `v1.0.2` points at `6390b26` on `origin/main`; the DMG is in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.2) (SHA-256 `cbe7f74835cc2bc06cb213568b2dd71ae36e31fcfb33136ad2339db96915123d`). This is the first version with the bucket updater: it checks `prisma-updates` at launch and every six hours. The signing key is in the login keychain under **Prisma actualizaciones**, with a `600` backup at `~/Library/Application Support/Prisma/firma-actualizaciones.txt`; restore it with `UpdateSigner restaurar`. Bucket `prisma-updates` exists in `system-kn` with public read-only access and no listing. The first updater version must be installed by hand; 1.0.1 and earlier cannot update themselves.
- **Windows 1.0.1 released.** Tag `windows-v1.0.1` points at `fc9b9c1`; `Prisma-Windows-1.0.1.zip` is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/windows-v1.0.1) (SHA-256 `3a3aa86a1e2f4fba2856a5cca00540adaab35e9d41158cc4a8967ce0ac7d3a0f`). It is intentionally **not** marked Latest so the macOS DMG stays Latest. The ZIP adds the Windows **Ajustes → Agentes** section and a portable plugin copy; it still needs end-to-end validation on a real Windows machine.
- **Installed and running (1.0.2).** `~/Applications/Prisma.app` is the 1.0.2 build on this Mac. It checked the real bucket after launch and logged `al día; publicada 1.0.2`.
- **Tests pass:** Swift (motion, themes, activity scale, window detection, Codex monitor, agent connections, update manifest signature and SHA-256), Python (hooks; Windows app and agent connections, 26 tests), Node (OpenCode flow). Commands are in [section 8.1](orb-and-sessions.md#81-automated-tests) of the reference.

## 2. What was done

### Codex session `01a19592-8739-7d53-89e1-7398f62ddfd2` (resume with `codex resume 01a19592-8739-7d53-89e1-7398f62ddfd2`)

- Thinking mode: the orb appears when a prompt is sent and turns into the voice orb for the reply. Codex first, then Claude Code and OpenCode.
- Shell and orbs:
  - Circular container, made smaller, halos centred.
  - Droplet-like entrance and exit.
  - Dark interior while thinking.
- One persistent orb per Codex session, in a row, with replies spoken in order. Open `codex resume <id>` clients are detected by process.
- Waiting state, after many iterations (constellation, light flower, droplet, aurora, a blue ribbon from a reference image, then folds inspired by a Dribbble shot). The colours follow the voice palette.

### Claude Code session `4825ad45-2a1c-4ee0-ac81-1abdb7ea98f7`

1. **One beam across states.**
   - Problem: transitions interpolated points between unrelated shapes, so the ring flipped and knotted when opening, and colours and backgrounds cross-faded.
   - Fix: a single centre line whose bend goes from the horizon arc to a closed loop. Colours are attached to the beam, the loop ends fade before parting, and the background changes in step with the bend. Pose changes use a quintic Hermite blend that keeps momentum through interruptions.
2. **True 60 fps.** `minimumInterval: 1/60` was skipping about every other frame (31–38 fps measured). It now uses 1/90 for motion and 1/36 for waiting. The audio level no longer triggers redraws.
3. **Performance.**
   - The glass blur is no longer resized every frame.
   - Unused layers leave the view tree.
   - Gradients animate opacity instead of colours.
   - Two canvases were merged.
   - Result: CPU with 7 orbs went from about 44 % to 25–29 %.
4. **Sliding row.** Neighbours slide when an orb arrives or leaves (`CADisplayLink`, 60 Hz measured). The row stays on one screen (`rowScreen`).
5. **Session orbs for Claude Code and OpenCode.**
   - Each window has an orb.
   - Claude Code: hooks report the window process; `/clear` and `/resume` keep the orb in place; Escape is noticed in the transcript.
   - OpenCode: windows are found by process scan and matched by folder, because its plugin runs in a shared service.
### OpenCode session (2026-11-01)

1. **Compact inactive vs. active session orbs and translucent glass.**
   - Waiting orbs rest in a compact state (scale `0.34`, ~67 pt diameter, 78 pt slot, 50 % opacity) with a softened backdrop blur and translucent smoked-glass interior so the menu bar and windows behind them remain readable.
   - When a specific orb is thinking, speaking, or hovered by the pointer (`NSEvent` global/local monitors + hit-testing on the orb circle), only that orb smoothly expands to its active size (scale `0.50`, ~99 pt diameter, 110 pt slot, 95 % opacity) while its neighbours slide 16 pt aside.
2. **Ten halo colour themes per agent.**
   - Added `HaloTheme` (`prisma`, `aurora`, `oceano`, `nebula`, `solar`, `amatista`, `esmeralda`, `artico`, `atardecer`, `platino`), recolouring the bloom, spectral bands, core filament, closed-loop stops, waiting ambient glow and outer aura across all three states.
   - Added independent selectors and interactive colour swatches in **Ajustes → Color del halo por agente** (`codexTheme`, `claudeTheme`, `openCodeTheme`).
3. **Click an orb to focus its terminal.**
   - `CodexSessionsMonitor.resumedSessionPIDs` records the process ID for `codex resume` sessions alongside Claude Code and OpenCode window processes.
   - While hovered, only that orb's panel enables mouse hit-testing (`setInteractive(true)`). Clicking the orb resolves its controlling TTY (`proc_pidinfo` + `devname`) and activates the exact window and tab in `Terminal.app` or `iTerm2` (`NSAppleEventsUsageDescription` in `app/Info.plist`).
4. **Fused hover info chip (`OrbInfoBadgeView`).**
   - While hovered (and when `settings.showHoverInfo` is enabled in **Ajustes → Animación → Mostrar información de la sesión al pasar el cursor**), a liquid-glass chip unfolds directly fused to the orb without separating (`hoverBadge` `SmoothBlend`, 14 pt inner breathing margin from the orb rim).
   - Displays the session title on top (`~/.codex/session_index.jsonl` `thread_name`, Claude Code transcript summary/title, or OpenCode project folder) and the agent indicator + name below, left-aligned in a Consolas-style monospaced font.
5. **Vertical side columns, multi-display selection and global hotkeys.**
   - Added `.left` (`Izquierda al centro (Columna)`) and `.right` (`Derecha al centro (Columna)`) vertical column layouts alongside `.top`, `.bottom`, `.center` and `.corner`.
   - Added Carbon global hotkeys (`RegisterEventHotKey`, no Accessibility permission required): `⌃⌥P` (`PositionShortcut`) to cycle orb positions smoothly, and `⌃⌥M` (`ScreenShortcut`) to send the orbs to the next connected display, plus explicit display selection in **Ajustes → Animación → Pantalla** (`targetDisplay`).

### 1.0.1 session (2026-11-04, evening): phantom OpenCode orbs

1. **Diagnosis.** The app was healthy; three unclickable OpenCode orbs were orphan sessions from one-shot `opencode run` model tests (19:16, from a Claude Code scratchpad; two failed with a provider quota error, one succeeded). The runs die with SIGTERM ~15 ms after the turn, so no completion event reached the plugin and the orbs stayed thinking forever; the 20 s orphan reap skips thinking orbs (`canHandOver`). The three were ended live with `POST /session/end` using the real session ids from `session_v2` in `~/.local/share/opencode/opencode.db`.
2. **Fixes.**
   - `AppDelegate.updateOpenCodeWindows`: an OpenCode orphan with no window process also leaves after 15 minutes of silence regardless of state (speech still delays the close; a returning client gets a fresh orb).
   - `plugin/opencode/prisma.ts`: subscribes to `session.error` (present in OpenCode 2.2.5, previously uncovered) and treats it like a failure → `Interrupt`.
3. **Deployed.** App rebuilt and reinstalled (running build has the fix); plugin copied to `~/.config/opencode/plugins/` and `opencode reload` run. `tests/test_opencode_flow.mjs` passes. Verified live: 2 orbs for 2 real windows (an OpenCode TUI and a Claude Code TUI). The Claude marketplace still points at the repository and `plugin-dist` does not exist; harmless, pressing **Reconectar** in Ajustes would restage it.

### 1.0.1 session (2026-11-04)

1. **Connect agents from Ajustes.**
   - New `AgentConnections.swift`: `AgentConnector` (observable) and `AgentInstaller` (status, install, remove) for Codex, Claude Code and OpenCode.
   - `SettingsView.swift` gained the **Agentes** section: status dot, detail, **Conectar** / **Reconectar** / **Desconectar**, a `jq` warning, and connection warnings.
   - `app/build.sh` now copies `plugin/`, `.agents/` and `.claude-plugin/` into `Contents/Resources/plugin-dist`, so the DMG does not need the repository.
   - The app stages those files in `~/Library/Application Support/Prisma/plugin-dist`, copies `on_stop.sh` and `on_turn.sh` to the support folder, and points both marketplaces at that copy.
   - Codex: merges seven hook events into `~/.codex/hooks.json`, keeps other hooks, adds the instruction block to `~/.codex/AGENTS.md`, installs the plugin, and trusts the hook hashes through `codex app-server`. Claude Code: registers the marketplace, installs and enables the plugin, and adds the block to `~/.claude/CLAUDE.md`. OpenCode: copies the plugin and skill, then reloads.
   - Detection is lenient: a Prisma marketplace installed from the repository also counts as connected.
2. **Tests.** `tests/test_agent_connections.swift` covers the hook merge and idempotency, disconnect, instruction blocks, OpenCode files, status detection and missing CLIs. An isolated-HOME end-to-end run installed and removed all three agents with the real CLIs.
3. **Scope note: local sessions only.** Ajustes and the README, Windows guide and LEEME now state that the integrations cover local sessions on the machine where they are installed; cloud or remote sessions do not run these hooks or this plugin. The desktop apps were not exercised, so Codex Desktop, Claude Code Desktop and OpenCode Desktop remain unvalidated; local desktop sessions read the same configuration, but no Desktop session has been verified with Prisma.

### Windows 1.0.1 session (2026-11-04)

1. **Agent connections in Ajustes.**
   - New `windows/agents.py`: status, connect and disconnect for Codex, Claude Code and OpenCode, plus `ensure_support()` to copy the runtime and stage `plugin/` under `%LOCALAPPDATA%\Prisma\plugin-dist`.
   - Codex: merges `Stop`, `PreToolUse` and `PermissionRequest` hooks, keeps unrelated hooks, backs up the file, appends the instruction block and trusts the hashes through two batched `codex app-server` sessions. Failure only produces a warning; Codex can still ask for approval.
   - Claude Code: merges the same hooks into `settings.json`, appends the block to `CLAUDE.md` and removes only Prisma's changes on disconnect.
   - OpenCode: copies `plugins\prisma.ts` and `skills\prisma\SKILL.md`, compares the installed plugin with the staged copy and runs `opencode reload` when the CLI is available.
   - The installer now calls `agents.connect()` for the agents it detects instead of duplicating hook logic. `windows/common.py` exposes `VERSION = '1.0.1'`, used by `/health` and the settings footer.
2. **Windows UI.** `windows/app.py` gained an **Agentes** section with status dots, details, **Conectar** / **Reconectar** / **Desconectar**, warnings, a background worker and an `agent-done` event. The dialog stays responsive while Codex is trusted.
3. **Packaging.** `windows/LEEME.txt`, `windows/install.cmd` and `tools/package-windows.sh` produce `dist/Prisma-Windows-1.0.1.zip` with the `Prisma` folder, `Instalar Prisma.cmd`, `windows/` and `plugin/`. `dist/` is ignored by git.
4. **Tests.** `tests/test_windows.py` now covers Codex merge/idempotency/backup/removal, instruction blocks, Claude and OpenCode round trips, missing CLI, staged runtime, the two-session trust protocol with a fake app server, and the UI worker. A simulated install from the generated ZIP with isolated `CODEX_HOME` and `CLAUDE_CONFIG_DIR` and the real Codex and Claude CLIs ended with both connected before cleanup. The real Codex trust path was also checked against Codex 0.166.0 with a temporary `CODEX_HOME`.
5. **Pending validation.** None of this has run on real Windows yet. Check the installer and `Instalar Prisma.cmd`, the tray and Ajustes layout, the three agent connections, Codex trust, and voice playback before calling Windows 1.0.1 stable.

### Updater session (2026-11-04)

1. **Bucket updater adapted from IconicOS Studio.** New `UpdateCore` (manifest, Ed25519 signature, SHA-256), `UpdateSigner` (keychain key, sign and verify), `Updater.swift` (ephemeral URLSession, manifest check, download, signature/size/hash/bundle check, installer script) and tests. `Package.swift` gains the three targets; `app/Info.plist` gains `PrismaUpdatesEnabled`.
2. **App integration.** The updater checks at launch and every six hours, shows a banner in **Ajustes**, and adds **Buscar actualizaciones…** / **Actualizar a la versión X…** to the menu bar. It stays disabled in the development copy next to `Package.swift`; `PRISMA_ACTUALIZACIONES_URL` and `PRISMA_APP_SUPPORT` exist for local tests.
3. **Publishing.** `app/empaquetar.sh` produces `dist/Prisma-<version>.zip` and `.dmg`; `app/publicar.sh` verifies the package, signs `latest.json`, publishes the DMG to GitHub and the ZIP + manifest to `prisma-updates`. `app/verificar_paquete.py` blocks credentials in the public package.
4. **Verified and published.** 1.0.1 → 1.0.2 update and reopen; tampered manifest rejected; wrong `CFBundleIdentifier` rejected; read-only location rejected; package signature and `codesign --verify --deep --strict` pass. The bucket is created, the 1.0.2 DMG and manifest are published, and the real 1.0.2 app in `~/Applications` reports `al día`. Pending: the full step-9 checklist on another Mac and with a non-admin account, and a real 1.0.2 → next-version update (the first updater version could only be installed by hand).

## 3. Resume work

```bash
cd ~/Desktop/Prisma
./app/build.sh                     # build only (app/Prisma.app)
./install.sh                       # full install: app, scripts, Codex hooks, Claude Code and OpenCode plugins
tools/orb-renderer/render.sh /tmp/orb 30 cycle && \
  python3 tools/orb-renderer/sheet.py /tmp/orb /tmp/orb.png 30 1.0,3.6,6.6   # look at transitions
```

To reinstall only the app after a Swift change:

```bash
./app/build.sh
pkill -f 'Prisma.app/Contents/MacOS/Prisma'
rm -rf ~/Applications/Prisma.app
cp -R app/Prisma.app ~/Applications/
open ~/Applications/Prisma.app
```

Session orbs reappear within 2 s: Codex `resume` clients and every Claude Code and OpenCode window are detected by process. After changing `plugin/`, rebuild the app and press **Reconectar** in **Ajustes → Agentes** (or run `./install.sh`); Claude Code runs its hooks from the plugin cache.

To rebuild the Windows release ZIP:

```bash
./tools/package-windows.sh   # dist/Prisma-Windows-<version>.zip
```

## 4. Gotchas

- **OpenCode's plugin runs in a daemon** (`opencode serve --service`). `process.pid` there is not a window, and there are no client connect or disconnect events. Window detection lives in Prisma (`OpenCodeWindows.swift`).
- **Never use `minimumInterval: 1/60`** in `TimelineView`; see [section 3.3](orb-and-sessions.md#33-frame-rate) of the reference.
- **Never scale `NSVisualEffectView` per frame** or reassign its properties in `updateNSView`; it re-renders its material.
- **Claude Code** loads plugin hooks from `~/.claude/plugins/cache/prisma-local/prisma/<version>`. Running sessions keep the hook commands they started with but run the updated scripts at that path.
- **Codex hooks must be trusted;** the app (`Ajustes → Agentes`) and `install.sh` do it through the Codex app server.
- **Codex restarts its app server after `hooks/list`.** A request written after reading that answer gets `Broken pipe`; send the messages of each short session in one batch. `CODEX_HOME` must exist or app-server exits, and trust keys match the resolved path (`/private/var` vs `/var`), so resolve symlinks before comparing.
- **`windows/agents.py` reads `CODEX_HOME`, `CLAUDE_CONFIG_DIR` and `XDG_CONFIG_HOME` when imported.** Tests patch the module attributes; a real Codex trust test must also set `CODEX_HOME` in the environment because `codex app-server` inherits it.
- **The Windows installer requires Python 3.11 or 3.12** with Tkinter and the `py` launcher; `install.ps1` does not use Python 3.13.
- **`SIGPIPE` is ignored** in `main.swift` and in `CodexHookTrust.apply`; a helper that closes its input must not kill Prisma.
- **The app's marketplaces point at `~/Library/Application Support/Prisma/plugin-dist`.** Editing `plugin/` in the repository does nothing until the app rebuilds and reconnects (or `install.sh` runs again).
- **`install.sh` stops Prisma** with `pkill`. The `SIGTERM` handler restores ducked audio.
- **Read the port from `runtime.json`;** it can change.
- **Tests are audible.** Testing through the API speaks aloud and adds orbs. Use `engine: "apple"`, short texts, a test session id, and `POST /session/end` afterwards.
- **SourceKit reports false errors** for single files of this multi-file module. Check with `swift build` or `swiftc` instead.
- **Screen recordings and window polling** cannot measure 60 fps. Count frames in the app with temporary logging.

## 5. Working with this user

- Writes in Spanish and expects replies in Spanish. Every reply, and every question, ends with a `<ForPrisma>…</ForPrisma>` block of one to three spoken sentences without paths, code or Markdown (global instruction in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`).
- Iterates visually on the orb and notices any cut, jump or cross-fade ("se ve el corte"). Wants every change of state to look like the same light, and likes the liquid and bubble metaphor.
- Often asks to see the flow again: demonstrate it live through the local API, then end the test session.
- Asks for verification ("verifícalo"). Show frame sheets, measurements or recordings, not only claims.
- Installing during the work was approved. Commits, pushes and anything outward-facing need explicit approval.

## 6. Suggested next improvements

Ordered by priority. Each one should be verified the way this work was: tests, frame sheets for animation, live checks in the app.

1. **Unit tests for the session registry.** Extract the bookkeeping in `AppDelegate` (session orbs, owners, `handOver`, deferred ends, OpenCode folders and orphans, speech routing) into a type without AppKit and test it. Today it is verified only live.
2. **Lower idle cost.** The SwiftUI view graph is now the main cost, about 4 % CPU per waiting orb. Options:
   - Draw the background gradients inside the beam canvas.
   - Lower the waiting frame rate when many orbs are visible.
   - Move to a Core Animation or Metal renderer, without changing the look.

   Measure with `sample` and with in-app frame counts.
3. **Reduced motion.** Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`: slower spin, no sweep, shorter morphs.
4. **Codex orbs that follow the terminal.** Check whether Codex hooks run under the terminal's `codex` process. If they do, report its PID like Claude Code so a closed terminal removes its orb.
5. **OpenCode details.**
   - Verify the real `session.created` payload; only the mocked test covers it.
   - If prompts expose a client id, use it to tell apart windows in the same folder.
6. **Claude Code one-shot runs.** Decide with the user whether `claude -p` runs should show an orb at all; the hook PID's process arguments can tell them apart.
7. **Windows parity.** The Windows app has none of these features.
