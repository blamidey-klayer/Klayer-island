#!/usr/bin/env bash
# The diagnostic log (AppLog.swift): lines appended, control characters escaped, and a write that
# fails (a full disk, played with the file size limit) never raises (0.3.6, B4). It writes one test
# file in ~/Library/Logs/NotchBuddy and removes it.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-app-log.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AppLogTests.swift -o "$TEST_DIR/app-log-tests"
"$TEST_DIR/app-log-tests"
