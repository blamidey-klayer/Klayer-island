#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-project-colors.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# IslandTypes.swift holds the agent colours (IslandConst.colorForProject); HomeLayout.swift and
# IslandScreenGeometry.swift bring what its view layouts use.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/HomeLayout.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
    tests/ProjectColorTests.swift -o "$TEST_DIR/project-color-tests"
"$TEST_DIR/project-color-tests"
