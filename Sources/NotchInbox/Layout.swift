import Foundation

/// The four sizes the notch moves through.
enum NotchLevel: Equatable {
    case rest    // closed: the notch plus small unread "ears"
    case peek    // the primary menu: one tile per tool (Mail first); hover or click
    case lanes   // click: one lane per inbox
    case detail  // click an inbox: it widens into list + full message
}

/// Sizes for each level, derived from the physical notch.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    /// The narrowest an ear gets. Ears widen to fit the unread counts they show.
    static let earWidth: CGFloat = 56
    static let shadowMargin: CGFloat = 48

    /// How wide each ear must be to show these unread counts in full, side by side.
    /// Accounts with nothing unread are left out; nothing unread at all means no ears.
    static func earWidth(for counts: [Int]) -> CGFloat {
        let shown = counts.filter { $0 > 0 }
        guard !shown.isEmpty else { return 0 }
        let characters = shown.reduce(0) { $0 + UnreadText.format($1).count }
        // About 7.6pt per bold 12pt digit, 8pt between counts, padding at both ends.
        let needed = CGFloat(characters) * 7.6 + CGFloat(shown.count - 1) * 8 + 20
        return max(earWidth, needed.rounded(.up))
    }

    /// Height of the row that sits beside the camera housing.
    var topRow: CGFloat { max(notchHeight, 32) + 4 }

    /// Width the content leaves empty in the middle of the top row, around the camera.
    var notchGap: CGFloat { notchWidth + 16 }

    /// `ears` is the width of each ear when closed (0 for none); other levels ignore it.
    func bodySize(_ level: NotchLevel, ears: CGFloat = 0) -> CGSize {
        switch level {
        case .rest:
            return CGSize(width: notchWidth + max(0, ears) * 2, height: notchHeight)
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
    func shoulder(_ level: NotchLevel, ears: CGFloat = 0) -> CGFloat {
        switch level {
        case .rest: return ears > 0 ? 6 : 0
        case .peek, .lanes: return 12
        case .detail: return 14
        }
    }

    /// Body plus shoulders: the full black outline.
    func outlineSize(_ level: NotchLevel, ears: CGFloat = 0) -> CGSize {
        let body = bodySize(level, ears: ears)
        return CGSize(width: body.width + shoulder(level, ears: ears) * 2, height: body.height)
    }

    /// The transparent window fits the largest level plus room for its shadow.
    var windowSize: CGSize {
        let largest = outlineSize(.detail)
        return CGSize(width: largest.width + NotchMetrics.shadowMargin * 2,
                      height: largest.height + NotchMetrics.shadowMargin * 1.5)
    }
}

/// Unread counts as people write them: 7, 297, 3992. Only 10,000 and up are shortened (12k).
enum UnreadText {
    static func format(_ count: Int) -> String {
        count < 10_000 ? "\(count)" : "\(count / 1000)k"
    }
}
