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

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ App creada: $APP"
