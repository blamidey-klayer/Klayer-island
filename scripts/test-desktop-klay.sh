#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-desktop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/DesktopKlayLogic.swift \
    tests/DesktopKlayTests.swift -o "$TEST_DIR/desktop-klay-tests"
"$TEST_DIR/desktop-klay-tests"
