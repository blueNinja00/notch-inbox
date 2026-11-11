import Foundation

/// The colours a theme is made of, as 0xRRGGBB. The notch itself stays black whatever the
/// theme, because it hangs from the camera housing, which is black; a theme colours what
/// sits on it: tiles, panels, text, and the accent on buttons and whatever's selected.
struct ThemePalette: Equatable {
    // Backgrounds, darkest to lightest.
    var composer: UInt32
    var lane: UInt32
    var surface: UInt32
    var unreadCard: UInt32
    var keyCap: UInt32
    var raised: UInt32
    var avatar: UInt32
    var hover: UInt32

    // Text, brightest to faintest.
    var text: UInt32
    var text2: UInt32
    var body: UInt32
    var secondary: UInt32
    var readText: UInt32
    var tertiary: UInt32

    /// Buttons to press, the selected choice, today, unread dots.
    var accent: UInt32
    /// Text and icons on the accent.
    var onAccent: UInt32

    /// The neutral palette the app was designed with: near-black and greys, white accent.
    static let midnight = ThemePalette(
        composer: 0x0B0B0C, lane: 0x0E0E10, surface: 0x141416, unreadCard: 0x18181B, keyCap: 0x1A1A1D,
        raised: 0x1E1E21, avatar: 0x232327, hover: 0x26262A,
        text: 0xF5F5F7, text2: 0xE4E4E7, body: 0xC8C8D0, secondary: 0xB4B4BC, readText: 0xA1A1AA, tertiary: 0x8E8E96,
        accent: 0xF5F5F7, onAccent: 0x0B0B0C)

    /// The neutral palette washed with a colour: backgrounds take on its hue (more of it the
    /// lighter they are), text only a trace, and the accent is the colour itself.
    static func tinted(_ tint: UInt32, strength: Double = 1) -> ThemePalette {
        let base = midnight
        func back(_ colour: UInt32, _ amount: Double) -> UInt32 { ThemeColour.mix(colour, tint, amount * strength) }
        func ink(_ colour: UInt32, _ amount: Double) -> UInt32 { ThemeColour.mix(colour, tint, amount * strength) }
        return ThemePalette(
            composer: back(base.composer, 0.05), lane: back(base.lane, 0.07), surface: back(base.surface, 0.10),
            unreadCard: back(base.unreadCard, 0.12), keyCap: back(base.keyCap, 0.12), raised: back(base.raised, 0.14),
            avatar: back(base.avatar, 0.15), hover: back(base.hover, 0.17),
            text: ink(base.text, 0.03), text2: ink(base.text2, 0.05), body: ink(base.body, 0.08),
            secondary: ink(base.secondary, 0.10), readText: ink(base.readText, 0.10), tertiary: ink(base.tertiary, 0.12),
            accent: tint,
            onAccent: ThemeColour.luminance(tint) > 0.18 ? base.onAccent : 0xFFFFFF)
    }
}

/// Sums on colours: blending two, and how well one reads on another.
enum ThemeColour {
    static func parts(_ colour: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((colour >> 16) & 0xFF), Double((colour >> 8) & 0xFF), Double(colour & 0xFF))
    }

    /// `amount` of the way from one colour to another (0 is the first, 1 the second).
    static func mix(_ first: UInt32, _ second: UInt32, _ amount: Double) -> UInt32 {
        let share = min(1, max(0, amount))
        let a = parts(first)
        let b = parts(second)
        func blend(_ x: Double, _ y: Double) -> UInt32 { UInt32((x * (1 - share) + y * share).rounded()) }
        return (blend(a.red, b.red) << 16) | (blend(a.green, b.green) << 8) | blend(a.blue, b.blue)
    }

    /// How bright a colour looks, 0 (black) to 1 (white), the way the web's contrast rules
    /// work it out.
    static func luminance(_ colour: UInt32) -> Double {
        func linear(_ value: Double) -> Double {
            let share = value / 255
            return share <= 0.03928 ? share / 12.92 : pow((share + 0.055) / 1.055, 2.4)
        }
        let c = parts(colour)
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    /// How well one colour reads on another: 1 (the same) to 21 (black on white). Body text
    /// wants 4.5 or more.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The themes to choose from, in Settings → General.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case midnight
    case graphite
    case ocean
    case forest
    case sunset
    case grape
    case rose
    case contrast

    static let standard = ThemeChoice.midnight
    static let key = "theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .sunset: return "Sunset"
        case .grape: return "Grape"
        case .rose: return "Rose"
        case .contrast: return "High contrast"
        }
    }

    var detail: String {
        switch self {
        case .midnight: return "Black and grey"
        case .graphite: return "Softer greys"
        case .ocean: return "Deep blue"
        case .forest: return "Dark green"
        case .sunset: return "Warm orange"
        case .grape: return "Purple"
        case .rose: return "Pink"
        case .contrast: return "Brighter text"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .midnight:
            return .midnight
        case .graphite:
            return ThemePalette(
                composer: 0x111113, lane: 0x161618, surface: 0x1D1D20, unreadCard: 0x232327, keyCap: 0x26262A,
                raised: 0x2B2B30, avatar: 0x313137, hover: 0x36363C,
                text: 0xF5F5F7, text2: 0xE6E6EA, body: 0xCDCDD4, secondary: 0xBABAC2, readText: 0xA8A8B1, tertiary: 0x96969F,
                accent: 0xE8E8ED, onAccent: 0x111113)
        case .ocean:
            return .tinted(0x5E9EFF)
        case .forest:
            return .tinted(0x3DD6A3, strength: 0.85)
        case .sunset:
            return .tinted(0xFF9F5A, strength: 0.8)
        case .grape:
            return .tinted(0xB18CFF, strength: 0.95)
        case .rose:
            return .tinted(0xFF7AC6, strength: 0.8)
        case .contrast:
            return ThemePalette(
                composer: 0x000000, lane: 0x060607, surface: 0x0D0D0F, unreadCard: 0x151518, keyCap: 0x1A1A1E,
                raised: 0x222226, avatar: 0x2A2A2F, hover: 0x303036,
                text: 0xFFFFFF, text2: 0xF4F4F6, body: 0xE2E2E8, secondary: 0xD2D2DA, readText: 0xC2C2CC, tertiary: 0xB0B0BC,
                accent: 0xFFD60A, onAccent: 0x000000)
        }
    }

    /// The theme chosen in Settings (kept in this app's settings).
    static func saved(in defaults: UserDefaults = .standard) -> ThemeChoice {
        defaults.string(forKey: key).flatMap(ThemeChoice.init(rawValue:)) ?? standard
    }
}
