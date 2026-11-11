import SwiftUI

/// The planner: homework to do on the left, how it fits into your free time in the middle,
/// and exams to count down to on the right. Click anything to edit it in the side panel.
struct PlannerView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    @ObservedObject var timetable: TimetableStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant
    let expanded: Bool

    init(model: NotchModel, store: PlannerStore, timetable: TimetableStore, settings: AppSettings, assistant: Assistant, expanded: Bool) {
        self.model = model
        self.store = store
        self.timetable = timetable
        self.settings = settings
        self.assistant = assistant
        self.expanded = expanded
    }

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "checklist", title: "Planner") {
                    EmptyView()
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: "graduationcap", label: "Add an exam", action: { model.newExam() })
                    IconButton(symbol: model.plannerShowsDone ? "checkmark.circle.fill" : "checkmark.circle",
                               label: model.plannerShowsDone ? "Hide finished homework" : "Show finished homework",
                               tint: model.plannerShowsDone ? Theme.text : Theme.secondary,
                               action: { model.plannerShowsDone.toggle() })
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make the planner smaller" : "Expand the planner",
                               action: { expanded ? model.back() : model.expandPlanner() })
                    SettingsButton(model: model, section: .planner)
                }
                .padding(.trailing, 4)
            }

            TimelineView(.periodic(from: Date(), by: 60)) { context in
                columns(now: context.date)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func columns(now: Date) -> some View {
        let planner = store.planner
        let table = timetable.timetable
        let sessions = settings.plansStudy
            ? StudyPlanner.plan(tasks: planner.tasks, exams: planner.exams, timetable: table, now: now, daily: settings.studyMinutesADay)
            : []

        return HStack(spacing: 10) {
            PlannerTasks(model: model, store: store, table: table, late: StudyPlanner.late(sessions), now: now,
                         finding: assistant.findsDueDates, engine: assistant.engine)
            if let edit = model.plannerEdit {
                Group {
                    switch edit {
                    case .task(let id):
                        TaskEditor(model: model, store: store, table: table, taskID: id)
                            .id("task-\(id.uuidString)")
                    case .exam(let id):
                        ExamEditor(model: model, store: store, table: table, examID: id)
                            .id("exam-\(id.uuidString)")
                    }
                }
                .frame(width: expanded ? 270 : 250)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if settings.plansStudy {
                PlannerPlan(model: model, table: table, sessions: sessions, now: now)
                    .frame(width: expanded ? 280 : 236)
            }
            PlannerExams(model: model, table: table, exams: planner.upcomingExams(now: now), now: now)
                .frame(width: expanded ? 240 : 206)
        }
        .animation(Theme.spring, value: model.plannerEdit)
    }
}

/// Colours for the planner.
enum PlannerLook {
    /// A subject's or class's colour: its timetable subject's, if it names one.
    static func colour(for subject: String, in table: Timetable) -> Color {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Theme.tertiary }
        let matched = Planner.subject(in: name, among: table.classes) ?? name
        return Theme.subject(table.colour(for: matched))
    }

    /// Red once it's overdue, amber on the day, grey otherwise.
    static func dueColour(_ task: PlannerTask, now: Date) -> Color {
        guard let due = task.due, !task.done else { return Theme.tertiary }
        if task.isOverdue(now: now) { return Theme.danger }
        return DueText.days(until: due, now: now) == 0 ? Theme.warning : Theme.secondary
    }

    /// The symbol for where something came from, and what to say about it.
    static func source(_ source: PlannerSource) -> (symbol: String, text: String)? {
        switch source {
        case .typed: return nil
        case .classroom: return ("studentdesk", "From Google Classroom")
        case .assistant: return ("sparkles", "Added by the assistant")
        case .found: return ("envelope.badge", "Found in an email by the assistant")
        }
    }
}

// MARK: Homework

/// The list of homework, grouped by when it's due, with a box to add more.
struct PlannerTasks: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    let table: Timetable
    /// Homework that won't fit before it's due.
    let late: Set<UUID>
    let now: Date
    let finding: Bool
    let engine: AssistantEngine

    var body: some View {
        let planner = store.planner
        let sections = planner.sections(now: now)
        let finished = model.plannerShowsDone ? Array(planner.finished.prefix(40)) : []

        VStack(alignment: .leading, spacing: 8) {
            QuickAddField(model: model, now: now)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    if sections.isEmpty && finished.isEmpty {
                        PlannerEmpty(hasFinished: !planner.finished.isEmpty)
                    }
                    ForEach(sections, id: \.section) { group in
                        SectionLine(label: "\(group.section.title) · \(group.tasks.count)")
                            .frame(height: 16)
                            .padding(.top, 2)
                        ForEach(group.tasks) { task in
                            row(task)
                        }
                    }
                    if !finished.isEmpty {
                        FinishedHeader(count: planner.finished.count, clear: { store.change { $0.clearDone() } })
                        ForEach(finished) { task in
                            row(task)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            if !finding {
                FindingHint(model: model, engine: engine)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func row(_ task: PlannerTask) -> some View {
        PlannerTaskRow(task: task,
                       colour: PlannerLook.colour(for: task.subject, in: table),
                       due: PlannerLook.dueColour(task, now: now),
                       wontFit: late.contains(task.id),
                       selected: model.plannerEdit == .task(task.id),
                       now: now,
                       toggle: { store.change { $0.setDone(task.id, !task.done) } },
                       edit: { model.editTask(task.id) })
            .contextMenu { TaskMenu(model: model, store: store, task: task) }
    }
}

/// "Finished · 12" with a button to clear them away.
struct FinishedHeader: View {
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SectionLine(label: "Finished · \(count)")
            Button(action: clear) {
                Text("Clear")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 16)
                    .background(Capsule().fill(Theme.raised))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Remove finished homework from the list")
        }
        .frame(height: 16)
        .padding(.top, 6)
    }
}

/// Shown when there's nothing to do.
struct PlannerEmpty: View {
    let hasFinished: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hasFinished ? "All done" : "Nothing to do yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text("Type homework above, like \"Maths worksheet fri 4pm 45m\", or ask the assistant to add it. Google Classroom emails add their assignments by themselves.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
    }
}

/// A slim line offering to find due dates in other emails, until it's turned on.
struct FindingHint: View {
    @ObservedObject var model: NotchModel
    let engine: AssistantEngine

    var body: some View {
        Button(action: { model.openSettings(.planner) }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("\(engine.name) can find due dates in your other emails. It's off: set it up")
                    .font(.system(size: 11))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(Theme.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(engine.isClaude ? "Off by default, because Claude would be sent those emails. Turn it on in Settings → Planner."
                              : "Turn it on in Settings → Planner. Qwen reads them on this Mac.")
    }
}

/// The box at the top of the list: type homework in one line and press Return.
struct QuickAddField: View {
    @ObservedObject var model: NotchModel
    let now: Date
    @State private var typed = ""
    @FocusState private var typing: Bool

    init(model: NotchModel, now: Date) {
        self.model = model
        self.now = now
    }

    var body: some View {
        let entry = QuickEntry.parse(typed, now: now)
        let understood = QuickAddField.understood(entry)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                TextField("Add homework: Maths worksheet fri 4pm 45m", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                    .onSubmit(add)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
            if !understood.isEmpty {
                Text(understood)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 10)
            }
        }
    }

    private func add() {
        if model.addTask(typed: typed, now: Date()) {
            typed = ""
        }
        typing = true
    }

    /// How a typed line will be read: "Due Fri 13 Nov, 4 pm · 45 min".
    static func understood(_ entry: QuickEntry.Parsed) -> String {
        var parts: [String] = []
        if let due = entry.due {
            parts.append("Due " + DueText.full(due, hasTime: entry.hasTime))
        }
        if let minutes = entry.minutes {
            parts.append(DueText.length(minutes))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ") + " · press Return to add"
    }
}

/// One piece of homework: tick it off on the left, click the rest to edit it.
struct PlannerTaskRow: View {
    let task: PlannerTask
    let colour: Color
    let due: Color
    let wontFit: Bool
    let selected: Bool
    let now: Date
    let toggle: () -> Void
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(task.done ? Theme.tertiary : Theme.secondary)
                    .frame(width: 22, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.done ? "Put it back on the list" : "Tick it off")

            Button(action: edit) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(task.done ? Theme.tertiary.opacity(0.5) : colour)
                        .frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .strikethrough(task.done, color: Theme.tertiary)
                            .foregroundStyle(task.done ? Theme.tertiary : Theme.text2)
                        TaskDetailLine(task: task)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 6)
                    if wontFit && !task.done {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.warning)
                            .help("There isn't enough free time on your timetable to finish this before it's due")
                    }
                    if let date = task.due {
                        Text(DueText.label(for: date, hasTime: task.hasTime, now: now))
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(due)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.trailing, 8)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Theme.raised : (hovering ? Theme.hover.opacity(0.6) : Color.clear)))
        .onHover { hovering = $0 }
    }
}

/// "Maths · 45 min", with a mark for where it came from.
struct TaskDetailLine: View {
    let task: PlannerTask

    var body: some View {
        HStack(spacing: 5) {
            if let source = PlannerLook.source(task.source) {
                Image(systemName: source.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .help(source.text)
            }
            Text(TaskDetailLine.text(task))
                .font(.system(size: 11))
        }
        .foregroundStyle(Theme.tertiary)
    }

    static func text(_ task: PlannerTask) -> String {
        let subject = task.subject.trimmingCharacters(in: .whitespaces)
        return [subject, DueText.length(task.minutes)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Right-click homework.
struct TaskMenu: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    let task: PlannerTask

    var body: some View {
        Button(task.done ? "Put Back on the List" : "Tick Off") { store.change { $0.setDone(task.id, !task.done) } }
        Button("Edit") { model.editTask(task.id) }
        if model.hasEmail(task.emailID), let email = task.emailID {
            Button("Open Its Email") { model.openEmail(email) }
        }
        if let link = task.link {
            Button(link.host == "classroom.google.com" ? "Open in Classroom" : "Open in Gmail") { model.onOpenURL?(link) }
        }
        Divider()
        Button("Make It an Exam") {
            var made: UUID?
            store.change { made = $0.makeExam(from: task.id) }
            if let id = made { model.plannerEdit = .exam(id) }
        }
        Button("Delete") {
            if model.plannerEdit == .task(task.id) { model.plannerEdit = nil }
            store.change { $0.removeTask(task.id) }
        }
    }
}

// MARK: The plan

/// When to do it: homework and revision fitted into the free time on your timetable.
struct PlannerPlan: View {
    @ObservedObject var model: NotchModel
    let table: Timetable
    let sessions: [StudySession]
    let now: Date

    var body: some View {
        let days = StudyPlanner.byDay(sessions)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text("Plan")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.text)
            .help("Homework and revision fitted into the free time on your timetable: soonest due first")

            if days.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing to plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Homework with a due date is fitted into your free time after school, soonest first.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(days, id: \.day) { day in
                            SectionLine(label: PlannerPlan.heading(day.day, minutes: day.sessions.reduce(0) { $0 + $1.minutes }, now: now))
                                .frame(height: 16)
                                .padding(.top, 2)
                            ForEach(day.sessions) { session in
                                PlanRow(session: session, colour: PlannerLook.colour(for: session.subject, in: table), open: { open(session) })
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func open(_ session: StudySession) {
        if let id = session.taskID {
            model.editTask(id)
        } else if let id = session.examID {
            model.editExam(id)
        }
    }

    /// "Today · 1 h 30", "Tomorrow · 45 min", "Fri 13 Nov · 2 h".
    static func heading(_ day: Date, minutes: Int, now: Date) -> String {
        let days = DueText.days(until: day, now: now)
        let name = days == 0 ? "Today" : (days == 1 ? "Tomorrow" : DueText.full(day, hasTime: false))
        return "\(name) · \(DueText.length(minutes))"
    }
}

/// "4:00 pm  Maths worksheet  45 min".
struct PlanRow: View {
    let session: StudySession
    let colour: Color
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colour)
                    .frame(width: 3, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    HStack(spacing: 4) {
                        Text("\(DueText.time(session.start)) · \(DueText.length(session.minutes))")
                        if session.late {
                            Text("· after it's due")
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.hover.opacity(0.6) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovering && AppSettings.shared.showsFocus {
                IconButton(symbol: "timer", label: "Start the focus timer for this (\(DueText.length(session.minutes)))", size: 24, tint: Theme.text2,
                           action: { FocusTimer.shared.start(title: session.title, taskID: session.taskID, minutes: session.minutes) })
                    .padding(.trailing, 4)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: Exams

/// Exams coming up, each with its countdown.
struct PlannerExams: View {
    @ObservedObject var model: NotchModel
    let table: Timetable
    let exams: [Exam]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap")
                    .font(.system(size: 11, weight: .semibold))
                Text("Exams")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                IconButton(symbol: "plus", label: "Add an exam", size: 22, action: { model.newExam() })
            }
            .foregroundStyle(Theme.text)

            if exams.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No exams coming up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Add one to count down to it and plan revision for the days before.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 6) {
                        ForEach(exams) { exam in
                            ExamCard(exam: exam, colour: PlannerLook.colour(for: exam.subject, in: table),
                                     selected: model.plannerEdit == .exam(exam.id), now: now,
                                     edit: { model.editExam(exam.id) })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// An exam: how many days to go, then what and when.
struct ExamCard: View {
    let exam: Exam
    let colour: Color
    let selected: Bool
    let now: Date
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        let days = DueText.days(until: exam.date, now: now)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        Button(action: edit) {
            HStack(spacing: 9) {
                VStack(spacing: -1) {
                    Text(days == 0 ? "Now" : "\(days)")
                        .font(.system(size: days == 0 ? 13 : 19, weight: .bold).monospacedDigit())
                        .foregroundStyle(days <= 2 ? Theme.warning : Theme.text)
                    Text(days == 0 ? "today" : (days == 1 ? "day" : "days"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(width: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(exam.title.isEmpty ? "New exam" : exam.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text(ExamCard.detail(exam))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(shape.fill(colour.opacity(selected || hovering ? 0.22 : 0.13)))
            .overlay(shape.strokeBorder(selected ? Theme.text : Color.clear, lineWidth: 1.2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(exam.title.isEmpty ? "This exam" : exam.name) is \(DueText.countdown(to: exam.date, now: now)). Click to edit it.")
    }

    /// "Fri 20 Nov, 9 am · Hall".
    static func detail(_ exam: Exam) -> String {
        [DueText.full(exam.date, hasTime: exam.hasTime), exam.place.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: Editing

/// A date you type: "fri 4pm", "20 Nov", "tomorrow". What it's read as shows underneath.
struct DueDateField: View {
    let label: String
    let date: Date?
    let hasTime: Bool
    /// Whether leaving it empty is allowed (no due date).
    let allowsNone: Bool
    let change: (Date?, Bool) -> Void
    @State private var text = ""
    @State private var loaded = false

    init(label: String, date: Date?, hasTime: Bool, allowsNone: Bool, change: @escaping (Date?, Bool) -> Void) {
        self.label = label
        self.date = date
        self.hasTime = hasTime
        self.allowsNone = allowsNone
        self.change = change
    }

    var body: some View {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let read = DueDateParser.parse(typed, relativeTo: Date())

        VStack(alignment: .leading, spacing: 3) {
            EditorField(label: label) {
                TextField(allowsNone ? "fri 4pm, 20 Nov, tomorrow… or empty" : "fri 9am, 20 Nov…", text: $text)
                    .onChange(of: text) { _ in save() }
            }
            if let read = read {
                Text(DueText.full(read.date, hasTime: read.hasTime) + " · " + DueText.countdown(to: read.date, now: Date()))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            } else if !typed.isEmpty || !allowsNone {
                Text(typed.isEmpty ? "Type a date, like 20 Nov 9am." : "Can't read that as a date. Try 20 Nov 4pm.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
            }
        }
        .onAppear {
            text = date.map { DueText.editable($0, hasTime: hasTime) } ?? ""
            DispatchQueue.main.async { loaded = true }
        }
    }

    /// Saves as you type, once it reads as a date (or is emptied, where that's allowed).
    private func save() {
        guard loaded else { return }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            if allowsNone { change(nil, false) }
        } else if let read = DueDateParser.parse(typed, relativeTo: Date()) {
            change(read.date, read.hasTime)
        }
    }
}

/// "Takes  [−] 45 min [+]".
struct MinutesRow: View {
    let title: String
    let detail: String
    let minutes: Int
    let step: Int
    let range: ClosedRange<Int>
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                IconButton(symbol: "minus", label: "Less", size: 24, tint: minutes > range.lowerBound ? Theme.text2 : Theme.tertiary.opacity(0.5),
                           action: { change(MinutesRow.stepped(minutes, by: step, up: false, in: range)) })
                Text(minutes == 0 ? "None" : DueText.length(minutes))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 46)
                IconButton(symbol: "plus", label: "More", size: 24, tint: minutes < range.upperBound ? Theme.text2 : Theme.tertiary.opacity(0.5),
                           action: { change(MinutesRow.stepped(minutes, by: step, up: true, in: range)) })
            }
            .padding(.horizontal, 2)
            .background(Capsule().fill(Theme.raised))
            .fixedSize()
        }
    }
}

extension MinutesRow {
    /// The next round amount up or down: 20 goes to 30 or 15 in steps of 15.
    static func stepped(_ minutes: Int, by step: Int, up: Bool, in range: ClosedRange<Int>) -> Int {
        let next = up ? (minutes / step + 1) * step : ((minutes - 1) / step) * step
        return max(range.lowerBound, min(range.upperBound, next))
    }
}

/// Subjects from your timetable to pick from.
struct SubjectChips: View {
    let table: Timetable
    let typed: String
    let pick: (String) -> Void

    var body: some View {
        let current = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = table.classes.filter { name in
            let lower = name.lowercased()
            return lower != current && (current.isEmpty || lower.hasPrefix(current))
        }

        if !names.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(names.prefix(10), id: \.self) { name in
                        Button(action: { pick(name) }) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Theme.subject(table.colour(for: name)))
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.text2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Theme.raised))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// The side panel for one piece of homework.
struct TaskEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    let table: Timetable
    let taskID: UUID
    @FocusState private var typingTitle: Bool

    init(model: NotchModel, store: PlannerStore, table: Timetable, taskID: UUID) {
        self.model = model
        self.store = store
        self.table = table
        self.taskID = taskID
    }

    var body: some View {
        let task = store.planner.task(taskID)

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: "Homework",
                         detail: task.flatMap { PlannerLook.source($0.source)?.text } ?? "You added this",
                         close: { model.closePlannerEdit() })
            if let task = task {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) {
                        EditorField(label: "What") {
                            TextField("e.g. Maths worksheet", text: binding(\.title))
                                .focused($typingTitle)
                        }
                        EditorField(label: "Subject") {
                            TextField("e.g. Maths", text: binding(\.subject))
                        }
                        SubjectChips(table: table, typed: task.subject, pick: { name in change { $0.subject = name } })
                        DueDateField(label: "Due", date: task.due, hasTime: task.hasTime, allowsNone: true, change: { date, hasTime in
                            change { task in
                                task.due = date
                                task.hasTime = hasTime
                            }
                        })
                        MinutesRow(title: "Takes", detail: "For fitting it into your week", minutes: task.minutes, step: 15, range: 15...600,
                                   change: { minutes in change { $0.minutes = minutes } })
                        EditorField(label: "Notes") {
                            TextField("Anything to remember", text: binding(\.notes))
                        }
                        TaskLinks(model: model, store: store, task: task)
                    }
                }
                .scrollIndicators(.never)
                HStack(spacing: 8) {
                    PillButton(title: "Delete", action: {
                        model.closePlannerEdit()
                        store.change { $0.removeTask(taskID) }
                    })
                    Spacer(minLength: 0)
                    PillButton(title: task.done ? "Not Done" : "Tick Off", action: { store.change { $0.setDone(taskID, !task.done) } })
                    PillButton(title: "Done", prominent: true, action: { model.closePlannerEdit() })
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear {
            if task?.title.isEmpty == true { typingTitle = true }
        }
    }

    private func change(_ edit: (inout PlannerTask) -> Void) {
        guard var task = store.planner.task(taskID) else { return }
        edit(&task)
        store.change { $0.update(task) }
    }

    /// Edits one part of the homework, saving as you type.
    private func binding(_ part: WritableKeyPath<PlannerTask, String>) -> Binding<String> {
        Binding(
            get: { store.planner.task(taskID)?[keyPath: part] ?? "" },
            set: { typed in change { $0[keyPath: part] = typed } }
        )
    }
}

/// Where homework came from: its email, its page in Classroom, and making it an exam.
struct TaskLinks: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    let task: PlannerTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model.hasEmail(task.emailID), let email = task.emailID {
                    SmallPill(title: "Open Email", symbol: "envelope", action: { model.openEmail(email) })
                }
                if let link = task.link {
                    SmallPill(title: link.host == "classroom.google.com" ? "Classroom" : "Gmail", symbol: "arrow.up.right",
                              action: { model.onOpenURL?(link) })
                }
            }
            SmallPill(title: "It's an Exam", symbol: "graduationcap", action: {
                var made: UUID?
                store.change { made = $0.makeExam(from: task.id) }
                if let id = made { model.plannerEdit = .exam(id) }
            })
            .help("Moves it to Exams, to count down to it and plan revision")
        }
    }
}

/// A small grey button with a symbol.
struct SmallPill: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(hovering ? Theme.hover : Theme.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The side panel for an exam.
struct ExamEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    let table: Timetable
    let examID: UUID
    @FocusState private var typingTitle: Bool

    init(model: NotchModel, store: PlannerStore, table: Timetable, examID: UUID) {
        self.model = model
        self.store = store
        self.table = table
        self.examID = examID
    }

    var body: some View {
        let exam = store.planner.exam(examID)

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: "Exam",
                         detail: exam.flatMap { PlannerLook.source($0.source)?.text } ?? "Counts down on the primary menu",
                         close: { model.closePlannerEdit() })
            if let exam = exam {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) {
                        EditorField(label: "What") {
                            TextField("e.g. Yearly exam", text: binding(\.title))
                                .focused($typingTitle)
                        }
                        EditorField(label: "Subject") {
                            TextField("e.g. Science", text: binding(\.subject))
                        }
                        SubjectChips(table: table, typed: exam.subject, pick: { name in change { $0.subject = name } })
                        DueDateField(label: "When", date: exam.date, hasTime: exam.hasTime, allowsNone: false, change: { date, hasTime in
                            guard let date = date else { return }
                            change { exam in
                                exam.date = date
                                exam.hasTime = hasTime
                            }
                        })
                        EditorField(label: "Where") {
                            TextField("e.g. Hall", text: binding(\.place))
                        }
                        MinutesRow(title: "Revision", detail: "Planned for the days before", minutes: exam.studyMinutes, step: 30, range: 0...1200,
                                   change: { minutes in change { $0.studyMinutes = minutes } })
                        EditorField(label: "Notes") {
                            TextField("Topics, what to bring", text: binding(\.notes))
                        }
                        if model.hasEmail(exam.emailID), let email = exam.emailID {
                            SmallPill(title: "Open Email", symbol: "envelope", action: { model.openEmail(email) })
                        }
                    }
                }
                .scrollIndicators(.never)
                HStack(spacing: 8) {
                    PillButton(title: "Delete", action: {
                        model.closePlannerEdit()
                        store.change { $0.removeExam(examID) }
                    })
                    Spacer(minLength: 0)
                    PillButton(title: "Done", prominent: true, action: { model.closePlannerEdit() })
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear {
            if exam?.title.isEmpty == true { typingTitle = true }
        }
    }

    private func change(_ edit: (inout Exam) -> Void) {
        guard var exam = store.planner.exam(examID) else { return }
        edit(&exam)
        store.change { $0.update(exam) }
    }

    private func binding(_ part: WritableKeyPath<Exam, String>) -> Binding<String> {
        Binding(
            get: { store.planner.exam(examID)?[keyPath: part] ?? "" },
            set: { typed in change { $0[keyPath: part] = typed } }
        )
    }
}

// MARK: On the primary menu

/// What's due next and the next exam.
struct PlannerToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    @ObservedObject var timetable: TimetableStore
    @State var hovering = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date
            let planner = store.planner
            let table = timetable.timetable
            let open = planner.open(now: now)
            let overdue = open.filter { $0.isOverdue(now: now) }.count
            let exam = planner.upcomingExams(now: now).first

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ToolIcon(symbol: "checklist")
                    Text("Planner")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !open.isEmpty {
                        Text("\(open.count)")
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(overdue > 0 ? Theme.danger : Theme.text)
                            .help(overdue > 0 ? "\(open.count) to do, \(overdue) overdue" : "\(open.count) to do")
                    }
                }
                Spacer(minLength: 0)
                if open.isEmpty && exam == nil {
                    Text("Nothing due")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Click to add homework or an exam")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                } else {
                    ForEach(open.prefix(exam == nil ? 2 : 1)) { task in
                        ClassLine(label: task.isOverdue(now: now) ? "Overdue" : "Due",
                                  colour: PlannerLook.colour(for: task.subject, in: table),
                                  subject: task.title,
                                  detail: task.due.map { DueText.label(for: $0, hasTime: task.hasTime, now: now) } ?? "No due date")
                    }
                    if let exam = exam {
                        ClassLine(label: "Exam", colour: PlannerLook.colour(for: exam.subject, in: table), subject: exam.name,
                                  detail: PlannerToolTile.countdown(exam, now: now))
                    }
                }
            }
            .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { model.openPlanner() }
        .onHover { hovering = $0 }
        .help("Open the planner")
    }

    /// "in 6 days · Fri 20 Nov".
    static func countdown(_ exam: Exam, now: Date) -> String {
        "\(DueText.countdown(to: exam.date, now: now)) · \(DueText.full(exam.date, hasTime: exam.hasTime))"
    }
}

/// The next exam, counting down beside the date at the top of the primary menu.
struct ExamCountdownChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: PlannerStore
    /// Exams further off than this aren't shown yet.
    static let horizon = 21

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date
            if let exam = store.planner.upcomingExams(now: now).first, DueText.days(until: exam.date, now: now) <= ExamCountdownChip.horizon {
                let days = DueText.days(until: exam.date, now: now)
                Button(action: { model.editExam(exam.id) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("\(exam.name) \(DueText.countdown(to: exam.date, now: now))")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(days <= 2 ? Theme.warning : Theme.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.raised))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(DueText.full(exam.date, hasTime: exam.hasTime) + (exam.place.isEmpty ? "" : " · \(exam.place)"))
            }
        }
    }
}
