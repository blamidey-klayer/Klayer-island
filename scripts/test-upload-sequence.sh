#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-upload-sequence.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# IslandTypes.swift brings the real view layouts and Klay's size rule: the drop canvas starts its
# Klay where the Déposer tab draws the island's (IslandScreenGeometry.swift brings the constant they
# use); KlayMotion.swift the island Klay's gaze rule.
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/UploadSequenceEngine.swift \
    NotchBuddy/Sources/KlayerIslandKit/KlayMotion.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
    tests/UploadSequenceTests.swift -o "$TEST_DIR/upload-sequence-tests"
"$TEST_DIR/upload-sequence-tests"
