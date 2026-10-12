#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-drop-inbox.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/DropInbox.swift \
    tests/DropInboxTests.swift -o "$TEST_DIR/drop-inbox-tests"
"$TEST_DIR/drop-inbox-tests"
