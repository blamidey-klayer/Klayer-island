import Foundation

/// Resting island dimensions, using a physical notch only when the screen has one.
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            height = safeAreaTop
        } else {
            width = Self.noNotchWidth
            height = min(Self.noNotchHeight, menuBarHeight)
        }
    }
}

/// Shared by the compact view and the greeting's collapse destination.
struct IslandRestingLayout {
    let width: CGFloat
    let height: CGFloat

    var botDiameter: CGFloat { min(20, max(0, height - 6)) }
    var botCenterY: CGFloat { height / 2 }

    /// Centre of the Granola button, in the right ear of the compact island.
    var granolaCenterX: CGFloat { width - 40 }
    /// Hit area of the Granola button in island coordinates (origin top left): a 28 pt square,
    /// shorter on a low bar, centred on `granolaCenterX` and on the island's height.
    var granolaHitRect: CGRect {
        let side = min(28, height)
        return CGRect(x: granolaCenterX - side / 2, y: (height - side) / 2, width: side, height: side)
    }

    /// The same area in panel coordinates (origin bottom left), for an island whose frame in
    /// the panel is `islandFrame`. The window controller uses it to tell the button from the
    /// rest of the island.
    func granolaHitRectInPanel(islandFrame: CGRect) -> CGRect {
        let rect = granolaHitRect
        return CGRect(x: islandFrame.minX + rect.minX, y: islandFrame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }
}
