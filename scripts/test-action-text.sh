#!/usr/bin/env bash
# What a session's row says it did (ActionText): a tool call in French, a prompt's first line, no id.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-action-text.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ActionText.swift \
    tests/ActionTextTests.swift -o "$TEST_DIR/action-text-tests"
"$TEST_DIR/action-text-tests"
