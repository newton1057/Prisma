# Prisma for Windows

This implementation adds a Windows system tray app using Prisma's local protocol. It includes notifications for Codex, Claude Code, and OpenCode; an animated orb; persistent settings; Edge Neural TTS; Piper; and a local Windows voice. It is separate from the macOS Swift app, and its appearance and some behavior differ. **Installation and operation still need to be validated on Windows**; automated tests run on macOS do not replace that validation.

## Requirements

- 64-bit Windows 10 or 11, an audio output device, and a graphical user session.
- 64-bit Python 3.11 or 3.12 with Tkinter, pip, and the `py` launcher. Check with `py -3 --version` and `py -3 -m tkinter`.
- Windows PowerShell, Git, and internet access to install packages and download the model. Edge requires internet for each synthesis; Piper and the system voice run locally.
- Codex, Claude Code, or OpenCode installed **natively on Windows**. Claude Code may require Git Bash depending on its installation. WSL and containers have separate paths, processes, and networking; this setup does not automatically connect hooks in those environments to Windows.
- If Piper or its dependencies fail to load, install the Microsoft Visual C++ Redistributable appropriate for your system.

## Install and update

Open PowerShell, go to the repository, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

The installer creates a virtual environment, installs the packages in `requirements.txt`, and downloads the Piper `es_MX-claude-high` model and configuration. The app, environment, model, settings, and logs are stored in `%LOCALAPPDATA%\Prisma`. It creates a Start menu shortcut and opens the app. The PowerShell execution policy exception applies only to this process.

The installer adds global voice instructions and configures Codex hooks in `%CODEX_HOME%` or `%USERPROFILE%\.codex`. It also configures Claude Code hooks if detected and copies the OpenCode plugin if it finds its configuration or command. Other settings are preserved, and a `.prisma-backup` copy is created before modifying each configuration file. If an existing file is not valid JSON, installation stops to avoid overwriting it. Rerun the installer after adding an agent and restart the agent to load the changes.

Codex may ask you to review and trust hooks before running them; the installer does not bypass that check. Agent commands and integration mechanisms can change between versions.

To update, close Prisma from its tray icon, update the repository, and rerun the installer. Use the Start menu shortcut to open it manually; hooks also try to start it when a notification arrives. The installer does not enable startup with Windows.

## Test and configure

Open Prisma's system tray menu and select **Probar voz** (Test voice). You can also send tests from the repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Text "Hello, this is Dalia." -Voice dalia
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Engine piper
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Engine windows
```

The current interface uses Spanish labels. In **Ajustes** (Settings), change the engine, Edge voice, reading mode, speed, orb position, visibility, and ducking. The `windows` engine uses a voice installed on the system; its language depends on Windows settings and installed voices. Edge defaults to Ava and supports `andrew`, `emma`, `brian`, `dalia`, `jorge`, `salome`, `ximena`, `alvaro`, and `elena`. If Edge fails, Prisma tries Piper and then the Windows voice; if Piper fails, it tries the Windows voice. The Piper model is a Spanish-language voice.

The orb pulses during playback, appears on the primary display, and attempts to let clicks pass through. Its animation does not measure actual audio amplitude. Windows ducking lowers existing audio sessions from other apps on the default device and attempts to restore their levels afterward; if a user changes a level during the notification, Prisma respects that change. Sessions started after the notification begins are not included, and ducking does not move when the output device changes. A forced exit can prevent restoration; use the Windows volume mixer to adjust levels manually if needed.

## Privacy and security

The server listens only on `127.0.0.1`, chooses a port from 8787 through 8798, and requires a token to speak or stop. The active port and token are stored in `%LOCALAPPDATA%\Prisma\runtime.json`, accessible to the local user. Edge sends notification text to its synthesis service; choose Piper or Windows for local synthesis. The installer downloads dependencies and the model from the internet. Piper and its dependencies have their own licenses; review them before redistributing the project.

## Troubleshooting

- **No tray icon:** find Prisma in the Start menu and check the hidden tray icons. See `%LOCALAPPDATA%\Prisma\prisma.log`.
- **The app speaks but the agent does not notify:** restart the agent, rerun the installer if the agent was installed later, check that hooks are enabled and trusted, and inspect `%LOCALAPPDATA%\Prisma\hook.log`.
- **Edge is silent:** check the connection or select Piper or Windows. Piper needs both the `.onnx` model and its `.onnx.json` file.
- **Another app's volume was not restored:** check the Windows volume mixer. You can disable ducking in settings.
- **The installer cannot find Python or Tkinter:** install Python with the components above and check that `py -3 -m tkinter` opens a window.
- **The agent runs in WSL:** use a native Windows agent or configure an integration for that environment; the installer does not do this automatically.

## Validation

Run the portable tests with `python -m unittest discover -s tests -v`. They cover text extraction, questions, hook configuration, and the local protocol. On a Windows machine, the remaining checks include a clean installation; all three agent integrations and their questions; token authentication and alternate ports; playback and cancellation for all three engines; the tray and orb; and mixer restoration after manual changes and exits.
