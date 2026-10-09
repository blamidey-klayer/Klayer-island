#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-claude-app-watch.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# ClaudeAppWatchRules.swift is Foundation only: the labels, the rules, the state machine and the
# diagnostic of the Chat and Cowork watch. The Accessibility reading (ClaudeAppWatcher.swift) needs a Mac.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeAppWatchRules.swift \
    tests/ClaudeAppWatchTests.swift -o "$TEST_DIR/claude-app-watch-tests"
"$TEST_DIR/claude-app-watch-tests"
