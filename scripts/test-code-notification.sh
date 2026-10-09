#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-code-notification.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# SessionRoster.swift brings SessionPhase (the phases of a row), HookRouting.swift and
# ClaudeHookDetection.swift the rule that tells the Claude app from a terminal session.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/SessionRoster.swift \
    NotchBuddy/Sources/App/CodeNotification.swift \
    tests/CodeNotificationTests.swift -o "$TEST_DIR/code-notification-tests"
"$TEST_DIR/code-notification-tests"
