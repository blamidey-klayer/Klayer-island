import Foundation

@main
enum IslandScreenGeometryTests {
    static func main() {
        // Regression: absent auxiliary areas must never mean "screen-wide notch".
        for screenWidth: CGFloat in [1080, 1920, 2560, 3840] {
            let geometry = IslandScreenGeometry(
                screenWidth: screenWidth, safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 30
            )
            precondition(!geometry.hasNotch)
            precondition(geometry.width == 80)
            precondition(geometry.height == 24)
        }

        // A shorter menu bar must also contain the resting island.
        let shortMenuBar = IslandScreenGeometry(
            screenWidth: 1920, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 22
        )
        precondition(shortMenuBar.height == 22)

        // Real MacBook notch measurements retain their physical dimensions.
        let macBook = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32
        )
        precondition(macBook.hasNotch)
        precondition(macBook.width == 192 && macBook.height == 32)

        // Incomplete or invalid measurements use the notch fallback, not the screen.
        for auxiliaryWidth: CGFloat? in [nil, 0, 1000] {
            let geometry = IslandScreenGeometry(
                screenWidth: 1512, safeAreaTop: 32,
                auxiliaryLeftWidth: auxiliaryWidth, auxiliaryRightWidth: auxiliaryWidth,
                menuBarHeight: 32
            )
            precondition(geometry.width == 184 && geometry.height == 32)
        }
        // Compact/greeting destinations share the measured resting height.
        for height: CGFloat in [22, 24, 32, 38] {
            let compact = IslandRestingLayout(width: 240, height: height)
            precondition(compact.botCenterY == height / 2)
            precondition(compact.botDiameter == min(20, height - 6))
            precondition(compact.botCenterY - compact.botDiameter / 2 >= 3)
            precondition(compact.botCenterY + compact.botDiameter / 2 <= height - 3)
            // The Granola button sits where the mini Klay grid was (40 pt from the right edge),
            // and its hit area stays inside the island whatever the height.
            precondition(compact.granolaCenterX == 200)
            let hit = compact.granolaHitRect
            precondition(hit.midX == 200 && hit.midY == height / 2)
            precondition(hit.width == hit.height && hit.width == min(28, height))
            precondition(hit.minX >= 0 && hit.maxX <= 240 && hit.minY >= 0 && hit.maxY <= height)
        }
        // The same area in panel coordinates (origin bottom left), for a 240 x 32 island
        // glued to the top of a 720 x 560 panel.
        let inPanel = IslandRestingLayout(width: 240, height: 32)
            .granolaHitRectInPanel(islandFrame: CGRect(x: 240, y: 528, width: 240, height: 32))
        precondition(inPanel == CGRect(x: 426, y: 530, width: 28, height: 28))
        print("Island screen geometry and resting layout: 14 cases passed")
    }
}
