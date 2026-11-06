# Prisma for Windows

This implementation adds a Windows system tray app using Prisma's local protocol. It includes notifications for Codex, Claude Code, and OpenCode; an animated orb; persistent settings; Edge Neural TTS; Piper; and a local Windows voice. It is separate from the macOS Swift app, and its appearance and some behavior differ. **Installation and operation still need to be validated on Windows**; automated tests run on macOS do not replace that validation.

## Requirements

- 64-bit Windows 10 or 11, an audio output device, and a graphical user session.
- 64-bit Python 3.11 or 3.12 with Tkinter, pip, and the `py` launcher. Check with `py -3 --version` and `py -3 -m tkinter`.
- Windows PowerShell and internet access to install packages and download the model. Edge requires internet for each synthesis; Piper and the system voice run locally.
- Codex, Claude Code, or OpenCode installed **natively on Windows**. Claude Code may require Git Bash depending on its installation. WSL and containers have separate paths, processes, and networking; this setup does not automatically connect hooks in those environments to Windows.
- If Piper or its dependencies fail to load, install the Microsoft Visual C++ Redistributable appropriate for your system.

## Install and update

Download `Prisma-Windows-1.0.2.zip` from [Releases](https://github.com/newton1057/Prisma/releases), extract it, and double-click **Instalar Prisma.cmd**. Windows SmartScreen may ask you to confirm because the script is not signed; choose **More info → Run anyway**. The installer does not need administrator rights.

To install from the repository instead, open PowerShell in the repository and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

The installer creates a virtual environment, installs the packages in `requirements.txt`, and downloads the Piper `es_MX-claude-high` model and configuration. The app, environment, model, settings, and logs are stored in `%LOCALAPPDATA%\Prisma`. It creates a Start menu shortcut and opens the app. The PowerShell execution policy exception applies only to this process.

It also copies `plugin/` and the Windows runtime files to `%LOCALAPPDATA%\Prisma` (`plugin-dist`), so the app can configure agents later without the repository or the extracted ZIP. Hooks use `"%LOCALAPPDATA%\Prisma\venv\Scripts\python.exe" "%LOCALAPPDATA%\Prisma\hook.py"`.

The installer configures the agents it finds:

- **Codex:** adds the voice instructions to `%CODEX_HOME%` (or `%USERPROFILE%\.codex`) `AGENTS.md`, merges the `Stop`, `PreToolUse`, and `PermissionRequest` hooks into `hooks.json`, and tries to mark them trusted through Codex's app-server protocol. If that fails, Codex may ask you to approve them when it opens.
- **Claude Code:** adds the instructions to `%USERPROFILE%\.claude\CLAUDE.md` and merges the same hooks into `%USERPROFILE%\.claude\settings.json`, or the folder set by `CLAUDE_CONFIG_DIR`.
- **OpenCode:** copies the plugin to `plugins\prisma.ts` and the skill to `skills\prisma\SKILL.md` under `%USERPROFILE%\.config\opencode`, or the folder set by `XDG_CONFIG_HOME`, then asks the CLI to reload.

Other settings are preserved, and a `.prisma-backup` copy is created before modifying each configuration file. If an existing file is not valid JSON, installation stops to avoid overwriting it. Agent commands and integration mechanisms can change between versions; if an agent is updated, reconnect it from Ajustes.

To update, close Prisma from its tray icon and run the new installer. It replaces the runtime files and the staged plugin but keeps the rest of your configuration and the virtual environment. Use the Start menu shortcut to open Prisma manually; hooks also try to start it when a notification arrives. The installer does not enable startup with Windows.

## Connect agents from Ajustes

Open the tray menu and choose **Ajustes**. The **Agentes** section lists Codex, Claude Code, and OpenCode with a status dot and the action for each:

These connections cover **local sessions on this PC**. Cloud sessions, WSL, containers, and agents running on another machine do not execute the hooks or plugin installed here.

- **Green — Conectado:** the hooks, instructions, and plugin are present. **Reconectar** refreshes them; **Desconectar** removes only Prisma's changes.
- **Orange — Falta…:** part of the integration is missing, for example hooks, instructions, the plugin, or Codex's hook trust. **Conectar** completes it.
- **Gray — No conectado:** nothing from Prisma is installed for that agent. **Conectar** adds it.
- **Light gray — No encontrado en este PC:** the agent's CLI is not on `PATH`. The row offers no button until it is installed.

Connections are detected leniently: hooks written by an older Prisma install still count, and an OpenCode plugin installed by hand is compared with the staged copy and marked **Plugin desactualizado** when it differs. The status refresh happens when Ajustes opens and after every action.

The connections run in a background worker, so the window remains responsive while Codex is being trusted. Warnings appear below the agent rows. Restart any open agent session so it loads new hooks; connecting again is enough if you install an agent after Prisma.

## Test and configure

Open Prisma's system tray menu and select **Probar voz** (Test voice). You can also send tests from the extracted folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Text "Hello, this is Dalia." -Voice dalia
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Engine piper
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Engine windows
```

The current interface uses Spanish labels. In **Ajustes**, change the engine, Edge voice, reading mode, speed, halo colour, orb position, visibility, and ducking. The `windows` engine uses a voice installed on the system; its language depends on Windows settings and installed voices. Edge defaults to Ava and supports `andrew`, `emma`, `brian`, `dalia`, `jorge`, `salome`, `ximena`, `alvaro`, and `elena`. If Edge fails, Prisma tries Piper and then the Windows voice; if Piper fails, it tries the Windows voice. The Piper model is a Spanish-language voice.

## The orb

The orb is a Pillow port of the macOS `PrismaBeam` and `SiriLiquidGlassOrbView` layers: curved light beam, conic palette, bloom, spectrum and core, smoked glass, lower voice glass, rim, sheen, halo and ambient glow. It is drawn on a 220×220 transparent canvas with a 198 px orb and shown at 180×180. macOS uses a native backdrop blur behind the glass; on Windows the glass is simulated with gradients and a dark translucent body, so the interior reads similar but not identical.

- **Waiting:** a folded loop of light that drifts around the glass.
- **Thinking:** the loop tightens and ripples.
- **Speaking:** the light opens into an arc above a lit lower hemisphere with bright refractions along the bottom. The animation does not measure the microphone; the arc follows a synthetic meter.
- **Colour:** ten halo palettes from the macOS app. Choose one in **Ajustes → Color del halo**; `Prisma Original (Ámbar y Zafiro)` is the default and matches macOS.

The overlay is a layered Win32 window with per-pixel transparency, painted from its own thread at up to 30 fps. The glass edge and halo blend with whatever is behind them, clicks pass through, and the window stays out of the taskbar and Alt-Tab. A frame costs about 15 ms, so keep the app on a machine that can spare one core. Transitions use the macOS timing: 1.05 s to the voice pose and 1.4 s back, with the light crossfading between the two shapes so nothing jumps when speech starts or stops.

The orb appears on the primary display. Windows ducking lowers existing audio sessions from other apps on the default device and attempts to restore their levels afterward; if a user changes a level during the notification, Prisma respects that change. Sessions started after the notification begins are not included, and ducking does not move when the output device changes. A forced exit can prevent restoration; use the Windows volume mixer to adjust levels manually if needed.

## Privacy and security

The server listens only on `127.0.0.1`, chooses a port from 8787 through 8798, and requires a token to speak or stop. The active port and token are stored in `%LOCALAPPDATA%\Prisma\runtime.json`, accessible to the local user. Edge sends notification text to its synthesis service; choose Piper or Windows for local synthesis. The installer downloads dependencies and the model from the internet. Piper and its dependencies have their own licenses; review them before redistributing the project.

## Troubleshooting

- **No tray icon:** find Prisma in the Start menu and check the hidden tray icons. See `%LOCALAPPDATA%\Prisma\prisma.log`.
- **The app speaks but the agent does not notify:** restart the agent, open **Ajustes → Agentes**, and press **Reconectar**. Check that hooks are enabled and trusted, and inspect `%LOCALAPPDATA%\Prisma\hook.log`.
- **Codex keeps asking to trust hooks:** the app-server trust step failed, usually because Codex is not on `PATH` for the app or its version changed. Open Codex and accept the hooks, or reconnect from Ajustes after checking the CLI.
- **Edge is silent:** check the connection or select Piper or Windows. Piper needs both the `.onnx` model and its `.onnx.json` file.
- **Another app's volume was not restored:** check the Windows volume mixer. You can disable ducking in settings.
- **The installer cannot find Python or Tkinter:** install Python with the components above and check that `py -3 -m tkinter` opens a window.
- **The agent runs in WSL:** use a native Windows agent or configure an integration for that environment; the installer does not do this automatically.

## Validation

Run the portable tests with `python -m unittest discover -s tests -v`. They cover text extraction, questions, hook configuration, the agent connection merge/removal and idempotency, OpenCode files, missing CLIs, the Codex trust protocol with a fake app server, orb rendering and transitions, layered-window packing, and the local protocol. To look at the renderer without the app, run `py -3 -m orb <folder>` from the `windows` folder; it writes one PNG per state. On a Windows machine, the remaining checks include a clean installation from the ZIP; all three agent integrations and their questions; token authentication and alternate ports; playback and cancellation for all three engines; the tray, the orb at every halo colour, its placement and click-through; and mixer restoration after manual changes and exits.
