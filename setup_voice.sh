#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🐍 Creando entorno de Piper…"
python3 -m venv .venv
.venv/bin/pip install --no-cache-dir --quiet piper-tts edge-tts

echo "🎙️  Descargando voz es_MX-claude-high…"
mkdir -p voices/piper
curl -L --fail --silent --show-error \
  -o voices/piper/es_MX-claude-high.onnx \
  'https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_MX/claude/high/es_MX-claude-high.onnx'
curl -L --fail --silent --show-error \
  -o voices/piper/es_MX-claude-high.onnx.json \
  'https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_MX/claude/high/es_MX-claude-high.onnx.json'

echo "✅ Voz lista. Ahora ejecuta ./install.sh"
