#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-choice-history.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ChoiceHistory.swift \
    tests/ChoiceHistoryTests.swift -o "$TEST_DIR/choice-history-tests"
"$TEST_DIR/choice-history-tests"
