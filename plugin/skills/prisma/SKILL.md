---
name: prisma
description: Configure and test Prisma, the animated orb and neural voice that announces when Codex, Claude Code, or OpenCode finish a turn or ask a question.
---

# Prisma

Prisma is a plugin and macOS or Windows application that announces completed turns and requests for user input in **Codex**, **Claude Code**, and **OpenCode**. It displays a floating orb and speaks the agent's `<ForPrisma>...</ForPrisma>` summary.

## How it works

- **Voice block:** OpenCode (`ctx.session.hook("context")`), Codex (`~/.codex/AGENTS.md`), and Claude Code (`~/.claude/CLAUDE.md`) instruct the agent to end each response or question with a one-to-three-sentence `<ForPrisma>` block in the user's language, without URLs, file paths, commands, or Markdown.
- **Turn completion and questions:** Codex and Claude Code use `Stop`, `PreToolUse`, and `PermissionRequest` hooks. OpenCode subscribes to `session.execution.succeeded`, `session.idle`, `question.v2.asked`, and `tool.execute.before`. The extractor ignores code examples, selects the last real voice block, and can format question options when a question tool is called directly.
- **Playback:** The platform-specific hook sends cleaned text to Prisma on `127.0.0.1`: `on_stop.sh` on macOS or `%LOCALAPPDATA%/Prisma/hook.py` on Windows. Prisma plays Edge Neural TTS (Ava), Piper, or a system voice and displays the orb. Background audio ducking is configurable.

The macOS installer attempts to register and trust the Codex hooks. On Windows, the installer registers them, but Codex may require the user to review and trust them.

## Quick test

On macOS:

```bash
~/Desktop/Prisma/test.sh "Hello. Prisma is working."
```

For Windows installation and testing, see `docs/windows.md` in the project. The integration targets native Windows agents; WSL requires separate configuration. Windows functionality still needs validation on a Windows machine.
