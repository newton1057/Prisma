# Prisma

Orbe estilo **Siri AI en iOS 27 (Liquid Glass + horizonte prismático)** y asistente de voz neural para **Codex**, **Claude Code** y **OpenCode** en macOS.

Cuando cualquiera de tus agentes termina un turno —o se detiene para hacerte una pregunta y pedir confirmación—, el orbe **Prisma** se desliza desde el borde superior de la pantalla (justo debajo del Notch) y lee un resumen pensado específicamente para ser escuchado en voz alta (**Edge Neural TTS · Ava Multilingüe**, con respaldo local **Piper** y **Apple Paulina**).

## Características principales

- **Orbe Liquid Glass (Siri AI iOS 27)**:
  - `NSPanel` flotante no intrusivo (`.screenSaver`, `.fullScreenAuxiliary`, `ignoresMouseEvents = true`) visible incluso sobre apps y videos en pantalla completa sin robar foco ni bloquear clics.
  - Horizonte prismático curvado a `60 fps` reactivo al nivel de audio en tiempo real.
- **Modo `<ForPrisma>` (Resumen inteligente para voz)**:
  - Los 3 agentes (**OpenCode**, **Codex** y **Claude Code**) añaden automáticamente al final de cada respuesta un bloque `<ForPrisma>...</ForPrisma>` de 1 a 3 frases naturales sin URLs, rutas de archivos, bloques de código ni Markdown.
  - El extractor ignora menciones de la etiqueta dentro de bloques de código o comillas invertidas y toma siempre el último bloque `<ForPrisma>` real del mensaje.
- **Aviso por voz en preguntas interactivas**:
  - Cuando un agente solicita confirmación o hace preguntas para continuar (`question` en OpenCode, `AskUserQuestion` en Claude Code o `request_user_input` en Codex), Prisma lee en voz alta la pregunta y las opciones principales en cuanto aparece el diálogo en pantalla.
- **Motores de voz neural y normalización fonética**:
  - **Microsoft Edge Neural TTS (`edge-tts`)**: voz por defecto `en-US-AvaMultilingualNeural` (Ava Multilingüe), más soporte para Andrew, Emma, Brian, Dalia, Jorge, Salomé, Ximena, Álvaro y Elena.
  - **Respaldo offline**: Piper TTS (`es_MX-claude-high.onnx`) y Apple `AVSpeechSynthesizer` (Paulina).
  - **Pronunciación natural**: normaliza siglas y términos técnicos en español (`iOS`, `macOS`, `OpenCode`, `GPT`, `TTS`, `Siri AI`, `Notch`, `Wi-Fi`, etc.).

## Instalación

```bash
git clone https://github.com/newton1057/Prisma.git ~/Desktop/Prisma
cd ~/Desktop/Prisma
./setup_voice.sh   # crea el venv y descarga la voz Piper (~60 MB, no incluida en el repo)
./install.sh
```

También se puede instalar en Claude Code desde el marketplace local:

```text
/plugin install prisma --marketplace prisma-local
```

## Prueba rápida

```bash
~/Desktop/Prisma/test.sh "Hola. Prisma está funcionando en tu Mac."

# Probar otra voz neural por parámetro (ava, andrew, dalia, jorge, salome, ximena, alvaro, elena):
~/Desktop/Prisma/test.sh "Hola. Probando otra voz en Prisma." dalia
```
