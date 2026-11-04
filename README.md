<div align="center">

# ◈ Prisma

### Your agent finished. Prisma tells you about it.

Voice notifications and an animated orb for your coding agents on macOS and Windows.

**Codex · Claude Code · OpenCode**

[Installation](#installation) · [How it works](#how-it-works) · [Settings](#settings) · [Troubleshooting](#troubleshooting)

</div>

---

You don't have to watch the terminal while an agent works. Prisma lets you get on with something else and hear when your agent finishes, what it did, or what it needs from you.

An animated floating orb appears with each notification. Prisma can also lower background audio while it speaks and restore it afterward. On macOS, the orb reacts to audio; on Windows, it uses a pulsing animation.

## Features

- **Completion and question notifications.** Hear updates and requests for information or confirmation from Codex, Claude Code, and OpenCode.
- **Summaries made for listening.** Agents are instructed to add a short voice block to their responses; Prisma extracts and cleans it before speaking.
- **A choice of voices.** Use Edge Neural TTS, local Piper, or a system voice. The default is Ava Multilingual; if Edge fails, Prisma tries Piper and then the system voice.
- **Configurable orb.** Choose its position, whether it remains visible briefly after speaking, and independent halo color themes (10 palettes) for Codex, Claude Code, and OpenCode.
- **Interactive session orbs (macOS).** Waiting orbs stay compact and semi-transparent (50% opacity) so you can see behind them, expand individually to 95% opacity when thinking, speaking, or hovered, unfold a liquid-glass info capsule with the agent name and session title on hover, and focus their exact terminal window and tab when clicked.
- **Adjustable background audio.** Temporarily lower background audio while Prisma speaks, or disable ducking altogether.

## Requirements

### macOS

- **macOS 15 or later.** Prisma builds as a native Swift app. The published DMG is for Apple Silicon.
- **Apple developer tools** with Swift, plus Git, Python 3 with `venv`, `curl`, and `jq`. For example, install the command line tools with `xcode-select --install` and `jq` with `brew install jq` if you use Homebrew.
- At least one supported agent: Codex, Claude Code, or OpenCode.
- Internet access to install dependencies, download the Piper model, and use Edge Neural TTS. Piper and the Apple voice can work offline once prepared.

### Windows

- Windows 10 or 11, 64-bit Python 3.11 or 3.12 with Tkinter and the `py` launcher, PowerShell, and Git.
- At least one supported agent installed natively on Windows.
- Internet access to install dependencies, download Piper, and use Edge Neural TTS.

## Installation

### macOS

Download the latest **Prisma.dmg** from [Releases](https://github.com/newton1057/Prisma/releases), drag **Prisma** to **Applications**, and open it. The published DMG is for Apple Silicon. The app is signed locally but not notarized, so the first launch may ask for confirmation: right-click → Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Prisma.app
```

Without extra dependencies Prisma speaks with the system voice. For the neural voices (Edge and Piper), clone the repository and run `setup_voice.sh` once:

```bash
git clone https://github.com/newton1057/Prisma.git ~/Desktop/Prisma
cd ~/Desktop/Prisma
./setup_voice.sh
./install.sh
```

`setup_voice.sh` creates a Python environment, installs `piper-tts` and `edge-tts`, and downloads the Piper voice model (about 60 MB). The model is not included in the repository.

`install.sh` builds everything from source and copies it to `~/Applications/Prisma.app`, preparing voice and configuration files in `~/Library/Application Support/Prisma/`. It also configures the three agents directly; the app can do the same from its settings, as described below.

#### Connecting your agents

Open **Prisma → Ajustes… → Agentes** and press **Conectar** next to Codex, Claude Code, or OpenCode. The app installs the hooks, instructions and plugin in your user folder (`~/.codex`, `~/.claude`, `~/.config/opencode`), so it does not need the repository or the DMG's contents afterward. Only the agent's CLI must be installed; when it is missing, the row says so instead of offering the button. **Desconectar** removes only Prisma's changes and leaves the rest of your agent configuration untouched.

Notifications cover **local sessions**. Sessions that run in the cloud or on another machine do not execute the hooks or plugin installed on your Mac, so Prisma cannot announce them.

The hooks read their events with `jq`; if it is missing, Ajustes shows a warning and you can install it with `brew install jq`. Restart any open agent session to load the new hooks. If you install an agent after Prisma, come back to this section instead of rerunning the installer.

To check the installation, select **Probar voz** (Test voice) from Prisma's menu bar icon, or run:

```bash
./test.sh "Hello. Prisma is working on your Mac."
```

Then start or restart an agent and ask it to complete a short task. To check question notifications, ask it to use an interactive question tool.

### Windows

Download `Prisma-Windows-1.0.1.zip` from [Releases](https://github.com/newton1057/Prisma/releases), extract it, and double-click **Instalar Prisma.cmd**. Windows SmartScreen may ask you to confirm; choose **More info → Run anyway**. The installer needs no administrator rights.

Alternatively, clone the repository and run the installer in PowerShell:

```powershell
git clone https://github.com/newton1057/Prisma.git
cd Prisma
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

The installer prepares the environment and voices in `%LOCALAPPDATA%\Prisma`, creates a Start menu shortcut, configures the agents it finds, and opens Prisma. Open the tray menu → **Ajustes → Agentes** to connect, reconnect, or disconnect Codex, Claude Code, and OpenCode later; it installs everything in your user folder and does not need the repository afterward. Restart open agent sessions to load new hooks. Codex may still ask you to approve its hooks if automatic trust fails. The orb appears on the primary display and the app is controlled from the system tray. As on macOS, notifications cover **local sessions** only; cloud sessions and sessions on other machines do not run these hooks.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Text "Hello. Prisma is working on Windows."
```

See the [Windows guide](docs/windows.md) for requirements, agent connections, settings, troubleshooting, and outstanding validation. **The Windows implementation still needs to be tested on a Windows machine.**

## How it works

```text
Codex / Claude Code / OpenCode
          │
          │  final response or question
          ▼
 Prisma integration
          │
          │  text prepared for speech
          ▼
 Prisma on macOS or Windows ──► voice + animated orb
```

The integrations ask the agent to include a block like this at the end of its responses:

```xml
<ForPrisma>
I finished the changes and checked that they work.
</ForPrisma>
```

Prisma reads the last valid block and ignores tags mentioned in code examples. If the agent omits it, Prisma falls back to the available text and removes links and Markdown, so the notification may be longer. For interactive questions, it can also build an announcement from the question and its options.

The Codex and Claude Code hooks and the OpenCode plugin send notifications to an app server listening on `127.0.0.1`. Speak and stop requests require a local token. The app uses the first available port in its range and records the active port in `runtime.json`.

## Settings

On macOS, Prisma can show the voice orb as soon as Codex, Claude Code, or OpenCode receives a message. While thinking, its prism light bends into a softly rotating iridescent ring within the glass; when the reply arrives, the ring opens and unrolls into the voice horizon, which reacts to the voice. Enable or disable it under **Animación → Mostrar el orbe mientras el agente piensa**. The setting is enabled by default; restart the agent after installing to load its integration. An interruption returns the session's orb to its waiting appearance. Claude Code has no hook for interruptions, so Prisma notices the interruption Claude Code writes to the session transcript; it reads only the lines added during that turn.

Codex, Claude Code, and OpenCode sessions have separate persistent orbs, arranged side by side and wrapped into additional rows if needed. Between turns, each orb rests in a compact, semi-transparent state (50% opacity) so the menu bar and windows behind it remain visible. When a specific session is thinking or speaking—or when you move the pointer over its orb—only that orb expands to its active size and 95% opacity while its neighbors slide slightly aside. Clicking any session orb brings its terminal window and tab (`Terminal.app` or `iTerm2`) directly to the front. Replies from multiple sessions are spoken in order.

- **Codex:** Prisma detects open `codex resume <session-id>` terminal clients, including ones already running when Prisma starts, and removes their orbs after those clients close and their queued speech finishes. Other Codex sessions use its session and prompt hooks; depending on the client, an empty session may not emit its start hook until the first prompt, and disconnecting a terminal can leave the underlying session running rather than emit a session-end hook.
- **Claude Code:** every open Claude Code window has an orb, including windows opened before Prisma started. Its hooks report the window's process, so the orb stays in place when the window moves to another conversation (`/clear`, `/resume`) and leaves when the window closes, even if Claude Code could not send its session-end hook.
- **OpenCode:** OpenCode runs its agent in a shared background service, so Prisma gives each open OpenCode window (`opencode` or `opencode run`) an orb by watching those processes. A session takes over the orb of the window opened in its folder; with several windows in the same folder, Prisma cannot tell which window shows which session. Sessions from clients Prisma does not see, such as a remote client, get an orb that leaves 20 seconds after their reply.

The current app interface uses Spanish labels. On macOS, open **Prisma → Ajustes…** (Settings) from the menu bar; on Windows, open **Ajustes** from the system tray. Options include:

| Setting | Options |
| --- | --- |
| **Engine and voice** | Edge Neural TTS, local Piper, or the system voice. Edge offers multilingual and regional voices. |
| **Reading mode** | Full message, short summary, or notice only. These modes apply to the text received by the app. |
| **Speed** | 0.8× to 1.2×. |
| **Background audio** | Enable or disable ducking and adjust its strength. |
| **Animation** | Target display (any connected monitor, active display, or pointer display), global shortcut to switch displays (`⌃⌥M` by default), orb position (top/bottom row, left/right vertical column, center, or corner), global shortcut to cycle positions (`⌃⌥P` by default), thinking mode, and how long it stays visible afterward. |
| **Halo color by agent** | Independent halo palette (10 themes) for Codex, Claude Code, and OpenCode across waiting, thinking, and voice states. |
| **Agentes** | Connect or disconnect Codex, Claude Code, and OpenCode. Shows whether each integration is connected, incomplete, or unavailable because its CLI is not installed. It covers local sessions only. |

On macOS, ducking is enabled by default and affects the **output device's global volume**, including calls and notifications. By default, it lowers the volume to 35% of its previous level and restores it afterward. Devices whose volume cannot be controlled by macOS are skipped. See [Background audio](docs/audio-ducking.md) for details and limitations. Windows uses per-session ducking; see the [Windows guide](docs/windows.md).

### Try other voices on macOS

```bash
./test.sh "Hello, this is Dalia." --voice dalia
./test.sh "Hello, I am using Piper." --engine piper
./test.sh "Hello, I am using the Apple voice." --engine apple
```

Available Edge voices include `ava`, `andrew`, `emma`, `brian`, `dalia`, `jorge`, `salome`, `ximena`, `alvaro`, and `elena`. You can also select them in settings. The Piper model is a Spanish-language voice.

## Privacy and connectivity

Communication between the plugins and app stays on your computer. **Edge Neural TTS uses an online service:** the prepared notification text is sent to that service to generate audio. For local synthesis, select **Piper Local** or the system voice in settings. The installer also downloads packages and a voice model from the internet.

## Troubleshooting

For Windows, see the [Windows guide](docs/windows.md). The following tips apply to macOS.

**I can't see or hear Prisma.** Open `~/Applications/Prisma.app` and select **Probar voz** (Test voice) from its menu. Check the output volume and confirm that the local server is active in settings.

**The voice test works, but the agent doesn't notify me.** Open **Ajustes → Agentes** and check that the agent says **Conectado**; reconnect it if not, then restart the agent. The hook log is at `~/Library/Application Support/Prisma/hook.log`.

**Edge doesn't speak or I'm offline.** Try Piper or Apple in settings. If Piper cannot be found, run `./setup_voice.sh` followed by `./install.sh` and check again.

**The orb appears on another screen.** On multi-monitor setups, it may appear on the screen macOS considers primary. Explicit display selection is not yet available; you can change the orb's position in settings.

**The volume stayed low.** Prisma attempts to restore it after speaking and on normal exit. If the process is forcibly stopped or crashes, adjust the volume in macOS. You can disable ducking in settings.

## Project structure

```text
app/                 Native macOS app: interface, voice, and local server
windows/             Windows app, installer, and voice test scripts
plugin/              Agent integrations, hooks, and skill
docs/                Research, technical decisions, and roadmap
tests/               Swift, Python, and Node tests for the app, hooks, and plugins
tools/orb-renderer/  Offline frame-by-frame renderer for the orb animation
samples/             Voice samples
setup_voice.sh       Prepares voice dependencies and model
install.sh           Builds and installs Prisma and its integrations
test.sh              Sends a test notification to the app
```

## Documentation

- [Orb animation and session orbs](docs/orb-and-sessions.md): how the macOS orb is drawn and animated, the row of session orbs, how each agent reaches its orb, and how to verify changes.
- [Handoff notes](docs/handoff.md): state of the latest work and suggested next steps for contributors and coding agents.
- [Windows guide](docs/windows.md): installation, configuration, compatibility, and validation.
- [Background audio](docs/audio-ducking.md): macOS ducking behavior, tests, and limitations.
- [Roadmap](docs/roadmap.md): planned improvements and product decisions.
- [Research](docs/investigacion.md): agent integration mechanisms and macOS architecture.
- [Voice comparison](docs/voces.md): local voice tests and samples. Some notes reflect earlier decisions; the current default is Edge Ava Multilingual.

---

<div align="center">
  Made so you can keep working while your agents work with you.
</div>
