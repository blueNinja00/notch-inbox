import Foundation

/// A tool with a tile on the primary menu.
enum HomeTile: String, CaseIterable, Identifiable, Codable {
    case mail
    case planner
    case assignments
    case timetable
    case notes
    case assistant
    case agents
    case bookmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mail: return "Mail"
        case .planner: return "Planner"
        case .assignments: return "Assignments"
        case .timetable: return "Timetable"
        case .notes: return "Notes"
        case .assistant: return "Assistant"
        case .agents: return "Agents"
        case .bookmarks: return "Bookmarks"
        }
    }

    var symbol: String {
        switch self {
        case .mail: return "envelope.fill"
        case .planner: return "checklist"
        case .assignments: return "list.bullet.clipboard"
        case .timetable: return "calendar"
        case .notes: return "note.text"
        case .assistant: return "sparkles"
        case .agents: return "building.2.fill"
        case .bookmarks: return "bookmark.fill"
        }
    }

    /// Its share of a row beside the others: Mail lists emails, so it's the widest.
    var weight: Double {
        switch self {
        case .mail: return 2.25
        case .planner, .timetable, .assignments: return 1.36
        case .notes: return 0.95
        case .assistant: return 0.95
        case .agents: return 1.2
        case .bookmarks: return 1.08
        }
    }
}

/// Which tools have a tile on the primary menu, and in what order. You arrange it in
/// Settings → General, or by right-clicking a tile.
struct HomeMenu: Equatable {
    /// Every tile, in your order. Hidden ones keep their place for when they're shown again.
    private(set) var order: [HomeTile]
    private(set) var hidden: Set<HomeTile>

    /// The order tiles start in.
    static let standardOrder: [HomeTile] = [.mail, .planner, .assignments, .timetable, .notes, .assistant, .agents, .bookmarks]
    static let standard = HomeMenu()

    static let orderKey = "homeMenu.order"
    static let hiddenKey = "homeMenu.hidden"

    init(order: [HomeTile] = HomeMenu.standardOrder, hidden: Set<HomeTile> = []) {
        self.order = HomeMenu.complete(order)
        self.hidden = hidden
        // Something always shows.
        if self.order.allSatisfy({ hidden.contains($0) }), let first = self.order.first {
            self.hidden.remove(first)
        }
    }

    /// From what was saved. Names this build doesn't know are dropped, and tools that are
    /// new in this build take their usual place.
    init(savedOrder: [String]?, savedHidden: [String]?) {
        let order = (savedOrder ?? []).compactMap(HomeTile.init(rawValue:))
        let hidden = Set((savedHidden ?? []).compactMap(HomeTile.init(rawValue:)))
        self.init(order: savedOrder == nil ? HomeMenu.standardOrder : order, hidden: hidden)
    }

    init(defaults: UserDefaults) {
        self.init(savedOrder: defaults.stringArray(forKey: HomeMenu.orderKey), savedHidden: defaults.stringArray(forKey: HomeMenu.hiddenKey))
    }

    func save(in defaults: UserDefaults) {
        defaults.set(order.map { $0.rawValue }, forKey: HomeMenu.orderKey)
        defaults.set(hidden.map { $0.rawValue }.sorted(), forKey: HomeMenu.hiddenKey)
    }

    /// An order with every tile in it once: repeats go, and a tile that's missing goes in
    /// after the tile it usually follows (or first, if that's missing too).
    static func complete(_ order: [HomeTile]) -> [HomeTile] {
        var result: [HomeTile] = []
        for tile in order where !result.contains(tile) {
            result.append(tile)
        }
        for (place, tile) in standardOrder.enumerated() where !result.contains(tile) {
            let before = standardOrder[..<place].reversed().first { result.contains($0) }
            if let before = before, let index = result.firstIndex(of: before) {
                result.insert(tile, at: index + 1)
            } else {
                result.insert(tile, at: 0)
            }
        }
        return result
    }

    /// The tiles on the primary menu, in order.
    var shown: [HomeTile] { order.filter { !hidden.contains($0) } }

    func isShown(_ tile: HomeTile) -> Bool { !hidden.contains(tile) }

    /// Whether a tile could be hidden: the last one showing stays.
    func canHide(_ tile: HomeTile) -> Bool {
        isShown(tile) && shown.count > 1
    }

    /// Shows or hides a tile. Returns whether anything changed.
    @discardableResult
    mutating func setShown(_ tile: HomeTile, _ show: Bool) -> Bool {
        if show {
            return hidden.remove(tile) != nil
        }
        guard canHide(tile) else { return false }
        hidden.insert(tile)
        return true
    }

    /// The tile one place before or after this one: among the tiles showing (from the
    /// primary menu) or among them all (from Settings).
    func neighbour(of tile: HomeTile, by offset: Int, amongShown: Bool) -> HomeTile? {
        let tiles = amongShown ? shown : order
        guard offset != 0, let index = tiles.firstIndex(of: tile), tiles.indices.contains(index + offset) else { return nil }
        return tiles[index + offset]
    }

    func canMove(_ tile: HomeTile, by offset: Int, amongShown: Bool) -> Bool {
        neighbour(of: tile, by: offset, amongShown: amongShown) != nil
    }

    /// Moves a tile one place, swapping with its neighbour. Returns whether it moved.
    @discardableResult
    mutating func move(_ tile: HomeTile, by offset: Int, amongShown: Bool) -> Bool {
        guard let other = neighbour(of: tile, by: offset, amongShown: amongShown),
              let from = order.firstIndex(of: tile), let to = order.firstIndex(of: other) else { return false }
        order.swapAt(from, to)
        return true
    }

    /// Back to every tile, in the order they started in.
    mutating func reset() {
        self = HomeMenu()
    }

    // MARK: Laying it out

    /// The most tiles that sit comfortably in one row.
    static let mostInOneRow = 6

    /// Rows of tiles at the menu's standard size.
    var rows: Int { shown.count > HomeMenu.mostInOneRow ? 2 : 1 }

    /// Changes when the menu's standard size does, so a size dragged for one arrangement
    /// isn't kept for another.
    var sizeClass: Int {
        let count = shown.count
        if count > HomeMenu.mostInOneRow { return 2 }
        return count == HomeMenu.mostInOneRow ? 1 : 0
    }

    /// How wide each of these tiles is, side by side in `width`, by their weights.
    static func widths(of tiles: [HomeTile], in width: Double, spacing: Double = 8) -> [Double] {
        guard !tiles.isEmpty else { return [] }
        let space = max(0, width - spacing * Double(tiles.count - 1))
        let total = tiles.reduce(0) { $0 + $1.weight }
        return tiles.map { (space * $0.weight / total).rounded(.down) }
    }

    /// The menu when it's tall: Mail down the left, if it's showing, and the other tiles in
    /// two rows beside it, in order.
    struct Tall: Equatable {
        var mail: Bool
        var top: [HomeTile]
        var bottom: [HomeTile]

        /// The share of the width the two rows take, beside Mail.
        var share: Double {
            guard mail else { return 1 }
            switch top.count {
            case 0: return 0
            case 1: return 0.34
            case 2: return 0.46
            case 3: return 0.58
            default: return 0.68
            }
        }
    }

    var tall: Tall {
        let tiles = shown
        let others = tiles.filter { $0 != .mail }
        let first = (others.count + 1) / 2
        return Tall(mail: tiles.contains(.mail), top: Array(others.prefix(first)), bottom: Array(others.dropFirst(first)))
    }
}
