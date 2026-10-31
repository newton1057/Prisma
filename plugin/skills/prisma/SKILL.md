---
name: prisma
description: Configura y prueba Prisma, el orbe estilo Siri AI iOS 27 y voz neural que avisa cuando Codex, Claude Code u OpenCode terminan un turno o hacen preguntas al usuario.
---

# Prisma

Plugin y app nativa de macOS que avisa cuando termina un turno o se solicita información al usuario en **Codex**, **Claude Code** u **OpenCode**: despliega un orbe estilo Siri AI iOS 27 desde el borde superior (debajo del Notch) y lee con voz neural únicamente el bloque `<ForPrisma>...</ForPrisma>`.

## Cómo funciona

- **Modo `<ForPrisma>`**:
  - En **OpenCode** (`ctx.session.hook("context")`), **Codex** (`~/.codex/AGENTS.md`) y **Claude Code** (`~/.claude/CLAUDE.md`), el agente incluye al final de cada respuesta o pregunta un bloque `<ForPrisma>...</ForPrisma>` de 1 a 3 frases naturales libre de URLs, rutas de archivos, comandos o Markdown.
- **Fin de turno y preguntas en vivo**:
  - El hook `Stop` / `PreToolUse` (en Codex y Claude Code) o el plugin de servidor (en OpenCode, suscrito a `session.execution.succeeded`, `session.idle`, `question.v2.asked` y `tool.execute.before`) ejecuta `on_stop.sh`.
  - El extractor descarta bloques de código o menciones en línea y toma únicamente el último bloque `<ForPrisma>` real (o formatea las opciones de la pregunta si se invocó la herramienta directamente).
- **Reproducción y animación**:
  - `on_stop.sh` envía el texto limpio a **Prisma.app** por `127.0.0.1`.
  - La app despliega el orbe con horizonte prismático reactivo al audio y reproduce la voz con **Edge Neural TTS (Ava)**, **Piper** o **Apple Paulina**.
  - Mientras habla, Prisma atenúa la música y los videos del sistema y sube su propia voz; al terminar restaura el volumen (configurable en **Ajustes → Audio de fondo**).

## Prueba rápida

```bash
~/Desktop/Prisma/test.sh "Hola. Prisma está funcionando."
```
