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

/// The palette from the design canvas.
enum Theme {
    static let surface = Color(hex: 0x141416)      // reading pane, hover tiles
    static let raised = Color(hex: 0x1E1E21)       // pills, selected rows
    static let lane = Color(hex: 0x0E0E10)         // lane and rail backgrounds
    static let unreadCard = Color(hex: 0x18181B)
    static let hover = Color(hex: 0x26262A)
    static let avatar = Color(hex: 0x232327)
    static let composer = Color(hex: 0x0B0B0C)
    static let keyCap = Color(hex: 0x1A1A1D)

    static let text = Color(hex: 0xF5F5F7)
    static let text2 = Color(hex: 0xE4E4E7)
    static let body = Color(hex: 0xC8C8D0)
    static let secondary = Color(hex: 0xB4B4BC)
    static let readText = Color(hex: 0xA1A1AA)
    static let tertiary = Color(hex: 0x8E8E96)
    static let onAccent = Color(hex: 0x0B0B0C)

    static let hairline = Color.white.opacity(0.06)

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
}
