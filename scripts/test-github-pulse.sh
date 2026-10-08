#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-github-pulse.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/GitHubPulse.swift \
    tests/GitHubPulseTests.swift -o "$TEST_DIR/github-pulse-tests"
"$TEST_DIR/github-pulse-tests"
