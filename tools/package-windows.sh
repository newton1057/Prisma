#!/usr/bin/env bash
# Build the portable Prisma for Windows ZIP published in GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n "s/^VERSION = '\([^']*\)'.*/\1/p" "$ROOT/windows/common.py")"
if [[ -z "$VERSION" ]]; then
  echo "No pude leer VERSION de windows/common.py" >&2
  exit 1
fi

DIST="$ROOT/dist"
OUT="$DIST/Prisma-Windows-$VERSION.zip"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/prisma-windows.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$DIST" "$STAGE/Prisma"
cp -R "$ROOT/windows" "$STAGE/Prisma/windows"
cp -R "$ROOT/plugin" "$STAGE/Prisma/plugin"
cp "$ROOT/windows/LEEME.txt" "$STAGE/Prisma/LEEME.txt"
cp "$ROOT/windows/install.cmd" "$STAGE/Prisma/Instalar Prisma.cmd"
rm -f "$STAGE/Prisma/windows/LEEME.txt" "$STAGE/Prisma/windows/install.cmd"

find "$STAGE" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$STAGE" -name '.DS_Store' -delete

rm -f "$OUT"
(cd "$STAGE" && zip -q -r -X "$OUT" Prisma)
echo "$OUT"
shasum -a 256 "$OUT"
