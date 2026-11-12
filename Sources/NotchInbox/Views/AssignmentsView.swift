import SwiftUI

/// Assignments: what's to hand in, broken into steps, on one side; the marks that came
/// back, and what you need for your goal in each subject, on the other.
struct AssignmentsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    @ObservedObject var planner: PlannerStore
    @ObservedObject var timetable: TimetableStore
    @ObservedObject var assistant: Assistant
    let expanded: Bool

    init(model: NotchModel, store: AssignmentsStore, planner: PlannerStore, timetable: TimetableStore, assistant: Assistant, expanded: Bool) {
        self.model = model
        self.store = store
        self.planner = planner
        self.timetable = timetable
        self.assistant = assistant
        self.expanded = expanded
    }

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)
        let marks = model.assignmentsTab == .marks

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "list.bullet.clipboard", title: "Assignments") {
                    ChoiceSegments(options: [
                        ChoiceSegments<NotchModel.AssignmentsTab>.Option(value: .work, title: "To Do", help: "Assignments to hand in, and their steps"),
                        ChoiceSegments<NotchModel.AssignmentsTab>.Option(value: .marks, title: "Marks", help: "Your results, and what you need for your goals"),
                    ], selected: model.assignmentsTab, choose: { tab in
                        model.assignmentOpen = nil
                        model.assignmentsTab = tab
                    })
                    .padding(.leading, 8)
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: "plus", label: marks ? "Add a result" : "New assignment",
                               action: { marks ? model.newResult(subject: model.marksSubject ?? "") : model.newAssignment() })
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make this smaller" : "Expand",
                               action: { expanded ? model.back() : model.expandAssignments() })
                    SettingsButton(model: model)
                }
                .padding(.trailing, 4)
            }

            TimelineView(.periodic(from: Date(), by: 60)) { context in
                HStack(spacing: 10) {
                    if marks {
                        MarksBoard(model: model, store: store, planner: planner, table: timetable.timetable, now: context.date, expanded: expanded)
                    } else {
                        AssignmentList(model: model, store: store, table: timetable.timetable, now: context.date)
                    }
                    if let id = model.assignmentOpen, store.assignments.item(id) != nil {
                        AssignmentEditor(model: model, store: store, assistant: assistant, table: timetable.timetable, itemID: id)
                            .id(id)
                            .frame(width: expanded ? 360 : 320)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(Theme.spring, value: model.assignmentOpen)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// Words and colours for assignments.
enum AssignmentLook {
    /// "Due Fri 4 pm", "Overdue: was due Mon", "No due date".
    static func due(_ item: Assignment, now: Date) -> String {
        guard let due = item.due else { return "No due date" }
        return DueText.label(for: due, hasTime: item.hasTime, now: now)
    }

    static func dueColour(_ item: Assignment, now: Date) -> Color {
        guard let due = item.due, item.isOpen else { return Theme.tertiary }
        if item.isOverdue(now: now) { return Theme.danger }
        return DueText.days(until: due, now: now) == 0 ? Theme.warning : Theme.secondary
    }

    /// "2 of 5 steps · 1 h 30 min left", or what to do when there are none.
    static func progress(_ item: Assignment) -> String {
        guard !item.steps.isEmpty else { return "Not broken into steps yet" }
        if item.stepsDone == item.steps.count { return "Every step done" }
        return "\(item.stepsDone) of \(item.steps.count) steps · \(DueText.length(item.minutesLeft)) left"
    }

    /// Green at or above the goal, amber a little under, red well under; plain without a goal.
    static func markColour(_ percent: Double, goal: Double?) -> Color {
        guard let goal = goal else { return Theme.text }
        if percent >= goal { return Theme.good }
        return percent >= goal - 10 ? Theme.warning : Theme.danger
    }
}

// MARK: To do

/// The assignments still to hand in, soonest first, then the ones waiting for a mark.
struct AssignmentList: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    let table: Timetable
    let now: Date

    var body: some View {
        let open = store.assignments.open
        let awaiting = store.assignments.awaiting

        VStack(alignment: .leading, spacing: 8) {
            if open.isEmpty && awaiting.isEmpty {
                AssignmentsEmpty(model: model)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !open.isEmpty {
                            AssignmentHeading(title: "To hand in", count: open.count)
                            ForEach(open) { item in
                                AssignmentRow(model: model, store: store, item: item, table: table, now: now)
                            }
                        }
                        if !awaiting.isEmpty {
                            AssignmentHeading(title: "Handed in, waiting for a mark", count: awaiting.count)
                                .padding(.top, open.isEmpty ? 0 : 8)
                            ForEach(awaiting) { item in
                                AssignmentRow(model: model, store: store, item: item, table: table, now: now)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

struct AssignmentHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.tertiary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct AssignmentsEmpty: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text("No assignments to hand in")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text("Add one, paste in its task sheet, and have it broken into steps that the planner fits into your week.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            PillButton(title: "New Assignment", prominent: true, action: { model.newAssignment() })
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One assignment in the list: what it is, when it's due, how far through it you are.
struct AssignmentRow: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    let item: Assignment
    let table: Timetable
    let now: Date
    @State var hovering = false

    var body: some View {
        let selected = model.assignmentOpen == item.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button(action: { model.showAssignment(item.id, toggle: true) }) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(PlannerLook.colour(for: item.subject, in: table))
                    .frame(width: 3, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title.isEmpty ? "New assignment" : item.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if item.weight > 0 {
                            WeightChip(weight: item.weight)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(item.handedIn ? "Handed in" : AssignmentLook.due(item, now: now))
                            .foregroundStyle(item.handedIn ? Theme.good : AssignmentLook.dueColour(item, now: now))
                        Text("·")
                            .foregroundStyle(Theme.tertiary)
                        Text(item.handedIn ? "Add the mark when it comes back" : AssignmentLook.progress(item))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if !item.handedIn && !item.steps.isEmpty {
                    ProgressRing(progress: item.progress)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10))
            .background(shape.fill(selected ? Theme.raised : (hovering ? Theme.hover : Theme.lane)))
            .overlay(shape.strokeBorder(Color.white.opacity(selected ? 0.18 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { model.showAssignment(item.id) }
            Button(item.handedIn ? "Not Handed In After All" : "Mark as Handed In") {
                store.change { $0.setHandedIn(item.id, !item.handedIn) }
            }
            Divider()
            Button("Delete") {
                if model.assignmentOpen == item.id { model.assignmentOpen = nil }
                store.change { $0.remove(item.id) }
            }
        }
    }
}

/// What something's worth, as a small chip: "20%".
struct WeightChip: View {
    let weight: Double

    var body: some View {
        Text(Marks.text(weight))
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(Theme.raised))
            .help("Worth \(Marks.text(weight)) of the subject's mark")
    }
}

/// How far through something you are, as a ring.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.raised, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(progress >= 1 ? Theme.good : Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("\(Int((progress * 100).rounded())) percent done"))
    }
}

// MARK: The side panel

/// An assignment (or a result) at the side: everything about it, saved as you type.
struct AssignmentEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    @ObservedObject var assistant: Assistant
    let table: Timetable
    let itemID: UUID
    @FocusState private var typingTitle: Bool

    init(model: NotchModel, store: AssignmentsStore, assistant: Assistant, table: Timetable, itemID: UUID) {
        self.model = model
        self.store = store
        self.assistant = assistant
        self.table = table
        self.itemID = itemID
    }

    var body: some View {
        let item = store.assignments.item(itemID)
        let isResult = item?.kind == .result

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: isResult ? "Result" : "Assignment",
                         detail: isResult ? "A mark to keep: a test or an exam" : "Saved as you type",
                         close: { model.assignmentOpen = nil })
            if let item = item {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) {
                        EditorField(label: "What") {
                            TextField(isResult ? "e.g. Half-yearly exam" : "e.g. Essay on Macbeth", text: binding(\.title))
                                .focused($typingTitle)
                        }
                        EditorField(label: "Subject") {
                            TextField("e.g. English", text: binding(\.subject))
                        }
                        SubjectChips(table: table, typed: item.subject, pick: { name in change { $0.subject = name } })
                        DueDateField(label: isResult ? "When it was" : "Due", date: item.due, hasTime: item.hasTime, allowsNone: true,
                                     change: { date, hasTime in
                                         change { item in
                                             item.due = date
                                             item.hasTime = hasTime
                                         }
                                     })
                        WeightField(weight: item.weight, change: { weight in change { $0.weight = weight } })
                        if !isResult {
                            AssignmentSteps(model: model, store: store, assistant: assistant, item: item)
                            AssignmentBrief(text: binding(\.brief))
                        }
                        if isResult || item.handedIn || item.isMarked {
                            MarkField(mark: item.mark, outOf: item.outOf, change: { mark, outOf in
                                store.change { $0.setMark(itemID, mark: mark, outOf: outOf) }
                            })
                        }
                        EditorField(label: "Notes") {
                            TextField("Anything to remember", text: binding(\.notes))
                        }
                    }
                }
                .scrollIndicators(.never)
                HStack(spacing: 8) {
                    PillButton(title: "Delete", action: {
                        model.assignmentOpen = nil
                        store.change { $0.remove(itemID) }
                    })
                    Spacer(minLength: 0)
                    if !isResult {
                        PillButton(title: item.handedIn ? "Not Handed In" : "Handed In",
                                   action: { store.change { $0.setHandedIn(itemID, !item.handedIn) } })
                    }
                    PillButton(title: "Done", prominent: true, action: { model.assignmentOpen = nil })
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear {
            if item?.title.isEmpty == true { typingTitle = true }
        }
    }

    private func change(_ edit: (inout Assignment) -> Void) {
        store.change { $0.change(itemID, edit) }
    }

    /// Edits one part of the assignment, saving as you type.
    private func binding(_ part: WritableKeyPath<Assignment, String>) -> Binding<String> {
        Binding(
            get: { store.assignments.item(itemID)?[keyPath: part] ?? "" },
            set: { typed in change { $0[keyPath: part] = typed } }
        )
    }
}

/// What it's worth toward the subject's mark.
struct WeightField: View {
    let weight: Double
    let change: (Double) -> Void
    @State private var text: String

    init(weight: Double, change: @escaping (Double) -> Void) {
        self.weight = weight
        self.change = change
        _text = State(initialValue: weight > 0 ? Marks.number(weight) : "")
    }

    var body: some View {
        let read = Marks.parseWeight(text)

        VStack(alignment: .leading, spacing: 3) {
            EditorField(label: "Worth (% of the subject's mark)") {
                TextField("e.g. 20, or leave empty", text: $text)
                    .onChange(of: text) { typed in
                        if let value = Marks.parseWeight(typed) {
                            change(value)
                        }
                    }
            }
            if read == nil {
                Text("A number from 0 to 100, like 20.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}

/// The mark that came back: "17/20" or "85%".
struct MarkField: View {
    let mark: Double?
    let outOf: Double?
    let change: (Double?, Double?) -> Void
    @State private var text: String

    init(mark: Double?, outOf: Double?, change: @escaping (Double?, Double?) -> Void) {
        self.mark = mark
        self.outOf = outOf
        self.change = change
        var shown = ""
        if let mark = mark, let outOf = outOf {
            shown = Marks.markText(mark, outOf: outOf)
        }
        _text = State(initialValue: shown)
    }

    var body: some View {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let read = Marks.parse(typed)

        VStack(alignment: .leading, spacing: 3) {
            EditorField(label: "Mark") {
                TextField("17/20 or 85%", text: $text)
                    .onChange(of: text) { now in
                        let entry = now.trimmingCharacters(in: .whitespacesAndNewlines)
                        if entry.isEmpty {
                            change(nil, nil)
                        } else if let found = Marks.parse(entry) {
                            change(found.mark, found.outOf)
                        }
                    }
            }
            if let read = read {
                Text(Marks.text(read.mark / read.outOf * 100))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            } else if !typed.isEmpty {
                Text("Type it like 17/20 or 85%.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}

/// What the task asks for, pasted from the task sheet: the assistant plans from it.
struct AssignmentBrief: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("What the task asks")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste the task sheet here. The steps are planned from it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .padding(EdgeInsets(top: 7, leading: 9, bottom: 0, trailing: 9))
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(EdgeInsets(top: 5, leading: 4, bottom: 5, trailing: 4))
            }
            .frame(height: 84)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        }
    }
}

/// An assignment's steps: tick them off, change them, add your own, or have them planned.
struct AssignmentSteps: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    @ObservedObject var assistant: Assistant
    let item: Assignment
    @State private var adding = ""

    init(model: NotchModel, store: AssignmentsStore, assistant: Assistant, item: Assignment) {
        self.model = model
        self.store = store
        self.assistant = assistant
        self.item = item
    }

    var body: some View {
        let planning = model.planningAssignment == item.id
        let hasPlan = item.steps.contains(where: { !$0.done })

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Steps")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                if !item.steps.isEmpty {
                    Text("\(item.stepsDone)/\(item.steps.count) · \(DueText.length(item.minutesLeft)) left")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if planning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Planning…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                } else {
                    SmallPill(title: hasPlan ? "Plan Again" : "Break into Steps", symbol: "sparkles",
                              action: { model.planAssignment(item.id) })
                        .help(planHelp)
                }
            }
            if let note = model.planningNote, !planning {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(item.steps) { step in
                AssignmentStepRow(store: store, step: step, isFirst: step.id == item.steps.first?.id, isLast: step.id == item.steps.last?.id)
            }
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                TextField("Add a step of your own", text: $adding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .onSubmit {
                        store.change { $0.addStep(adding, to: item.id) }
                        adding = ""
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
            Text(item.due == nil ? "Give it a due date and the planner fits the steps into your free time."
                 : "The planner fits the steps still to do into your free time before it's due.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Who plans it, and what leaves the Mac to do so.
    private var planHelp: String {
        guard assistant.status.isReady else {
            return "\(assistant.engine.name) isn't set up, so this puts in the usual steps for this kind of work."
        }
        return assistant.engine.isClaude
            ? "Claude plans the steps. This assignment's name, subject, due date and task sheet are sent to Anthropic."
            : "Qwen plans the steps, on this Mac."
    }
}

/// One step: tick it off, rename it, give it more or less time, move it or remove it.
struct AssignmentStepRow: View {
    @ObservedObject var store: AssignmentsStore
    let step: AssignmentStep
    let isFirst: Bool
    let isLast: Bool
    @State var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { store.change { $0.setStep(step.id, done: !step.done) } }) {
                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(step.done ? Theme.good : Theme.tertiary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(step.done ? "Not done after all" : "Tick this step off")

            TextField("Step", text: Binding(
                get: { step.title },
                set: { typed in rename(typed) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(step.done ? Theme.tertiary : Theme.text)
            .strikethrough(step.done, color: Theme.tertiary)

            if hovering {
                IconButton(symbol: "chevron.up", label: "Move this step earlier", size: 18, action: { store.change { $0.moveStep(step.id, by: -1) } })
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)
                IconButton(symbol: "chevron.down", label: "Move this step later", size: 18, action: { store.change { $0.moveStep(step.id, by: 1) } })
                    .disabled(isLast)
                    .opacity(isLast ? 0.3 : 1)
                IconButton(symbol: "xmark", label: "Remove this step", size: 18, action: { store.change { $0.removeStep(step.id) } })
            }
            StepMinutes(minutes: step.minutes, change: { minutes in retime(minutes) })
        }
        .padding(.leading, 4)
        .padding(.trailing, 3)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : Theme.lane))
        .onHover { hovering = $0 }
    }

    private func rename(_ title: String) {
        store.change { all in
            guard let owner = all.owner(of: step.id) else { return }
            all.change(owner.id) { item in
                if let index = item.steps.firstIndex(where: { $0.id == step.id }) {
                    item.steps[index].title = title
                }
            }
        }
    }

    private func retime(_ minutes: Int) {
        store.change { all in
            guard let owner = all.owner(of: step.id) else { return }
            all.change(owner.id) { item in
                if let index = item.steps.firstIndex(where: { $0.id == step.id }) {
                    item.steps[index].minutes = minutes
                }
            }
        }
    }
}

/// How long a step takes: click for more, option-click (or right-click) for less.
struct StepMinutes: View {
    let minutes: Int
    let change: (Int) -> Void

    var body: some View {
        Menu {
            ForEach([10, 15, 20, 30, 45, 60, 90, 120, 180], id: \.self) { choice in
                Button(DueText.length(choice)) { change(choice) }
            }
        } label: {
            Text(DueText.length(minutes))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Capsule().fill(Theme.raised))
        .help("How long this step takes")
    }
}

// MARK: Marks

/// The marks tracker: your subjects on the left, the one you pick on the right.
struct MarksBoard: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    @ObservedObject var planner: PlannerStore
    let table: Timetable
    let now: Date
    let expanded: Bool

    var body: some View {
        let all = store.assignments
        let subjects = all.subjects
        let summaries = subjects.map { Marks.summary(subject: $0, items: all.items, goal: all.goal(for: $0)) }
        let chosen = MarksBoard.chosen(model.marksSubject, among: subjects)
        let toMark = all.examsToMark(planner.planner.exams, now: now)

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                MarksOverall(average: Marks.overall(summaries), subjects: summaries.filter { $0.average != nil }.count)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summaries, id: \.subject) { summary in
                            MarksSubjectRow(summary: summary, colour: PlannerLook.colour(for: summary.subject, in: table),
                                            selected: chosen.map { Marks.key($0) == Marks.key(summary.subject) } ?? false,
                                            choose: {
                                                model.assignmentOpen = nil
                                                model.marksSubject = summary.subject
                                            })
                        }
                        ForEach(toMark.prefix(3)) { exam in
                            ExamToMark(exam: exam, add: { model.newResult(exam: exam) })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(12)
            .frame(width: expanded ? 260 : 232)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))

            if let subject = chosen, let summary = summaries.first(where: { Marks.key($0.subject) == Marks.key(subject) }) {
                MarksSubject(model: model, store: store, summary: summary, items: all.items(in: subject), now: now)
            } else {
                MarksEmpty(model: model)
            }
        }
    }

    /// The subject to show: the one you picked if it's still there, else the first.
    static func chosen(_ picked: String?, among subjects: [String]) -> String? {
        if let picked = picked, let match = subjects.first(where: { Marks.key($0) == Marks.key(picked) }) {
            return match
        }
        return subjects.first
    }
}

/// Your average across every subject that has a mark.
struct MarksOverall: View {
    let average: Double?
    let subjects: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("OVERALL")
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.tertiary)
            Text(average.map { Marks.text($0) } ?? "No marks yet")
                .font(.system(size: average == nil ? 14 : 24, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
            Text(average == nil ? "Add a result with the + at the top." : "Across \(subjects) subject\(subjects == 1 ? "" : "s"), each counting the same")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, 4)
    }
}

/// A subject in the list: its average, and how many results are behind it.
struct MarksSubjectRow: View {
    let summary: Marks.Summary
    let colour: Color
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        Button(action: choose) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colour)
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary.subject.isEmpty ? "No subject" : summary.subject)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if let average = summary.average {
                    Text(Marks.text(average))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(AssignmentLook.markColour(average, goal: summary.goal))
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 38)
            .background(shape.fill(selected ? Theme.raised : (hovering ? Theme.hover : Color.clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detail: String {
        var parts = [summary.count == 0 ? "No marks yet" : "\(summary.count) result\(summary.count == 1 ? "" : "s")"]
        if let goal = summary.goal {
            parts.append("goal \(Marks.text(goal))")
        }
        return parts.joined(separator: " · ")
    }
}

/// An exam from the planner that's over: add its mark with a click.
struct ExamToMark: View {
    let exam: Exam
    let add: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exam.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Sat it? Add your mark")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.hover : Theme.lane))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct MarksEmpty: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text("No marks yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text("Add each result as it comes back, with what it's worth, to see your average in every subject and what you need for the mark you want.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            PillButton(title: "Add a Result", prominent: true, action: { model.newResult() })
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// One subject: its average, your goal and what it takes to get there, and every result.
struct MarksSubject: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    let summary: Marks.Summary
    let items: [Assignment]
    let now: Date

    var body: some View {
        let marked = items.filter { $0.isMarked }.sorted { ($0.due ?? $0.added) > ($1.due ?? $1.added) }
        let coming = items.filter { !$0.isMarked }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.subject.isEmpty ? "No subject" : summary.subject)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let average = summary.average {
                    Text(Marks.text(average))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(AssignmentLook.markColour(average, goal: summary.goal))
                        .help(summary.weighted ? "Weighted by what each result is worth" : "A plain average: say what each result is worth to weight it")
                }
            }
            MarksGoal(store: store, summary: summary)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 5) {
                    if !marked.isEmpty {
                        AssignmentHeading(title: "Results", count: marked.count)
                        ForEach(marked) { item in
                            ResultRow(model: model, item: item, goal: summary.goal)
                        }
                    }
                    if !coming.isEmpty {
                        AssignmentHeading(title: "Still to come", count: coming.count)
                            .padding(.top, marked.isEmpty ? 0 : 8)
                        ForEach(coming) { item in
                            ResultRow(model: model, item: item, goal: summary.goal)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// The mark you're aiming for, and what you need on what's left to get it.
struct MarksGoal: View {
    @ObservedObject var store: AssignmentsStore
    let summary: Marks.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Goal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text(summary.weighted ? "\(Marks.text(summary.done)) of the mark decided, \(Marks.text(summary.left)) to come"
                         : "Say what each result is worth to see what you need")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    IconButton(symbol: "minus", label: "A lower goal", size: 24, tint: Theme.text2,
                               action: { step(-5) })
                    Text(summary.goal.map { Marks.text($0) } ?? "None")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .frame(minWidth: 46)
                    IconButton(symbol: "plus", label: "A higher goal", size: 24, tint: Theme.text2,
                               action: { step(5) })
                }
                .padding(.horizontal, 2)
                .background(Capsule().fill(Theme.raised))
                .fixedSize()
            }
            if let verdict = Marks.verdict(summary) {
                Text(verdict)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
    }

    /// Goals go in fives from 50% to 100%; below 50 is no goal.
    private func step(_ change: Double) {
        let next: Double?
        if let goal = summary.goal {
            let moved = goal + change
            next = moved < 50 ? nil : min(moved, 100)
        } else {
            next = change > 0 ? MarksGoal.firstGoal(above: summary.average) : nil
        }
        store.change { $0.setGoal(next, for: summary.subject) }
    }

    /// A first goal: the next five above where you are, or 80%.
    static func firstGoal(above average: Double?) -> Double {
        guard let average = average else { return 80 }
        return min(100, max(50, (average / 5).rounded(.down) * 5 + 5))
    }
}

/// One result (or something still to be marked) in a subject.
struct ResultRow: View {
    @ObservedObject var model: NotchModel
    let item: Assignment
    let goal: Double?
    @State var hovering = false

    var body: some View {
        let selected = model.assignmentOpen == item.id
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        Button(action: { open() }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? "New result" : item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if item.weight > 0 {
                    WeightChip(weight: item.weight)
                }
                if let percent = item.percent, let mark = item.mark, let outOf = item.outOf {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Marks.text(percent))
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(AssignmentLook.markColour(percent, goal: goal))
                        Text(Marks.markText(mark, outOf: outOf))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 40)
            .background(shape.fill(selected ? Theme.raised : (hovering ? Theme.hover : Theme.lane)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// Results open at the side here; an assignment still to hand in opens in To Do.
    private func open() {
        if item.isOpen {
            model.showAssignment(item.id)
        } else {
            model.assignmentOpen = model.assignmentOpen == item.id ? nil : item.id
        }
    }

    private var detail: String {
        if item.isMarked {
            return item.due.map { DueText.full($0, hasTime: false) } ?? (item.kind == .result ? "Result" : "Assignment")
        }
        if item.kind == .result { return "Click to add the mark" }
        return item.handedIn ? "Handed in · click to add the mark" : "Not handed in yet"
    }
}

// MARK: On the primary menu

/// Assignments on the primary menu: what's due next and how far through it you are, or
/// your average once there's nothing to hand in.
struct AssignmentsToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AssignmentsStore
    @State var hovering = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date
            let all = store.assignments
            let open = all.open
            let overdue = open.filter { $0.isOverdue(now: now) }.count
            let table = model.timetableStore?.timetable

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ToolIcon(symbol: "list.bullet.clipboard")
                    Text("Assignments")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !open.isEmpty {
                        Text("\(open.count)")
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(overdue > 0 ? Theme.danger : Theme.text)
                            .help(overdue > 0 ? "\(open.count) to hand in, \(overdue) overdue" : "\(open.count) to hand in")
                    }
                }
                Spacer(minLength: 0)
                if open.isEmpty {
                    AssignmentsTileIdle(all: all)
                } else {
                    ForEach(open.prefix(2)) { item in
                        ClassLine(label: item.isOverdue(now: now) ? "Overdue" : "Due",
                                  colour: table.map { PlannerLook.colour(for: item.subject, in: $0) } ?? Theme.tertiary,
                                  subject: item.title,
                                  detail: AssignmentsToolTile.detail(item, now: now))
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
        .onTapGesture { model.openAssignments() }
        .onHover { hovering = $0 }
        .help("Open your assignments and marks")
    }

    /// "Fri 4 pm · 2/5 steps".
    static func detail(_ item: Assignment, now: Date) -> String {
        let due = AssignmentLook.due(item, now: now)
        guard !item.steps.isEmpty else { return due }
        return "\(due) · \(item.stepsDone)/\(item.steps.count) steps"
    }
}

/// The tile with nothing to hand in: your average, or a nudge to add something.
struct AssignmentsTileIdle: View {
    let all: Assignments

    var body: some View {
        let summaries = all.subjects.map { Marks.summary(subject: $0, items: all.items, goal: all.goal(for: $0)) }
        let average = Marks.overall(summaries)

        Text(average.map { "Averaging \(Marks.text($0))" } ?? "Nothing to hand in")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.text2)
            .lineLimit(1)
        Text(average == nil ? "Click to add an assignment or a mark" : "Nothing to hand in")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
    }
}
