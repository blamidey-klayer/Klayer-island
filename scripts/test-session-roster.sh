#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-session-roster.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# IslandTypes.swift brings the real IslandView (and IslandScreenGeometry.swift the constant it
# uses), so the view strings of FinishPresentation are checked against the real cases.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/SessionRoster.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
    tests/SessionRosterTests.swift -o "$TEST_DIR/session-roster-tests"
"$TEST_DIR/session-roster-tests"
