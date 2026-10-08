#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-removed-feature-cleanup.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/RemovedFeatureCleanup.swift \
    tests/RemovedFeatureCleanupTests.swift -o "$TEST_DIR/removed-feature-cleanup-tests"
"$TEST_DIR/removed-feature-cleanup-tests"
