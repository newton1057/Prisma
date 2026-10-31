# Prisma

Orbe estilo **Siri AI en iOS 27 (Liquid Glass + horizonte prismático)** y asistente de voz neural para **Codex**, **Claude Code** y **OpenCode** en macOS.

Cuando cualquiera de tus agentes termina un turno, el orbe **Prisma** se desliza desde el borde superior de la pantalla (justo debajo del Notch) y lee la respuesta con voz neural (**Edge Neural TTS · Ava Multilingüe**, con respaldo local **Piper** y **Apple Paulina**).

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
