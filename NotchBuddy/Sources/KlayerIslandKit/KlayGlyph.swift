import SwiftUI

// The Klayer glyph, the brand mark Klay is built on, as absolute segments in
// glyph units (797 x 512, y down). Generated from windows/src/klay/glyph.ts
// (itself converted from the official glyph SVG): never edit the numbers by
// hand. The mark is drawn exactly as the brand ships it; only its colour and
// the limbs and eyes around it belong to the character.

enum KlayGlyph {
    static let width: CGFloat = 797
    static let height: CGFloat = 512

    enum Segment {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    static let segments: [Segment] = [
        .move(370.0, 165.2),
        .line(370.0, 330.5),
        .line(253.7, 214.2),
        .line(137.5, 98.0),
        .line(117.0, 118.5),
        .line(96.6, 138.9),
        .line(169.0, 211.7),
        .curve(208.9, 251.7, 249.4, 292.5, 259.0, 302.3),
        .line(276.5, 320.0),
        .line(267.5, 316.4),
        .curve(262.6, 314.4, 222.3, 297.8, 178.0, 279.5),
        .curve(47.0, 225.4, 40.8, 222.8, 40.0, 223.7),
        .curve(39.2, 224.5, 20.8, 268.7, 19.6, 272.7),
        .curve(19.1, 274.3, 19.4, 275.2, 20.9, 275.9),
        .curve(23.1, 277.1, 48.7, 287.8, 122.0, 318.0),
        .curve(177.1, 340.7, 226.9, 361.4, 241.5, 367.7),
        .line(250.5, 371.5),
        .line(125.2, 371.8),
        .line(0.0, 372.0),
        .line(0.2, 400.8),
        .line(0.5, 429.5),
        .line(131.5, 430.1),
        .curve(250.0, 430.6, 263.3, 430.8, 271.0, 432.4),
        .curve(304.7, 439.2, 331.2, 450.4, 354.6, 467.6),
        .curve(369.1, 478.2, 379.2, 489.0, 387.4, 502.8),
        .curve(389.5, 506.2, 392.0, 509.5, 393.0, 510.0),
        .curve(395.6, 511.4, 402.3, 511.2, 404.3, 509.7),
        .curve(405.2, 509.1, 408.7, 504.2, 412.1, 499.0),
        .curve(424.2, 480.5, 443.6, 464.4, 469.5, 451.5),
        .curve(492.5, 440.1, 514.1, 433.6, 537.2, 431.1),
        .curve(543.5, 430.4, 591.0, 430.0, 672.0, 430.0),
        .line(797.0, 430.0),
        .line(797.0, 401.0),
        .line(797.0, 372.0),
        .line(671.8, 372.0),
        .curve(602.9, 372.0, 547.0, 371.6, 547.6, 371.1),
        .curve(548.5, 370.3, 562.4, 364.6, 655.0, 326.5),
        .curve(770.1, 279.2, 778.6, 275.6, 778.3, 274.4),
        .curve(778.0, 273.2, 757.9, 223.6, 757.5, 223.2),
        .curve(757.3, 223.0, 746.9, 227.1, 734.3, 232.3),
        .curve(721.8, 237.5, 702.7, 245.4, 692.0, 249.8),
        .curve(671.6, 258.2, 571.8, 299.3, 540.1, 312.4),
        .curve(530.0, 316.6, 521.5, 319.9, 521.3, 319.6),
        .curve(521.1, 319.4, 561.1, 278.9, 610.2, 229.5),
        .curve(659.3, 180.2, 699.6, 139.5, 699.8, 139.1),
        .curve(699.9, 138.8, 691.0, 129.5, 680.1, 118.6),
        .line(660.1, 98.6),
        .line(642.8, 115.5),
        .curve(633.3, 124.8, 581.2, 176.9, 527.1, 231.2),
        .curve(472.9, 285.6, 428.3, 330.0, 427.8, 330.0),
        .curve(427.4, 330.0, 427.0, 255.7, 427.0, 165.0),
        .line(427.0, 0.0),
        .line(398.5, 0.0),
        .line(370.0, 0.0),
        .line(370.0, 165.2),
        .close,
    ]

    /// The glyph as a SwiftUI Path in glyph units (0…797 x 0…512). Built once.
    static let path: Path = {
        var p = Path()
        for s in segments {
            switch s {
            case let .move(x, y):
                p.move(to: CGPoint(x: x, y: y))
            case let .line(x, y):
                p.addLine(to: CGPoint(x: x, y: y))
            case let .curve(c1x, c1y, c2x, c2y, x, y):
                p.addCurve(to: CGPoint(x: x, y: y),
                           control1: CGPoint(x: c1x, y: c1y),
                           control2: CGPoint(x: c2x, y: c2y))
            case .close:
                p.closeSubpath()
            }
        }
        return p
    }()
}
