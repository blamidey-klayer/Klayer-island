#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-session-roster.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/SessionRoster.swift \
    tests/SessionRosterTests.swift -o "$TEST_DIR/session-roster-tests"
"$TEST_DIR/session-roster-tests"
