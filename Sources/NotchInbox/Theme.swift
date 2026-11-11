import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension MailAccount {
    var color: Color { Color(hex: colorHex) }
}

/// The colours everything is drawn with. They come from the theme chosen in Settings →
/// General; the notch redraws itself when that changes. The notch's own shape stays black.
enum Theme {
    /// The chosen theme's colours.
    static var palette: ThemePalette { AppSettings.shared.palette }

    static var surface: Color { Color(hex: palette.surface) }        // reading pane, tiles
    static var raised: Color { Color(hex: palette.raised) }          // pills, selected rows
    static var lane: Color { Color(hex: palette.lane) }              // lane and rail backgrounds
    static var unreadCard: Color { Color(hex: palette.unreadCard) }
    static var hover: Color { Color(hex: palette.hover) }
    static var avatar: Color { Color(hex: palette.avatar) }
    static var composer: Color { Color(hex: palette.composer) }
    static var keyCap: Color { Color(hex: palette.keyCap) }

    static var text: Color { Color(hex: palette.text) }
    static var text2: Color { Color(hex: palette.text2) }
    static var body: Color { Color(hex: palette.body) }
    static var secondary: Color { Color(hex: palette.secondary) }
    static var readText: Color { Color(hex: palette.readText) }
    static var tertiary: Color { Color(hex: palette.tertiary) }

    /// Buttons to press, the selected choice, today, unread dots; and what's written on them.
    static var accent: Color { Color(hex: palette.accent) }
    static var onAccent: Color { Color(hex: palette.onAccent) }

    static let hairline = Color.white.opacity(0.06)

    /// Overdue, due today, and all's well.
    static let danger = Color(hex: 0xFF6B6B)
    static let warning = Color(hex: 0xFFB547)
    static let good = Color(hex: 0x34C759)

    /// Subject colours for the timetable: bright enough to read on black, distinct side by side.
    static let subjectHexes: [UInt32] = [0x5E9EFF, 0x3DD6A3, 0xFFB547, 0xFF6B6B, 0xB18CFF, 0xFF7AC6, 0x56CFE1, 0xA6D85A]

    static func subject(_ index: Int) -> Color {
        Color(hex: subjectHexes[((index % subjectHexes.count) + subjectHexes.count) % subjectHexes.count])
    }

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
}
