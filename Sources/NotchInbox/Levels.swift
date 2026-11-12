import Foundation

/// A level the notch can show and change: the Mac's volume, or its display's brightness.
enum LevelKind: String, CaseIterable {
    case volume
    case brightness

    var title: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        }
    }
}

/// How loud or how bright, right now.
struct LevelReading: Equatable {
    var kind: LevelKind
    /// From 0 (off) to 1 (full).
    var value: Double
    /// Sound only: muted, whatever the volume is set to.
    var muted: Bool

    init(kind: LevelKind, value: Double, muted: Bool = false) {
        self.kind = kind
        self.value = value.isFinite ? min(max(value, 0), 1) : 0
        self.muted = kind == .volume && muted
    }

    /// What the bar shows: nothing while muted.
    var shown: Double { muted ? 0 : value }

    var percent: Int { Int((shown * 100).rounded()) }

    /// A speaker with more waves the louder it is, or a sun.
    var symbol: String {
        switch kind {
        case .volume:
            if muted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    /// The same reading to the nearest fiftieth, so a gauge that's always on show isn't
    /// redrawn for changes too small to see.
    var rounded: LevelReading {
        LevelReading(kind: kind, value: (value * 50).rounded() / 50, muted: muted)
    }

    /// "Volume 44%", "Muted", "Brightness 80%".
    var label: String {
        if kind == .volume && muted { return "Muted" }
        return "\(kind.title) \(percent)%"
    }
}

/// The steps a key press moves a level by: sixteen from nothing to full, like macOS, or a
/// quarter of one with Shift and Option held.
enum LevelSteps {
    static let count = 16

    static func step(_ value: Double, up: Bool, fine: Bool = false) -> Double {
        let steps = Double(fine ? count * 4 : count)
        let position = min(max(value, 0), 1) * steps
        // From between two steps, a press goes to the next whole one.
        let next = up ? (position + 0.0001).rounded(.down) + 1 : (position - 0.0001).rounded(.up) - 1
        return min(max(next / steps, 0), 1)
    }
}

/// The keys along the top of the keyboard that change sound and brightness.
enum MediaKey: Int, CaseIterable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7

    /// A key going down or coming up, as macOS reports it.
    struct Press: Equatable {
        let key: MediaKey
        let down: Bool
        /// Held down: this is the key repeating.
        let repeated: Bool
    }

    var kind: LevelKind {
        switch self {
        case .soundUp, .soundDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        }
    }

    /// Reads a "system-defined" event: these keys come as subtype 8, with the key and
    /// whether it went down or up packed into one number.
    static func press(subtype: Int, data1: Int) -> Press? {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF0000) >> 16
        let flags = data1 & 0x0000FFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code), state == 0xA || state == 0xB else { return nil }
        return Press(key: key, down: state == 0xA, repeated: flags & 0x1 == 1)
    }
}

/// Decides when a change of level is worth showing at the notch.
struct LevelWatch: Equatable {
    private(set) var last: [LevelKind: LevelReading] = [:]

    /// Brightness drifts a little by itself as the room's light changes; only a jump like
    /// a key press counts.
    static let brightnessJump = 0.02
    static let volumeJump = 0.004

    /// Takes a new reading and says whether the notch should show it. `own` is a change
    /// made in the notch itself (dragging its slider), which needs no showing. `pressed`
    /// is a key press, which shows even at the top or bottom, where nothing changes.
    /// `showing` is whether this level is on show already: then it follows every change.
    mutating func take(_ reading: LevelReading, own: Bool = false, pressed: Bool = false, showing: Bool = false) -> Bool {
        let before = last[reading.kind]
        last[reading.kind] = reading
        if own { return false }
        if pressed { return true }
        guard let before = before else { return false }
        if showing { return before != reading }
        switch reading.kind {
        case .volume:
            return before.muted != reading.muted || abs(before.value - reading.value) >= LevelWatch.volumeJump
        case .brightness:
            return abs(before.value - reading.value) >= LevelWatch.brightnessJump
        }
    }

    /// What a key press does to a level: the new reading, or nil if there's nothing to change.
    static func after(_ key: MediaKey, from reading: LevelReading, fine: Bool = false) -> LevelReading? {
        guard key.kind == reading.kind else { return nil }
        switch key {
        case .mute:
            return LevelReading(kind: .volume, value: reading.value, muted: !reading.muted)
        case .soundUp:
            // Either volume key also unmutes.
            return LevelReading(kind: .volume, value: LevelSteps.step(reading.value, up: true, fine: fine), muted: false)
        case .soundDown:
            return LevelReading(kind: .volume, value: LevelSteps.step(reading.value, up: false, fine: fine), muted: false)
        case .brightnessUp:
            return LevelReading(kind: .brightness, value: LevelSteps.step(reading.value, up: true, fine: fine))
        case .brightnessDown:
            return LevelReading(kind: .brightness, value: LevelSteps.step(reading.value, up: false, fine: fine))
        }
    }
}
