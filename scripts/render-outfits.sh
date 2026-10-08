#!/bin/bash
# render-outfits.sh — compile and run the Klay outfit planche renderer
# NOT in CI. Run manually: bash scripts/render-outfits.sh
# Output: /tmp/klayer-outfits.png

set -e
cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk macosx --show-sdk-path)

echo "Compiling renderer..."
swiftc \
  -parse-as-library \
  -sdk "$SDK" \
  -target arm64-apple-macosx15.0 \
  NotchBuddy/Sources/KlayerIslandKit/IslandScreenGeometry.swift \
  NotchBuddy/Sources/KlayerIslandKit/IslandTypes.swift \
  NotchBuddy/Sources/KlayerIslandKit/KlayWardrobe.swift \
  NotchBuddy/Sources/KlayerIslandKit/BotEngine.swift \
  NotchBuddy/Sources/KlayerIslandKit/KlayOutfitDrawing.swift \
  scripts/RenderOutfits.swift \
  -framework AppKit \
  -framework SwiftUI \
  -o /tmp/klayer-render-outfits \
  2>&1

echo "Running renderer..."
/tmp/klayer-render-outfits
echo "Opening..."
open /tmp/klayer-outfits.png
