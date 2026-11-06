# Handoff: orb animation and session orbs

Date: 2026-11-05
For: the next agent continuing work on Prisma (macOS)
Technical reference: [Orb animation and session orbs](orb-and-sessions.md)

## 1. State of the repository

- **v1.0.0 released.** Tag `v1.0.0` points at `5e9d152` on `origin/main`; the DMG is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.0) (SHA-256 `abae9fd3…`).
- **v1.0.1 released (macOS).** Tag `v1.0.1` points at `94bb53b`; the DMG is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.1) (SHA-256 `455eff272ee804a6795061cb7e95ba49091c0af250aa237a9443fcb488976a54`). The app connects Codex, Claude Code and OpenCode from **Ajustes → Agentes** without the repository.
- **v1.0.2 released (macOS, 2026-11-04).** Tag `v1.0.2` points at `6390b26` on `origin/main`; the DMG is in [Releases](https://github.com/newton1057/Prisma/releases/tag/v1.0.2) (SHA-256 `cbe7f74835cc2bc06cb213568b2dd71ae36e31fcfb33136ad2339db96915123d`). This is the first version with the bucket updater: it checks `prisma-updates` at launch and every six hours. The signing key is in the login keychain under **Prisma actualizaciones**, with a `600` backup at `~/Library/Application Support/Prisma/firma-actualizaciones.txt`; restore it with `UpdateSigner restaurar`. Bucket `prisma-updates` exists in `system-kn` with public read-only access and no listing. The first updater version must be installed by hand; 1.0.1 and earlier cannot update themselves.
- **Windows 1.0.1 released.** Tag `windows-v1.0.1` points at `fc9b9c1`; `Prisma-Windows-1.0.1.zip` is published in [Releases](https://github.com/newton1057/Prisma/releases/tag/windows-v1.0.1) (SHA-256 `3a3aa86a1e2f4fba2856a5cca00540adaab35e9d41158cc4a8967ce0ac7d3a0f`). It is intentionally **not** marked Latest so the macOS DMG stays Latest. The ZIP adds the Windows **Ajustes → Agentes** section and a portable plugin copy; it still needs end-to-end validation on a real Windows machine.
- **Windows 1.0.2 released (orb).** Tag `windows-v1.0.2`; `Prisma-Windows-1.0.2.zip` is in [Releases](https://github.com/newton1057/Prisma/releases/tag/windows-v1.0.2) (SHA-256 `a87c19fe61a458aee702e255a8d6f32c62134741df5361190d812a283d92e1a0`), also not marked Latest. This replaces the Tk circles and the grey square with the macOS-style orb on a layered window, adds the ten halo palettes and **Ajustes → Color del halo**.
- **Windows 1.0.3 released (updater).** Tag `windows-v1.0.3`; `Prisma-Windows-1.0.3.zip` is in [Releases](https://github.com/newton1057/Prisma/releases/tag/windows-v1.0.3) (SHA-256 `ded494d327d287d87e9aca33b84bc55d002a36ddd5e3b6f943bf057a3dbfd85a`). It is marked Latest because it is the most recently published release; GitHub keeps only one, so macOS `v1.0.2` lost that badge. This is the first Windows version with the signed bucket updater: it checks `windows-latest.json` at launch and every six hours, verifies the Ed25519 signature and the ZIP size/SHA-256, validates the version and build, and replaces the runtime after the app exits. Settings, the virtual environment and the voice model are preserved; a failed requirement install restores the previous runtime. **Ajustes → Actualizaciones** and the tray menu expose the check and the available version. 1.0.2 and earlier must install 1.0.3 by hand once. Published with `tools/publicar-windows.sh`.
- **v1.0.4 released (unified).** Tag `v1.0.4`; one GitHub release carries `Prisma-1.0.4.dmg` for macOS and `Prisma-Windows-1.0.4.zip` for Windows (DMG SHA-256 `6a0b4ebdda8cda31419d70625a4da7c5720f3b82f2ae26141330a2bf625f1d04`; Windows ZIP SHA-256 `eec50145eccf0a35423493245908521b52500ddc51a8e706e5e32c5a2488febe`), marked Latest. Both apps share version 1.0.4 and build 4, and the bucket serves `latest.json` and `windows-latest.json` at build 4 (macOS bucket ZIP `f152ec8e94fe51dbf97bb85ab65d1caee8bde23013d41c7c889b6f2a907cfde7`). macOS 1.0.2 and Windows 1.0.3 update through the bucket; Windows 1.0.2 and earlier install by hand once. Published with the new shared `tools/publicar.sh`.
- **v1.0.5 released (Muse Code + Antigravity).** Tag `v1.0.5`; one GitHub release carries `Prisma-1.0.5.dmg` (SHA-256 `12ca9b5c4cf3a6be3281ff7a1559ae34c5979e29f6ad86e987a2f1a162527aeb`) and `Prisma-Windows-1.0.5.zip` (SHA-256 `94705f3cc13e21b1978022ba87bd178eb9293f8ec48e8d33ddcdb0d6934b306b`), marked Latest. Both apps share 1.0.5 / build 5; the bucket serves `latest.json` and `windows-latest.json` at build 5 (macOS bucket ZIP `73e0034c82a51bf4ea693adeba6ae78d253cccc84da4baae08e4874c8d85e53e`). Verified: both signatures, sizes and hashes; the GitHub digest for the Windows ZIP equals the bucket hash; the macOS ZIP carries 1.0.5 / build 5 / `com.newton.prisma`, and the Windows ZIP carries `VERSION = '1.0.5'` / `BUILD = 5`, the updater files and the new agent integrations.
- **Installed and running (1.0.4 dev build).** `~/Applications/Prisma.app` was rebuilt and reinstalled from this repository on 2026-11-05 (same 1.0.4 / build 4 as the published release, with the new agent sources). `./install.sh` connected all five agents on this Mac, including Muse Code and Antigravity. Live checks passed: a real `muse exec` echo run and a real `agy -p` run fired Prisma's hooks, and short simulated sessions produced the thinking orb and speech. With `v1.0.5` published, this install can update itself through the bucket on its next check.
- **Tests pass:** Swift (motion, themes, activity scale, window detection for all five agents, Codex monitor, agent connections including Muse Code and Antigravity, update manifest signature and SHA-256), Python (hooks; Windows app, orb renderer, layer packing, agent connections and signed updates, 63 tests), Node (OpenCode flow). Commands are in [section 8.1](orb-and-sessions.md#81-automated-tests) of the reference.

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

### Windows orb session (2026-11-05)

1. **Why.** A Windows user's screenshot showed the old Tk orb: five flat concentric circles inside a grey square. The square was `-transparentcolor` failing on antialiased edges and the circles were the placeholder animation.
2. **New renderer.** `windows/orb.py` ports `PrismaBeam` and `SiriLiquidGlassOrbView` to Pillow: curved beam geometry, conic palette, bloom/spectrum/core light, smoked glass, lower voice glass, rim, sheen, aura and idle glow. 220×220 canvas, 198 px orb, shown at 180×180. Ten macOS halo palettes with `prisma` as the default; **Ajustes → Color del halo**.
3. **Transparency.** `windows/overlay.py` replaces the Tk canvas with a Win32 layered popup that paints premultiplied BGRA through `UpdateLayeredWindow`, so edges and the halo blend with the desktop and clicks pass through. No key colour, no grey square, no taskbar entry.
4. **Motion.** `OrbAnimator` follows macOS `stateChanged`: 1.05 s to the voice pose, 1.4 s back, smoothstep. Aura and idle glow scale their alpha continuously, and the moving light crossfades between the loop and voice paths around voice 0.06 instead of swapping in one frame; regression tests check that the handoffs at 0.001, 0.06 and 1.0 do not jump.
5. **Cost.** About 13 ms per idle frame and 15 ms per voice frame at 30 fps, measured on this Mac; the crossfade frames cost about 29 ms.
6. **Pending validation.** All of it needs a real Windows machine: layered-window composition, DPI scaling, placement, click-through, the tray menu and the actual look next to the macOS orb.

### Updater session (2026-11-04)

1. **Bucket updater adapted from IconicOS Studio.** New `UpdateCore` (manifest, Ed25519 signature, SHA-256), `UpdateSigner` (keychain key, sign and verify), `Updater.swift` (ephemeral URLSession, manifest check, download, signature/size/hash/bundle check, installer script) and tests. `Package.swift` gains the three targets; `app/Info.plist` gains `PrismaUpdatesEnabled`.
2. **App integration.** The updater checks at launch and every six hours, shows a banner in **Ajustes**, and adds **Buscar actualizaciones…** / **Actualizar a la versión X…** to the menu bar. It stays disabled in the development copy next to `Package.swift`; `PRISMA_ACTUALIZACIONES_URL` and `PRISMA_APP_SUPPORT` exist for local tests.
3. **Publishing.** `app/empaquetar.sh` produces the macOS `dist/Prisma-<version>.zip` and `.dmg`; the shared `tools/publicar.sh` builds and verifies both platforms, signs `latest.json` and `windows-latest.json`, creates one GitHub release with the DMG and the Windows ZIP, and uploads both ZIPs and manifests to `prisma-updates`. `app/verificar_paquete.py` blocks credentials in the public package.
4. **Verified and published.** 1.0.1 → 1.0.2 update and reopen; tampered manifest rejected; wrong `CFBundleIdentifier` rejected; read-only location rejected; corrupted ZIP rejected (`el archivo descargado no coincide con la versión publicada`, installed version stayed 1.0.2); package signature and `codesign --verify --deep --strict` pass. The bucket is created, the 1.0.2 DMG and manifest are published, and the real 1.0.2 app in `~/Applications` reports `al día`. All local test apps, servers and temporary folders were removed afterwards. Pending: the full step-9 checklist on another Mac and with a non-admin account, and a real 1.0.2 → next-version update (the first updater version could only be installed by hand).

### Windows updater session (2026-11-05)

1. **Why.** The macOS app had the bucket updater; the Windows app had no update path at all. Windows now checks a separate `windows-latest.json` so macOS and Windows builds can advance independently, using the same Ed25519 key and the same signed text layout as `UpdateManifest`.
2. **Verification.** `windows/updater.py` implements RFC 8032 verification in pure Python, so no compiled crypto dependency is needed. It also checks the manifest field types and paths, the ZIP size and SHA-256, and the `VERSION`/`BUILD` inside the staged `common.py`; extraction rejects traversal, absolute paths, symlinks, encrypted entries and oversized archives.
3. **Install.** The app downloads into `%TEMP%`, prepares and verifies the package, then launches `windows/update_helper.py` with pythonw and exits. The helper waits up to 60 s for the app PID, replaces the `*.py` runtime, `requirements.txt` only when it changed, and `plugin-dist/plugin`; it leaves settings, the venv, voices and logs alone. A failed requirements install restores the previous runtime. It then retries opening `app.py` and logs every step to `prisma.log`.
4. **UI.** Automatic checks run at launch and every six hours. **Ajustes → Actualizaciones** shows the current build, the available notes, progress and a retry button; the tray menu changes to **Actualizar a la versión X…**. Installation is deferred with `Espera a que Prisma termine de hablar.` while speech is active. `/health` now includes `build`.
5. **Publishing.** The Windows ZIP is part of the shared release now: `tools/publicar.sh` requires matching versions and builds, a clean pushed branch and a build greater than both published manifests, runs `tools/package-windows.sh`, signs with the macOS `UpdateSigner`, uploads `windows/versiones/<version>/Prisma-Windows-<version>.zip` and writes `windows-latest.json` last. The old per-platform publishers were removed.
6. **Tests.** 48 Python tests pass, including the real signature over a fixture signed by `UpdateSigner`, tampering of every signed field, wrong types and paths, download size/progress, zip-slip and absolute paths, version/build mismatch, runtime replacement and rollback, and the existing orb and agent suites.
7. **First updater version.** 1.0.2 and earlier cannot update themselves: install 1.0.3 by hand once, and later builds update in place. The real Windows install/replace/reopen path still needs a Windows machine.
8. **Published and verified.** The bucket serves `windows-latest.json` with build 3 and a valid signature (checked both with the app's verifier and `UpdateSigner verificar`); the public ZIP size and SHA-256 match the manifest; and it contains `updater.py`, `update_helper.py` and `VERSION = '1.0.3'` / `BUILD = 3`. The Windows release was later marked Latest at the user's request, so the badge follows the most recently published release instead of staying with macOS; macOS `latest.json` remains at build 2. Remaining: the real replace/reopen test on Windows, with 1.0.3 installed by hand and a later build published.

### Unified release session (2026-11-05)

1. **Why.** The user asked for one release per version carrying both platforms, so the download page, the version number and the publishing flow stop being per-platform.
2. **Versioning.** macOS `CFBundleShortVersionString` / `CFBundleVersion` in `app/Info.plist` and Windows `VERSION` / `BUILD` in `windows/common.py` are now 1.0.4 / 4 on both sides. macOS skips 1.0.3 on purpose; the updaters compare builds (2 and 3 to 4), so every installed app receives it.
3. **Shared publisher.** `tools/publicar.sh` builds `app/empaquetar.sh` and `tools/package-windows.sh`, runs `app/verificar_paquete.py`, signs `latest.json` and `windows-latest.json`, creates one GitHub release with the DMG and the Windows ZIP marked Latest, uploads both packages and then both manifests, and verifies the published copies. It refuses to run when the versions or builds differ, the branch is dirty or unpushed, or the build is not greater than both published manifests. `app/publicar.sh` and `tools/publicar-windows.sh` were removed.
4. **Verified.** Independent checks: the app's pure-Python verifier accepts both manifests, sizes and SHA-256 match (`f152ec8e…` for the macOS ZIP, `eec50145…` for the Windows ZIP), the GitHub asset digest for the Windows ZIP equals the bucket hash, the macOS ZIP carries 1.0.4 / build 4 and `com.newton.prisma`, the Windows ZIP carries `VERSION = '1.0.4'` / `BUILD = 4` plus the updater files, and `v1.0.4` is the repository's Latest with both assets.
5. **Pending.** The real Windows install/replace/reopen path still needs a Windows machine; the macOS 1.0.2 installed here can exercise the 1.0.2 → 1.0.4 update on its next check.

### Muse Code and Antigravity session (2026-11-05)

1. **Why.** The user asked to integrate Muse Code CLI (Meta) and Antigravity CLI (Google) like the existing agents: orbs, thinking state, spoken replies, questions, and connect/disconnect from Ajustes on both platforms.
2. **Research.** Muse Code 1.4 and Antigravity CLI 1.3 are installed on this Mac. Their hook mechanisms were verified live: Muse Code user hooks live in the `hooks` block of `$XDG_CONFIG_HOME/muse/settings.json` (or `~/.config/muse/settings.json`), accept `statusMessage`, and reject a synchronous `Interrupt` hook (`async: true` required); its payload is Claude-compatible (`hook_event_name`, `session_id`, `cwd`, `transcript_path`, `last_assistant_message`), and user rules load from `$XDG_CONFIG_HOME/muse/AGENTS.md`. Antigravity hooks live in the global `~/.gemini/config/hooks.json` (named entries; `PreToolUse` groups have matchers; other events take bare handler lists) and payloads are camelCase (`conversationId`, `transcriptPath`, `workspacePaths`) with no message field; the reply is the last `MODEL`/`PLANNER_RESPONSE` line of `brain/<id>/.system_generated/logs/transcript_full.jsonl`. An Antigravity `PreToolUse` that answers `{}` denies the tool, so the hook answers `{"decision":"allow"}`.
3. **macOS.** `AgentKind` gained `muse` and `antigravity`; `AgentPaths` resolves the Muse config directory and the Antigravity customization directory; the installer merges only its entries (first-change `.prisma-backup`, `schema_version` preserved, files removed when nothing else was in them) and appends the `<ForPrisma>` block to both rules files. `MuseWindows` and `AntigravityWindows` detect open windows (excluding one-shot and non-chat subcommands) and provide window orbs like Claude Code; `AppDelegate` treats both sources as window-owned sessions, gained hover names, and per-agent halo themes (`museTheme`, `antigravityTheme`, defaults nebula and esmeralda). `on_turn.sh` and `on_stop.sh` read both key spellings, pass the source explicitly, walk to the agent process for the `pid`, and send the Antigravity workspace as the orb folder.
4. **Windows.** `agents.py` gained Muse Code (`%USERPROFILE%\.config\muse\settings.json` with `schema_version`) and Antigravity (`%USERPROFILE%\.gemini\config\hooks.json` named entry) status, connect and disconnect; `hook.py` accepts `source` / `event` arguments, normalizes Antigravity payloads and skips speech on an errored Antigravity stop; `common.transcript_text` reads Antigravity transcripts; `install.py` and the Ajustes fallback list include both agents. `install.sh` connects both on macOS.
5. **Verified.** Swift tests: agent connections (Muse merge/idempotency/removal/backups, Antigravity named-entry preservation, always-`allow` gate) and window detection for both; Python: 63 tests including a new `test_muse_antigravity_hooks.py` that exercises session lifecycle, Stop speech, stale-reply rejection, questions, the `allow` decision and the errored-stop silence, plus Windows merge/removal/transcript tests. Live on this Mac: `install.sh` connected both agents, a real `muse exec` echo run and a real `agy -p` run fired the hooks through the installed app (the Antigravity model even replied with its `<ForPrisma>` block), and short simulated sessions produced the thinking state and speech.
6. **Pending.** A real Muse Code model run could not be exercised here (the account returns a billing error), so its interactive TUI, question tool and interrupt path are only covered through captured payloads and the echo provider. Antigravity's `ask_question` was exercised in headless mode, where the question is auto-skipped, so its interactive answer flow still needs a live session. The Windows side and the focus-click behavior for the new orbs have not been tested either. Committed as `8a0b975` (docs `07502c9`, version bump `69d5232`); released as `v1.0.5`.

## 3. Resume work

```bash
cd ~/Desktop/Prisma
./app/build.sh                     # build only (app/Prisma.app)
./install.sh                       # full install: app, scripts, and the agents it finds (Codex, Claude Code, OpenCode, Muse Code, Antigravity)
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

Session orbs reappear within 2 s: Codex `resume` clients and every Claude Code, OpenCode, Muse Code and Antigravity window are detected by process. After changing `plugin/`, rebuild the app and press **Reconectar** in **Ajustes → Agentes** (or run `./install.sh`); Claude Code runs its hooks from the plugin cache.

To publish one release for macOS and Windows (same version and build in `app/Info.plist` and `windows/common.py`):

```bash
./tools/publicar.sh "What changed in this version"
```

To rebuild only the Windows release ZIP:

```bash
./tools/package-windows.sh   # dist/Prisma-Windows-<version>.zip
```

## 4. Gotchas

- **OpenCode's plugin runs in a daemon** (`opencode serve --service`). `process.pid` there is not a window, and there are no client connect or disconnect events. Window detection lives in Prisma (`OpenCodeWindows.swift`).
- **Never use `minimumInterval: 1/60`** in `TimelineView`; see [section 3.3](orb-and-sessions.md#33-frame-rate) of the reference.
- **Never scale `NSVisualEffectView` per frame** or reassign its properties in `updateNSView`; it re-renders its material.
- **Claude Code** loads plugin hooks from `~/.claude/plugins/cache/prisma-local/prisma/<version>`. Running sessions keep the hook commands they started with but run the updated scripts at that path.
- **Codex hooks must be trusted;** the app (`Ajustes → Agentes`) and `install.sh` do it through the Codex app server.
- **Muse Code user hooks live in `~/.config/muse/settings.json`** and the file must keep `"schema_version": 1`; a synchronous `Interrupt` hook is rejected (declare `"async": true`), and user rules load from `~/.config/muse/AGENTS.md`. Its Stop hook already carries `last_assistant_message`, so no transcript parsing is needed.
- **Antigravity hooks run with the working directory set to `~/.gemini/config`**, so commands need absolute paths, and a `PreToolUse` hook that answers `{}` denies the tool: Prisma's gate answers `{"decision":"allow"}` to keep Antigravity's own policy in charge. Replies are read from the newest `MODEL`/`PLANNER_RESPONSE` line of `brain/<id>/.system_generated/logs/transcript_full.jsonl`; a `content` that is not a string means the turn called a tool and nothing should be spoken.
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
