#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-approval-summary.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ApprovalSummary.swift \
    tests/ApprovalSummaryTests.swift -o "$TEST_DIR/approval-summary-tests"
"$TEST_DIR/approval-summary-tests"
