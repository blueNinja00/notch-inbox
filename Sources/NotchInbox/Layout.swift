import Foundation

/// The four sizes the notch moves through.
enum NotchLevel: String, Equatable {
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
    /// The screen's size, which caps how big you can drag the open panel.
    var screenSize = CGSize(width: 1512, height: 982)

    /// The narrowest an ear gets. Ears widen to fit the unread counts they show.
    static let earWidth: CGFloat = 56
    /// Ears just wide enough for the red phone dot, when nothing is unread.
    static let dotEarWidth: CGFloat = 26
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

    /// The row of extras under the primary menu's tiles (now playing, focus, clipboard,
    /// shelf), with the gap above it.
    static let extrasRow: CGFloat = 48
    /// The primary menu's tiles, with the gaps around them: in one row, or in two.
    static let oneTileRow: CGFloat = 110
    static let twoTileRows: CGFloat = 214
    /// The tiles go in two rows (Mail down the left) once there's this much height for them.
    static let tallTiles: CGFloat = 180
    /// Ears wide enough for the focus timer's minutes, when nothing is unread.
    static let focusEarWidth: CGFloat = 44
    /// Ears wide enough for the volume or brightness: its symbol on one side, its bar on the other.
    static let levelEarWidth: CGFloat = 64

    /// `ears` is the width of each ear when closed (0 for none); other levels ignore it.
    /// `extras` adds room for the row of extras on the primary menu, and `tiles` is how
    /// many tools have a tile there: six sit in a slightly wider row, more go in two rows.
    func bodySize(_ level: NotchLevel, ears: CGFloat = 0, extras: Bool = false, tiles: Int = 5) -> CGSize {
        switch level {
        case .rest:
            return CGSize(width: notchWidth + max(0, ears) * 2, height: notchHeight)
        case .peek:
            let width: CGFloat = tiles == HomeMenu.mostInOneRow ? 1060 : 1000
            let rows: CGFloat = tiles > HomeMenu.mostInOneRow ? NotchMetrics.twoTileRows : NotchMetrics.oneTileRow
            return CGSize(width: width, height: topRow + rows + (extras ? NotchMetrics.extrasRow : 0))
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

    /// The smallest you can drag each open level to.
    func minimumSize(_ level: NotchLevel) -> CGSize {
        switch level {
        case .rest: return bodySize(.rest)
        case .peek: return CGSize(width: 860, height: topRow + 104)
        case .lanes: return CGSize(width: 640, height: topRow + 220)
        case .detail: return CGSize(width: 820, height: topRow + 340)
        }
    }

    /// The biggest you can drag the panel: nearly the whole screen.
    var maximumSize: CGSize {
        CGSize(width: max(bodySize(.detail).width, min(screenSize.width - 32, 2000)),
               height: max(bodySize(.detail).height, min(screenSize.height - 60, 1400)))
    }

    /// A dragged size kept between the level's minimum and the screen's limit.
    func clamp(_ size: CGSize, for level: NotchLevel) -> CGSize {
        let low = minimumSize(level)
        let high = maximumSize
        return CGSize(width: min(max(size.width, low.width), high.width),
                      height: min(max(size.height, low.height), high.height))
    }

    /// The transparent window fits the biggest the panel can be dragged to, plus its shadow.
    var windowSize: CGSize {
        let largest = maximumSize
        return CGSize(width: largest.width + shoulder(.detail) * 2 + NotchMetrics.shadowMargin * 2,
                      height: largest.height + NotchMetrics.shadowMargin * 1.5)
    }
}

/// Unread counts as people write them: 7, 297, 3992. Only 10,000 and up are shortened (12k).
enum UnreadText {
    static func format(_ count: Int) -> String {
        count < 10_000 ? "\(count)" : "\(count / 1000)k"
    }
}
