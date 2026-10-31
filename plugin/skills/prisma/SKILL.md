---
name: prisma
description: Configura y prueba Prisma, el orbe estilo Siri AI iOS 27 y voz neural que avisa cuando Codex, Claude Code u OpenCode terminan un turno.
---

# Prisma

Plugin y app nativa de macOS que avisa cuando termina un turno en **Codex**, **Claude Code** u **OpenCode**: despliega un orbe estilo Siri AI iOS 27 desde el borde superior (debajo del Notch) y lee el mensaje final con voz neural.

## Cómo funciona

- El hook `Stop` (en Codex y Claude Code) o el plugin de servidor (en OpenCode) ejecuta `on_stop.sh` al terminar el turno.
- El script envía el último mensaje a **Prisma.app** por `127.0.0.1`.
- La app despliega el orbe con haz prismático reactivo al audio y reproduce la voz con **Edge Neural TTS (Ava)**, **Piper** o **Apple Paulina**.

## Prueba rápida

```bash
~/Desktop/Prisma/test.sh "Hola. Prisma está funcionando."
```
