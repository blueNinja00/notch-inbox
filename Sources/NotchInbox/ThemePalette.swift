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

extension ThemePalette {
    /// The backgrounds, darkest to lightest.
    var backgrounds: [UInt32] {
        get { [composer, lane, surface, unreadCard, keyCap, raised, avatar, hover] }
        set {
            guard newValue.count == 8 else { return }
            composer = newValue[0]
            lane = newValue[1]
            surface = newValue[2]
            unreadCard = newValue[3]
            keyCap = newValue[4]
            raised = newValue[5]
            avatar = newValue[6]
            hover = newValue[7]
        }
    }

    /// A colour made brighter, a little at a time, until it reads this well on a background.
    static func readable(_ colour: UInt32, on background: UInt32, atLeast contrast: Double) -> UInt32 {
        var result = colour
        for _ in 0..<60 {
            if ThemeColour.contrast(result, background) >= contrast { return result }
            result = ThemeColour.mix(result, 0xFFFFFF, 0.07)
        }
        return 0xFFFFFF
    }

    /// Makes any palette one that works on the notch: backgrounds dark enough to sit on
    /// black and stepping up in order, every kind of text bright enough to read on them,
    /// and an accent that stands out with a label that reads.
    mutating func settle() {
        // Backgrounds: darker all together until white text would read on them.
        var list = backgrounds
        for _ in 0..<60 {
            let dark = ThemeColour.luminance(list[7]) < 0.066 && ThemeColour.luminance(list[5]) < 0.058
                && ThemeColour.luminance(list[3]) < 0.045 && ThemeColour.luminance(list[2]) < 0.032
            if dark { break }
            list = list.map { ThemeColour.mix($0, 0x000000, 0.06) }
        }
        for index in list.indices.dropFirst() where ThemeColour.luminance(list[index]) < ThemeColour.luminance(list[index - 1]) {
            list[index] = list[index - 1]
        }
        backgrounds = list

        // Text, brightest to faintest.
        text = ThemePalette.readable(text, on: surface, atLeast: 12.3)
        text2 = ThemePalette.readable(text2, on: raised, atLeast: 9.3)
        body = ThemePalette.readable(body, on: surface, atLeast: 7.3)
        secondary = ThemePalette.readable(secondary, on: surface, atLeast: 6.3)
        readText = ThemePalette.readable(readText, on: unreadCard, atLeast: 4.8)
        tertiary = ThemePalette.readable(ThemePalette.readable(tertiary, on: surface, atLeast: 4.8), on: raised, atLeast: 4.3)

        accent = ThemePalette.readable(accent, on: surface, atLeast: 4.8)
        onAccent = ThemeColour.contrast(0x0B0B0C, accent) >= ThemeColour.contrast(0xFFFFFF, accent) ? 0x0B0B0C : 0xFFFFFF
    }
}

/// A theme you make yourself, in Settings → General: a colour that washes the tiles, how
/// much of it, how bright the tiles are, and the accent on buttons and whatever's selected.
/// Whatever you pick, text is kept readable and the tiles dark enough for the black notch.
struct CustomTheme: Equatable {
    /// How much of the colour the tiles take on.
    enum Strength: String, CaseIterable {
        case subtle
        case medium
        case strong

        var title: String {
            switch self {
            case .subtle: return "Subtle"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }

        var amount: Double {
            switch self {
            case .subtle: return 0.5
            case .medium: return 0.95
            case .strong: return 1.5
            }
        }
    }

    /// How bright the tiles are.
    enum Tiles: String, CaseIterable {
        case darker
        case standard
        case lighter

        var title: String {
            switch self {
            case .darker: return "Darker"
            case .standard: return "Standard"
            case .lighter: return "Lighter"
            }
        }
    }

    /// The colour that washes the tiles.
    var tint: UInt32 = 0x56CFE1
    var strength: Strength = .medium
    var tiles: Tiles = .standard
    /// The accent, when it isn't the colour itself.
    var accent: UInt32? = nil

    /// Colours to pick from; any other can be typed as a hex code.
    static let swatches: [UInt32] = [
        0xFF6B6B, 0xFF9F5A, 0xFFB547, 0xFFD60A, 0xA6D85A, 0x34C759, 0x3DD6A3, 0x56CFE1,
        0x64B5FF, 0x5E9EFF, 0x7B8CFF, 0xB18CFF, 0xE879F9, 0xFF7AC6, 0xD6C3A5, 0xC8C8D0,
    ]

    /// Accents to pick from, besides the colour itself.
    static let accents: [UInt32] = [0xF5F5F7, 0xFFD60A, 0xFF6B6B, 0x34C759, 0x5E9EFF, 0xFF7AC6]

    var palette: ThemePalette {
        var palette = ThemePalette.tinted(tint, strength: strength.amount)
        switch tiles {
        case .darker:
            palette.backgrounds = palette.backgrounds.map { ThemeColour.mix($0, 0x000000, 0.4) }
        case .standard:
            break
        case .lighter:
            let lift = ThemeColour.mix(0x55555E, tint, 0.3)
            palette.backgrounds = palette.backgrounds.map { ThemeColour.mix($0, lift, 0.2) }
        }
        palette.accent = accent ?? tint
        palette.settle()
        return palette
    }

    // MARK: Hex codes

    /// "#5E9EFF", "5e9eff" or "#59f" as a colour; nil if it isn't one.
    static func colour(fromHex typed: String) -> UInt32? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.hasPrefix("0x") { text.removeFirst(2) }
        guard text.allSatisfy({ $0.isHexDigit }) else { return nil }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 else { return nil }
        return UInt32(text, radix: 16)
    }

    /// 0x5E9EFF → "#5E9EFF".
    static func hex(_ colour: UInt32) -> String {
        let digits = String(colour & 0xFFFFFF, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    // MARK: Remembering it

    static let key = "customTheme"

    /// As kept in this app's settings.
    var saved: [String: Any] {
        var values: [String: Any] = ["tint": Int(tint), "strength": strength.rawValue, "tiles": tiles.rawValue]
        if let accent = accent {
            values["accent"] = Int(accent)
        }
        return values
    }

    init() {}

    init(tint: UInt32, strength: Strength = .medium, tiles: Tiles = .standard, accent: UInt32? = nil) {
        self.tint = tint & 0xFFFFFF
        self.strength = strength
        self.tiles = tiles
        self.accent = accent.map { $0 & 0xFFFFFF }
    }

    init(saved: [String: Any]?) {
        guard let saved = saved else { return }
        if let tint = saved["tint"] as? Int, (0...0xFFFFFF).contains(tint) {
            self.tint = UInt32(tint)
        }
        if let strength = (saved["strength"] as? String).flatMap(Strength.init(rawValue:)) {
            self.strength = strength
        }
        if let tiles = (saved["tiles"] as? String).flatMap(Tiles.init(rawValue:)) {
            self.tiles = tiles
        }
        if let accent = saved["accent"] as? Int, (0...0xFFFFFF).contains(accent) {
            self.accent = UInt32(accent)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> CustomTheme {
        CustomTheme(saved: defaults.dictionary(forKey: key))
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(saved, forKey: CustomTheme.key)
    }

    /// Changes whenever the colours would.
    var stamp: String {
        "\(CustomTheme.hex(tint))-\(strength.rawValue)-\(tiles.rawValue)-\(accent.map(CustomTheme.hex) ?? "same")"
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
    /// The one you make yourself.
    case custom

    /// The ready-made themes.
    static let presets: [ThemeChoice] = allCases.filter { $0 != .custom }

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
        case .custom: return "Your own"
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
        case .custom: return "Colours you pick"
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
        case .custom:
            return CustomTheme.load().palette
        }
    }

    /// The theme chosen in Settings (kept in this app's settings).
    static func saved(in defaults: UserDefaults = .standard) -> ThemeChoice {
        defaults.string(forKey: key).flatMap(ThemeChoice.init(rawValue:)) ?? standard
    }
}
