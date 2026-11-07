import Foundation

/// The four sizes the notch moves through.
enum NotchLevel: Equatable {
    case rest    // closed: the notch plus small unread "ears"
    case peek    // hover: one tile per account
    case lanes   // click: one lane per inbox
    case detail  // click an inbox: it widens into list + full message
}

/// Sizes for each level, derived from the physical notch.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    static let earWidth: CGFloat = 56
    static let shadowMargin: CGFloat = 48

    /// Height of the row that sits beside the camera housing.
    var topRow: CGFloat { max(notchHeight, 32) + 4 }

    /// Width the content leaves empty in the middle of the top row, around the camera.
    var notchGap: CGFloat { notchWidth + 16 }

    func bodySize(_ level: NotchLevel, showEars: Bool) -> CGSize {
        switch level {
        case .rest:
            let width = showEars ? notchWidth + NotchMetrics.earWidth * 2 : notchWidth
            return CGSize(width: width, height: notchHeight)
        case .peek:
            return CGSize(width: 600, height: topRow + 110)
        case .lanes:
            return CGSize(width: 900, height: topRow + 318)
        case .detail:
            return CGSize(width: 1040, height: topRow + 482)
        }
    }

    func bottomRadius(_ level: NotchLevel) -> CGFloat {
        switch level {
        case .rest: return 12
        case .peek: return 28
        case .lanes: return 30
        case .detail: return 32
        }
    }

    /// Radius of the inward curves where the shape meets the top edge of the screen.
    func shoulder(_ level: NotchLevel, showEars: Bool) -> CGFloat {
        switch level {
        case .rest: return showEars ? 6 : 0
        case .peek, .lanes: return 12
        case .detail: return 14
        }
    }

    /// Body plus shoulders: the full black outline.
    func outlineSize(_ level: NotchLevel, showEars: Bool) -> CGSize {
        let body = bodySize(level, showEars: showEars)
        return CGSize(width: body.width + shoulder(level, showEars: showEars) * 2, height: body.height)
    }

    /// The transparent window fits the largest level plus room for its shadow.
    var windowSize: CGSize {
        let largest = outlineSize(.detail, showEars: true)
        return CGSize(width: largest.width + NotchMetrics.shadowMargin * 2,
                      height: largest.height + NotchMetrics.shadowMargin * 1.5)
    }
}
