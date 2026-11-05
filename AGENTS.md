# Prisma: notes for coding agents

Prisma speaks coding agents' replies aloud and shows an animated orb for each agent session. The macOS app is in `app/`, the agent hooks and plugins in `plugin/`, the Windows app in `windows/`.

## Start here

- [docs/handoff.md](docs/handoff.md): current state (including uncommitted work), how to resume, gotchas and next steps.
- [docs/orb-and-sessions.md](docs/orb-and-sessions.md): orb animation, row layout, session orbs per agent, local API, verification.
- [docs/roadmap.md](docs/roadmap.md), [docs/audio-ducking.md](docs/audio-ducking.md), [docs/windows.md](docs/windows.md).

## Build, install and test (macOS)

- `./app/build.sh` builds `app/Prisma.app`; `./install.sh` installs the app, scripts, Codex hooks and the Claude Code and OpenCode plugins.
- `./app/empaquetar.sh` creates `dist/Prisma-<version>.zip` and `.dmg`; `./app/publicar.sh "notes"` publishes the DMG to GitHub and the signed ZIP + manifest to the `prisma-updates` bucket. The updater key is in the login keychain under **Prisma actualizaciones**; never commit it.
- The test commands are listed in [section 8.1 of the orb reference](docs/orb-and-sessions.md#81-automated-tests).
- For animation work, render frames with `tools/orb-renderer` and look at the contact sheet before calling a transition smooth.

## Conventions

- The app's interface labels are Spanish; documentation and code comments are English.
- Scripts read the port and token from `~/Library/Application Support/Prisma/runtime.json`; the port can change.
- Testing in the running app is audible and adds orbs. Use short texts and end test sessions with `POST /session/end`.
- Ask before committing, pushing or anything else outward-facing.
