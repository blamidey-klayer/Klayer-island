#!/usr/bin/env bash
# What the open buttons open (OpenTarget), and the source icons of the rows and the notes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-open-target.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# HookRouting.swift (with ClaudeHookDetection.swift) gives the Claude app's pill and bundle id,
# SessionRoster.swift (with ActionText.swift) the rows.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeHookDetection.swift \
    NotchBuddy/Sources/App/HookRouting.swift \
    NotchBuddy/Sources/App/ActionText.swift \
    NotchBuddy/Sources/App/SessionRoster.swift \
    NotchBuddy/Sources/App/OpenTarget.swift \
    tests/OpenTargetTests.swift -o "$TEST_DIR/open-target-tests"
"$TEST_DIR/open-target-tests"
