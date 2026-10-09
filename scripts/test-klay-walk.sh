#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-walk.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# Klay's walk back into the island: the plan and the gait, Foundation only.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/KlayerIslandKit/KlayWalk.swift \
    tests/KlayWalkTests.swift -o "$TEST_DIR/klay-walk-tests"
"$TEST_DIR/klay-walk-tests"
