#!/usr/bin/env bash
# The card steps aside when the session's app comes to the front (CardStepAside, StepAsideWatch).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-card-step-aside.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# HookRouting.swift (with ClaudeHookDetection.swift) gives the Claude app's bundle id.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/CardStepAside.swift \
    tests/CardStepAsideTests.swift -o "$TEST_DIR/card-step-aside-tests"
"$TEST_DIR/card-step-aside-tests"
