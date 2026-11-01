#!/bin/bash
# Renders the orb frame by frame from the app's current OverlayView.swift.
# Usage: tools/orb-renderer/render.sh <out-dir> [fps=30] [cycle|silent|interrupt]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:?usage: render.sh <out-dir> [fps] [cycle|silent|interrupt]}"
FPS="${2:-30}"
SCENARIO="${3:-cycle}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
# ImageRenderer cannot draw the native blur; use the harness stand-in.
sed 's/VisualEffectBlur(/HarnessBlur(/' "$ROOT/app/Sources/Prisma/OverlayView.swift" > "$BUILD/OverlayView.swift"
swiftc -O -swift-version 5 -parse-as-library "$HERE/Harness.swift" "$BUILD/OverlayView.swift" -o "$BUILD/render"
"$BUILD/render" "$OUT" "$FPS" "$SCENARIO"
