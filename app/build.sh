#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🔨 Compilando Prisma…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/Prisma.app"

rm -rf "$APP" "$PWD/CodexVoz.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Prisma" "$APP/Contents/MacOS/Prisma"
cp "$PWD/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Prisma"

# Integrations shipped inside the app so Ajustes can connect each agent
# without the repository: hooks, plugins and the Codex/Claude marketplaces.
RESOURCES="$APP/Contents/Resources/plugin-dist"
rm -rf "$RESOURCES"
mkdir -p "$RESOURCES"
cp -R "$PWD/../plugin" "$RESOURCES/plugin"
cp -R "$PWD/../.agents" "$RESOURCES/.agents"
cp -R "$PWD/../.claude-plugin" "$RESOURCES/.claude-plugin"
find "$RESOURCES" -name ".DS_Store" -delete

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ App creada: $APP"
