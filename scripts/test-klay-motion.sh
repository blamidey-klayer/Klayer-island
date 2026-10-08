#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-motion.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/KlayerIslandKit/KlayMotion.swift \
    tests/KlayMotionTests.swift -o "$TEST_DIR/klay-motion-tests"
"$TEST_DIR/klay-motion-tests"
