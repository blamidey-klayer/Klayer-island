#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-claude-cli.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudeCLI.swift \
    NotchBuddy/Sources/App/ClaudeStream.swift \
    NotchBuddy/Sources/App/ChatAttachment.swift \
    tests/ClaudeCLITests.swift -o "$TEST_DIR/claude-cli-tests"
"$TEST_DIR/claude-cli-tests"
