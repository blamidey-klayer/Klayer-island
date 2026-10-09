#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-code-notification.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# IslandTypes.swift brings PillBadge (the badge of the house tab) and the real IslandView (with
# IslandScreenGeometry.swift, the constant it uses), SessionRoster.swift SessionPhase (the phases of a
# row) and FinishPresentation, HookRouting.swift and ClaudeHookDetection.swift the rule that tells the
# Claude app from a terminal session. ClaudeAppAlertHold.swift: the alert held while the island is busy.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/SessionRoster.swift \
    NotchBuddy/Sources/App/CodeNotification.swift \
    NotchBuddy/Sources/App/ClaudeAppAlertHold.swift \
    tests/CodeNotificationTests.swift -o "$TEST_DIR/code-notification-tests"
"$TEST_DIR/code-notification-tests"
