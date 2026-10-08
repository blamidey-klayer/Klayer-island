#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-granola-link.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/GranolaLink.swift \
    tests/GranolaLinkTests.swift -o "$TEST_DIR/granola-link-tests"
"$TEST_DIR/granola-link-tests"
