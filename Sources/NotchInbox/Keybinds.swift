import Foundation

/// A key and the modifier keys held with it, as a shortcut: ⌘N, ⇧⌘↩.
struct KeyCombo: Codable, Hashable {
    /// The key, by its place on the keyboard (macOS's key code), so that a shortcut is
    /// the same keys whatever they type.
    var code: Int
    var command: Bool
    var control: Bool
    var option: Bool
    var shift: Bool
    /// What's on the key, to show it: "N", "↩", "F5".
    var symbol: String

    init(code: Int, symbol: String, command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false) {
        self.code = code
        self.symbol = symbol
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }

    private enum CodingKeys: String, CodingKey {
        case code, command, control, option, shift, symbol
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decode(Int.self, forKey: .code)
        command = (try? values.decodeIfPresent(Bool.self, forKey: .command)) ?? false
        control = (try? values.decodeIfPresent(Bool.self, forKey: .control)) ?? false
        option = (try? values.decodeIfPresent(Bool.self, forKey: .option)) ?? false
        shift = (try? values.decodeIfPresent(Bool.self, forKey: .shift)) ?? false
        let saved = (try? values.decodeIfPresent(String.self, forKey: .symbol)) ?? ""
        symbol = saved.isEmpty ? KeyCombo.symbol(code: code, characters: nil) : saved
    }

    /// Two shortcuts are the same when they're the same keys, whatever is printed on them.
    static func == (one: KeyCombo, other: KeyCombo) -> Bool {
        one.code == other.code && one.command == other.command && one.control == other.control
            && one.option == other.option && one.shift == other.shift
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(command)
        hasher.combine(control)
        hasher.combine(option)
        hasher.combine(shift)
    }

    /// "⌃⌥⇧⌘N": the modifiers in the order macOS writes them, then the key.
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + symbol
    }

    /// For VoiceOver and tooltips: "Command N".
    var spoken: String {
        var parts: [String] = []
        if control { parts.append("Control") }
        if option { parts.append("Option") }
        if shift { parts.append("Shift") }
        if command { parts.append("Command") }
        parts.append(KeyCombo.spokenNames[code] ?? symbol)
        return parts.joined(separator: " ")
    }

    // MARK: Keys

    static let returnKey = 36
    static let escape = 53
    static let delete = 51
    static let forwardDelete = 117
    static let left = 123
    static let right = 124
    static let down = 125
    static let up = 126

    /// Keys that don't type a character, as they're shown.
    static let named: [Int: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let spokenNames: [Int: String] = [
        36: "Return", 76: "Enter", 48: "Tab", 49: "Space", 51: "Delete", 117: "Forward Delete", 53: "Escape",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    /// The function keys, which can be a shortcut by themselves.
    static let functionKeys: Set<Int> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    /// The keys a standard keyboard has, for a shortcut that was saved without what's on its key.
    private static let printed: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
    ]

    /// What to show for a key: its name if it has one, otherwise what it types, in capitals.
    static func symbol(code: Int, characters: String?) -> String {
        if let name = named[code] {
            return name
        }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = typed.first, typed.count == 1, !first.isNewline {
            return String(first).uppercased()
        }
        return printed[code] ?? "Key \(code)"
    }

    /// A shortcut on a letter, number or mark, as a standard keyboard has them.
    static func standard(_ key: Character, command: Bool = true, control: Bool = false, option: Bool = false, shift: Bool = false) -> KeyCombo? {
        let wanted = String(key).uppercased()
        guard let code = printed.first(where: { $0.value == wanted })?.key else { return nil }
        return KeyCombo(code: code, symbol: wanted, command: command, control: control, option: option, shift: shift)
    }

    /// A shortcut on a key that has a name: Return, Delete, an arrow.
    static func standard(code: Int, command: Bool = true, control: Bool = false, option: Bool = false, shift: Bool = false) -> KeyCombo {
        KeyCombo(code: code, symbol: symbol(code: code, characters: nil), command: command, control: control, option: option, shift: shift)
    }

    // MARK: What can be a shortcut

    /// Whether it has a modifier that keeps it from being typed by accident.
    var hasModifier: Bool { command || control || option }

    /// Shortcuts that edit text, which aren't taken over: cut, copy, paste, select all,
    /// undo and redo. And ⌘Q, which nothing here should be one slip away from.
    var isReserved: Bool {
        guard command, !control, !option else { return false }
        if !shift, [7, 8, 9, 0, 6, 12].contains(code) { return true }
        return shift && code == 6
    }

    /// Whether it also means something while typing: moving through text with ⌘ or ⌥ and
    /// an arrow, or deleting a word or a line. While there's text in the box being typed
    /// in, these are left to the text.
    var editsText: Bool {
        guard command || option, !control else { return false }
        return [KeyCombo.left, KeyCombo.right, KeyCombo.up, KeyCombo.down, KeyCombo.delete, KeyCombo.forwardDelete].contains(code)
    }

    /// Why this can't be a shortcut, or nil if it can.
    var problem: String? {
        if code == KeyCombo.escape && !hasModifier {
            return "Esc goes back, so it can't be a shortcut by itself."
        }
        if isReserved {
            return "\(label) is kept for editing text (or quitting), so it can't be used."
        }
        if !hasModifier && !KeyCombo.functionKeys.contains(code) {
            return "A shortcut needs ⌘, ⌃ or ⌥ with the key (or to be an F-key), so that it can't be typed by accident."
        }
        return nil
    }
}

/// Something a shortcut can do.
enum KeyAction: String, CaseIterable, Codable, Identifiable {
    // In the agent room.
    case newTask
    case startAll
    case stopAll
    case toggleTask
    case againTask
    case openTask
    case removeTask
    case clearDone
    case nextTask
    case previousTask
    case nextGroup
    case previousGroup
    case newGroup
    case chain
    case library
    case recipes
    case teamChat
    case searchLibrary
    // Anywhere in the notch.
    case goHome
    case goMail
    case goPlanner
    case goTimetable
    case goAssignments
    case goNotes
    case goAssistant
    case goAgents
    case goBookmarks
    case goSettings

    var id: String { rawValue }

    /// Where a shortcut works.
    enum Scope: String, CaseIterable {
        /// While the agent room is showing.
        case agents
        /// Wherever you are in the open notch.
        case anywhere

        var title: String {
            switch self {
            case .agents: return "In the Agents room"
            case .anywhere: return "Anywhere in the notch"
            }
        }

        var detail: String {
            switch self {
            case .agents: return "These work while the Agents room is open, even while you're typing a task."
            case .anywhere: return "These work wherever you are, once you've clicked in the open notch. None has a key until you give it one."
            }
        }

        var actions: [KeyAction] { KeyAction.allCases.filter { $0.scope == self } }
    }

    var scope: Scope {
        switch self {
        case .goHome, .goMail, .goPlanner, .goTimetable, .goAssignments, .goNotes, .goAssistant, .goAgents, .goBookmarks, .goSettings:
            return .anywhere
        default:
            return .agents
        }
    }

    var title: String {
        switch self {
        case .newTask: return "New task"
        case .startAll: return "Start all in the group"
        case .stopAll: return "Stop all in the group"
        case .toggleTask: return "Start or stop the selected task"
        case .againTask: return "Run the selected task again"
        case .openTask: return "Open or close the selected task"
        case .removeTask: return "Remove the selected task"
        case .clearDone: return "Clear finished tasks from the group"
        case .nextTask: return "Select the next task"
        case .previousTask: return "Select the previous task"
        case .nextGroup: return "Next group"
        case .previousGroup: return "Previous group"
        case .newGroup: return "New group"
        case .chain: return "Switch Chain on or off"
        case .library: return "Library"
        case .recipes: return "Recipes"
        case .teamChat: return "Team chat"
        case .searchLibrary: return "Search the library"
        case .goHome: return "Primary menu"
        case .goMail: return "Mail"
        case .goPlanner: return "Planner"
        case .goTimetable: return "Timetable"
        case .goAssignments: return "Assignments"
        case .goNotes: return "Notes"
        case .goAssistant: return "Assistant"
        case .goAgents: return "Agents room"
        case .goBookmarks: return "Bookmarks"
        case .goSettings: return "Settings"
        }
    }

    /// Its key until you change it. The ones that go somewhere start with none.
    var standard: KeyCombo? {
        switch self {
        case .newTask: return KeyCombo.standard("N")
        case .startAll: return KeyCombo.standard(code: KeyCombo.returnKey)
        case .stopAll: return KeyCombo.standard(".")
        case .toggleTask: return KeyCombo.standard("S")
        case .againTask: return KeyCombo.standard("D")
        case .openTask: return KeyCombo.standard("O")
        case .removeTask: return KeyCombo.standard(code: KeyCombo.delete)
        case .clearDone: return KeyCombo.standard(code: KeyCombo.delete, shift: true)
        case .nextTask: return KeyCombo.standard(code: KeyCombo.down)
        case .previousTask: return KeyCombo.standard(code: KeyCombo.up)
        case .nextGroup: return KeyCombo.standard("]")
        case .previousGroup: return KeyCombo.standard("[")
        case .newGroup: return KeyCombo.standard("N", shift: true)
        case .chain: return KeyCombo.standard("K")
        case .library: return KeyCombo.standard("L")
        case .recipes: return KeyCombo.standard("R")
        case .teamChat: return KeyCombo.standard("T")
        case .searchLibrary: return KeyCombo.standard("F")
        default: return nil
        }
    }
}

/// Your shortcuts: each action's key, where you've changed it from the one it came with.
struct Keybinds: Codable, Equatable {
    /// Keys you've given actions yourself.
    private(set) var changed: [String: KeyCombo] = [:]
    /// Actions you've taken the key off.
    private(set) var cleared: [String] = []

    private enum CodingKeys: String, CodingKey {
        case changed, cleared
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let saved = (try? values.decodeIfPresent([String: KeyCombo].self, forKey: .changed)) ?? [:]
        // (Only actions there still are, with keys that can still be shortcuts.)
        changed = saved.filter { KeyAction(rawValue: $0.key) != nil && $0.value.problem == nil }
        cleared = ((try? values.decodeIfPresent([String].self, forKey: .cleared)) ?? []).filter { KeyAction(rawValue: $0) != nil && changed[$0] == nil }
    }

    /// The key an action has now: yours, or the one it came with, or none.
    func combo(for action: KeyAction) -> KeyCombo? {
        if let own = changed[action.rawValue] {
            return own
        }
        return cleared.contains(action.rawValue) ? nil : action.standard
    }

    /// "⌘N", or "" for an action with no key.
    func label(for action: KeyAction) -> String {
        combo(for: action)?.label ?? ""
    }

    /// For a button's tooltip: " (⌘N)", or nothing.
    func hint(for action: KeyAction) -> String {
        let key = label(for: action)
        return key.isEmpty ? "" : " (\(key))"
    }

    func isChanged(_ action: KeyAction) -> Bool {
        changed[action.rawValue] != nil || cleared.contains(action.rawValue)
    }

    var anyChanged: Bool { !changed.isEmpty || !cleared.isEmpty }

    /// The action that has a key, if any.
    func owner(of combo: KeyCombo) -> KeyAction? {
        KeyAction.allCases.first { self.combo(for: $0) == combo }
    }

    /// What a pressed key does. A shortcut for the agent room only counts there.
    func action(for combo: KeyCombo, inAgents: Bool) -> KeyAction? {
        guard let action = owner(of: combo) else { return nil }
        return action.scope == .agents && !inAgents ? nil : action
    }

    /// Gives an action a key. If another action had that key, it loses it, and is returned.
    /// Nothing changes for a key that can't be a shortcut.
    @discardableResult
    mutating func set(_ combo: KeyCombo, for action: KeyAction) -> KeyAction? {
        guard combo.problem == nil else { return nil }
        let before = owner(of: combo)
        if let other = before, other != action {
            clear(other)
        }
        cleared.removeAll { $0 == action.rawValue }
        if action.standard == combo {
            changed[action.rawValue] = nil
        } else {
            changed[action.rawValue] = combo
        }
        return before == action ? nil : before
    }

    /// Takes an action's key off.
    mutating func clear(_ action: KeyAction) {
        changed[action.rawValue] = nil
        cleared.removeAll { $0 == action.rawValue }
        if action.standard != nil {
            cleared.append(action.rawValue)
        }
    }

    /// Puts an action back on the key it came with. If another action has been given
    /// that key since, that one loses it, and is returned.
    @discardableResult
    mutating func reset(_ action: KeyAction) -> KeyAction? {
        changed[action.rawValue] = nil
        cleared.removeAll { $0 == action.rawValue }
        guard let standard = action.standard else { return nil }
        let other = KeyAction.allCases.first { $0 != action && self.combo(for: $0) == standard }
        if let other = other {
            clear(other)
        }
        return other
    }

    mutating func resetAll() {
        changed = [:]
        cleared = []
    }

    /// What Settings says after a key is set: who lost it, if anyone did.
    static func note(set combo: KeyCombo, for action: KeyAction, taking other: KeyAction?) -> String {
        guard let other = other else { return "\(combo.label) is now “\(action.title)”." }
        return "\(combo.label) is now “\(action.title)”. “\(other.title)” has no key any more."
    }

    // MARK: Keeping them

    static let key = "shortcuts"

    static func saved(in defaults: UserDefaults) -> Keybinds {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Keybinds.self, from: data) else { return Keybinds() }
        return saved
    }

    func save(in defaults: UserDefaults) {
        guard anyChanged, let data = try? JSONEncoder().encode(self) else {
            defaults.removeObject(forKey: Keybinds.key)
            return
        }
        defaults.set(data, forKey: Keybinds.key)
    }
}
