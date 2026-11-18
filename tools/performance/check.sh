#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD="$(mktemp -d /tmp/prisma-checks.XXXXXX)"
trap 'rm -rf "$BUILD"' EXIT
MONITOR=(app/Sources/Prisma/CodexSessionsMonitor.swift)
WINDOWS=(app/Sources/Prisma/OpenCodeWindows.swift app/Sources/Prisma/ClaudeCodeWindows.swift
         app/Sources/Prisma/MuseWindows.swift app/Sources/Prisma/AntigravityWindows.swift)
swiftc -O -swift-version 5 -parse-as-library app/Sources/Prisma/OverlayView.swift \
    app/Sources/Prisma/SettingsStore.swift tests/test_overlay_motion.swift -o "$BUILD/motion"
"$BUILD/motion"
sed 's/VisualEffectBlur(/HarnessBlur(/' app/Sources/Prisma/OverlayView.swift > "$BUILD/OverlayView.swift"
swiftc -O -swift-version 5 -parse-as-library "$BUILD/OverlayView.swift" tools/orb-renderer/StandIn.swift \
    tests/test_orb_viewport.swift -o "$BUILD/viewport"
"$BUILD/viewport"
swiftc -parse-as-library "${MONITOR[@]}" "${WINDOWS[@]}" tests/test_agent_windows.swift -o "$BUILD/windows"
"$BUILD/windows"
swiftc "${MONITOR[@]}" tests/test_codex_sessions_monitor.swift -o "$BUILD/codex"
"$BUILD/codex"
swiftc -parse-as-library "${MONITOR[@]}" "${WINDOWS[@]}" app/Sources/Prisma/AgentProcessSnapshot.swift \
    tests/test_agent_process_snapshot.swift -o "$BUILD/snapshot"
"$BUILD/snapshot"
swiftc -parse-as-library app/Sources/Prisma/SessionMetadataResolver.swift \
    app/Sources/Prisma/ThinkingTranscriptReader.swift tests/test_session_metadata.swift -o "$BUILD/metadata"
"$BUILD/metadata"
swiftc -parse-as-library app/Sources/Prisma/AgentConnections.swift app/Sources/Prisma/Config.swift \
    tests/test_agent_connections.swift -o "$BUILD/connections"
"$BUILD/connections"
python3 -m unittest discover -s tests
node tests/test_opencode_flow.mjs
swift test --package-path app
