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
- **Configurable orb.** Choose its position and whether it remains visible briefly after speaking.
- **Adjustable background audio.** Temporarily lower background audio while Prisma speaks, or disable ducking altogether.

## Requirements

### macOS

- **macOS 15 or later.** Prisma builds as a native Swift app.
- **Apple developer tools** with Swift, plus Git, Python 3 with `venv`, `curl`, and `jq`. For example, install the command line tools with `xcode-select --install` and `jq` with `brew install jq` if you use Homebrew.
- At least one supported agent: Codex, Claude Code, or OpenCode.
- Internet access to install dependencies, download the Piper model, and use Edge Neural TTS. Piper and the Apple voice can work offline once prepared.

### Windows

- Windows 10 or 11, 64-bit Python 3.11 or 3.12 with Tkinter and the `py` launcher, PowerShell, and Git.
- At least one supported agent installed natively on Windows.
- Internet access to install dependencies, download Piper, and use Edge Neural TTS.

## Installation

### macOS

Clone the repository and run both scripts from the project directory:

```bash
git clone https://github.com/newton1057/Prisma.git ~/Desktop/Prisma
cd ~/Desktop/Prisma
./setup_voice.sh
./install.sh
```

`setup_voice.sh` creates a Python environment, installs `piper-tts` and `edge-tts`, and downloads the Piper voice model (about 60 MB). The model is not included in the repository.

`install.sh` builds and opens the app, copies it to `~/Applications/Prisma.app`, and prepares voice and configuration files in `~/Library/Application Support/Prisma/`. It also configures Codex's global hooks and instructions and, when detected, installs the Claude Code and OpenCode integrations. The installer may modify existing agent configuration; review [install.sh](install.sh) for details. Some plugin commands can fail without stopping the script, so verify each integration afterward.

> If you install an agent after Prisma, run `./install.sh` again to configure it. Restart the agent to load the changes.

To check the installation, select **Probar voz** (Test voice) from Prisma's menu bar icon, or run:

```bash
./test.sh "Hello. Prisma is working on your Mac."
```

Then start or restart an agent and ask it to complete a short task. To check question notifications, ask it to use an interactive question tool.

### Windows

In PowerShell, clone the repository and run the installer:

```powershell
git clone https://github.com/newton1057/Prisma.git
cd Prisma
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

The installer prepares the environment and voices in `%LOCALAPPDATA%\Prisma`, creates a Start menu shortcut, configures hooks, and opens Prisma. Restart your agents; Codex may require you to approve its hooks. The orb appears on the primary display and the app is controlled from the system tray.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\test.ps1 -Text "Hello. Prisma is working on Windows."
```

See the [Windows guide](docs/windows.md) for requirements, settings, troubleshooting, and outstanding validation. **The Windows implementation still needs to be tested on a Windows machine.**

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

The current app interface uses Spanish labels. On macOS, open **Prisma → Ajustes…** (Settings) from the menu bar; on Windows, open **Ajustes** from the system tray. Options include:

| Setting | Options |
| --- | --- |
| **Engine and voice** | Edge Neural TTS, local Piper, or the system voice. Edge offers multilingual and regional voices. |
| **Reading mode** | Full message, short summary, or notice only. These modes apply to the text received by the app. |
| **Speed** | 0.8× to 1.2×. |
| **Background audio** | Enable or disable ducking and adjust its strength. |
| **Animation** | Orb position and how long it stays visible afterward. |

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

**The voice test works, but the agent doesn't notify me.** Restart the agent and rerun `./install.sh` if you installed it after Prisma. Check that its integration is enabled; the installer continues even if some plugin commands fail. The hook log is at `~/Library/Application Support/Prisma/hook.log`.

**Edge doesn't speak or I'm offline.** Try Piper or Apple in settings. If Piper cannot be found, run `./setup_voice.sh` followed by `./install.sh` and check again.

**The orb appears on another screen.** On multi-monitor setups, it may appear on the screen macOS considers primary. Explicit display selection is not yet available; you can change the orb's position in settings.

**The volume stayed low.** Prisma attempts to restore it after speaking and on normal exit. If the process is forcibly stopped or crashes, adjust the volume in macOS. You can disable ducking in settings.

## Project structure

```text
app/                 Native macOS app: interface, voice, and local server
windows/             Windows app, installer, and voice test scripts
plugin/              Agent integrations, hooks, and skill
docs/                Research, technical decisions, and roadmap
samples/             Voice samples
setup_voice.sh       Prepares voice dependencies and model
install.sh           Builds and installs Prisma and its integrations
test.sh              Sends a test notification to the app
```

## Documentation

- [Windows guide](docs/windows.md): installation, configuration, compatibility, and validation.
- [Background audio](docs/audio-ducking.md): macOS ducking behavior, tests, and limitations.
- [Roadmap](docs/roadmap.md): planned improvements and product decisions.
- [Research](docs/investigacion.md): agent integration mechanisms and macOS architecture.
- [Voice comparison](docs/voces.md): local voice tests and samples. Some notes reflect earlier decisions; the current default is Edge Ava Multilingual.

---

<div align="center">
  Made so you can keep working while your agents work with you.
</div>
