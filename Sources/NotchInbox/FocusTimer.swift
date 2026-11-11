import Foundation
#if canImport(Combine)
import Combine
#endif

/// A stretch of focus, or the break after it.
struct FocusSession: Equatable {
    enum Phase: Equatable {
        case focus
        case rest
    }

    var phase: Phase
    /// What you're working on, if you said.
    var title: String
    /// The homework it's for, to tick off afterwards.
    var taskID: UUID?
    /// How long it runs in all, in seconds.
    var length: TimeInterval
    /// When it ends, while it's running.
    var ends: Date
    /// What was left when you paused it; nil while it runs.
    var pausedWith: TimeInterval?
    /// It ran out: waiting for you to start a break or another round.
    var finished = false

    var isPaused: Bool { pausedWith != nil }

    /// Seconds left.
    func remaining(now: Date) -> TimeInterval {
        if finished { return 0 }
        return max(0, pausedWith ?? ends.timeIntervalSince(now))
    }

    /// How far through it is, 0 to 1.
    func progress(now: Date) -> Double {
        guard length > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(now: now) / length))
    }

    /// "24:59", or "1:05:00" for more than an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// "25m" for the closed notch: whole minutes left, rounded up.
    static func short(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded(.up)))m"
    }
}

/// The focus timer: a stretch of work (25 minutes unless you choose otherwise), then a short
/// break. One for every screen's notch.
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    static let focusChoices = [15, 25, 45, 50]
    static let breakChoices = [5, 10, 15]
    private static let focusKey = "focusMinutes"
    private static let breakKey = "focusBreakMinutes"

    @Published private(set) var session: FocusSession?
    /// Rounds of focus finished since the app started.
    @Published private(set) var rounds = 0

    @Published var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: FocusTimer.focusKey) }
    }

    @Published var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: FocusTimer.breakKey) }
    }

    /// A round or a break ran out (set by the app: it chimes and opens the notch).
    var onFinished: ((FocusSession) -> Void)?

    private let defaults: UserDefaults
    private var alarm: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let focus = defaults.integer(forKey: FocusTimer.focusKey)
        let rest = defaults.integer(forKey: FocusTimer.breakKey)
        focusMinutes = FocusTimer.focusChoices.contains(focus) ? focus : 25
        breakMinutes = FocusTimer.breakChoices.contains(rest) ? rest : 5
    }

    /// Starts a round of focus. `minutes` is for a planned stretch of homework; otherwise
    /// it's your usual length.
    func start(title: String = "", taskID: UUID? = nil, minutes: Int? = nil, now: Date = Date()) {
        let length = TimeInterval(max(1, min(minutes ?? focusMinutes, 180)) * 60)
        begin(FocusSession(phase: .focus, title: title, taskID: taskID, length: length, ends: now.addingTimeInterval(length)), now: now)
    }

    func startBreak(now: Date = Date()) {
        let length = TimeInterval(breakMinutes * 60)
        begin(FocusSession(phase: .rest, title: "", taskID: nil, length: length, ends: now.addingTimeInterval(length)), now: now)
    }

    func pause(now: Date = Date()) {
        guard var current = session, !current.finished, !current.isPaused else { return }
        current.pausedWith = current.remaining(now: now)
        alarm?.cancel()
        alarm = nil
        session = current
    }

    func resume(now: Date = Date()) {
        guard var current = session, let left = current.pausedWith else { return }
        current.pausedWith = nil
        current.ends = now.addingTimeInterval(left)
        begin(current, now: now)
    }

    /// Stops and clears the timer.
    func stop() {
        alarm?.cancel()
        alarm = nil
        if session != nil {
            session = nil
        }
    }

    /// The time ran out: the session stays, marked finished, until you choose what's next.
    func finish(now: Date = Date()) {
        guard var current = session, !current.finished, !current.isPaused, current.remaining(now: now) <= 0.5 else { return }
        alarm?.cancel()
        alarm = nil
        current.finished = true
        if current.phase == .focus {
            rounds += 1
        }
        session = current
        onFinished?(current)
    }

    private func begin(_ next: FocusSession, now: Date) {
        alarm?.cancel()
        session = next
        let work = DispatchWorkItem { [weak self] in
            self?.finish()
        }
        alarm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, next.ends.timeIntervalSince(now)), execute: work)
    }
}
