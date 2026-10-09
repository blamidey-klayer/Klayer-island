#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-home-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# IslandTypes.swift brings the real view layouts (Klay's place on the home is checked against the
# columns), PillCatalog.swift the pill ids the rail icons show.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/HomeLayout.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
    NotchBuddy/Sources/KlayerIslandKit/PillColors.swift \
    NotchBuddy/Sources/KlayerIslandKit/PillCatalog.swift \
    tests/HomeLayoutTests.swift -o "$TEST_DIR/home-layout-tests"
"$TEST_DIR/home-layout-tests"
