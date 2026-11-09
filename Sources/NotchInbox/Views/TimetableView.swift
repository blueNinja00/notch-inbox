import SwiftUI

/// Your week at school: periods down the side, Monday to Friday across, every lesson in its
/// subject's colour. Click a lesson (or an empty slot) to edit it in the side panel, or a
/// period's name to change its times. Today and the class on now are lit up.
struct TimetableView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    let expanded: Bool

    init(model: NotchModel, store: TimetableStore, expanded: Bool) {
        self.model = model
        self.store = store
        self.expanded = expanded
    }

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)
        let table = store.timetable

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "calendar", title: "Timetable") {
                    if table.twoWeeks {
                        WeekSwitch(model: model, thisWeek: table.week(of: Date()))
                    }
                }
            } trailing: {
                HStack(spacing: 2) {
                    if !table.schoolIsOneBlock {
                        IconButton(symbol: "plus", label: "Add a period", action: { model.addPeriod() })
                    }
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make the timetable smaller" : "Expand the timetable",
                               action: { expanded ? model.back() : model.expandTimetable() })
                    SettingsButton(model: model, section: .timetable)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                TimetableGrid(model: model, store: store, expanded: expanded)
                if let edit = model.timetableEdit {
                    Group {
                        switch edit {
                        case .lesson(let slot):
                            LessonEditor(model: model, store: store, slot: slot)
                                .id("lesson-\(slot.week)-\(slot.day)-\(slot.period.uuidString)")
                        case .period(let id):
                            PeriodEditor(model: model, store: store, periodID: id)
                                .id("period-\(id.uuidString)")
                        }
                    }
                    .frame(width: expanded ? 260 : 232)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 6)
            .animation(Theme.spring, value: model.timetableEdit)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// Week A or Week B, with a dot on this week.
struct WeekSwitch: View {
    @ObservedObject var model: NotchModel
    let thisWeek: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { week in
                let selected = model.timetableWeek == week
                Button(action: { model.timetableWeek = week }) {
                    HStack(spacing: 5) {
                        if week == thisWeek {
                            Circle()
                                .fill(selected ? Theme.onAccent : Theme.text)
                                .frame(width: 5, height: 5)
                        }
                        Text(Timetable.weekName(week))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(selected ? Theme.text : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(week == thisWeek ? "This week" : "Next week")
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
        .fixedSize()
    }
}

// MARK: The grid

struct TimetableGrid: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    let expanded: Bool

    private let gap: CGFloat = 4
    private let header: CGFloat = 24

    var body: some View {
        let table = store.timetable

        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let now = context.date
            let calendar = Calendar.current
            let showingThisWeek = table.week(of: now, calendar: calendar) == model.timetableWeek
            let today = showingThisWeek ? table.column(of: now, calendar: calendar) : nil
            let minute = Timetable.minuteOfDay(now, calendar: calendar)
            let rows = table.rows

            GeometryReader { area in
                let heights = rowHeights(rows: rows, height: area.size.height)
                let labelWidth: CGFloat = expanded ? 92 : 78

                VStack(spacing: gap) {
                    DayHeader(days: table.dayCount, today: today,
                              monday: showingThisWeek ? Timetable.monday(of: now, calendar: calendar) : nil,
                              labelWidth: labelWidth, gap: gap)
                        .frame(height: header)

                    ScrollViewReader { scroller in
                        ScrollView(.vertical) {
                            VStack(spacing: gap) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, period in
                                    if index > 0 && rows[index - 1].isActivity != period.isActivity {
                                        SectionLine(label: period.isActivity ? "After school" : "School")
                                            .frame(height: sectionHeight)
                                    }
                                    TimetableRow(model: model, table: table, period: period, today: today, minute: minute,
                                                 labelWidth: labelWidth, classHeight: heights.classHeight * TimetableGrid.weight(period),
                                                 breakHeight: heights.breakHeight, gap: gap)
                                        .id(period.id)
                                }
                            }
                        }
                        .scrollIndicators(heights.scrolls ? .automatic : .never)
                        .scrollDisabled(!heights.scrolls)
                        .onAppear {
                            // Long days scroll: start where you are in the day (or at the start of school).
                            guard heights.scrolls, let target = scrollTarget(rows: rows, minute: today == nil ? nil : minute) else { return }
                            DispatchQueue.main.async {
                                scroller.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The row to show at the top: the one before what's on now, or the start of school.
    private func scrollTarget(rows: [Timetable.Period], minute: Int?) -> UUID? {
        if let minute = minute, let current = rows.firstIndex(where: { $0.end > minute }) {
            return rows[max(0, current - 1)].id
        }
        return rows.first(where: { !$0.isActivity })?.id ?? rows.first?.id
    }

    private let sectionHeight: CGFloat = 12

    /// How tall a row is next to an hour-long one: longer stretches (school as one block) are
    /// taller, up to a little over twice.
    static func weight(_ period: Timetable.Period) -> CGFloat {
        let hours = CGFloat(period.end - period.start) / 60
        return min(2.2, max(1, hours / 2))
    }

    /// Classes and hour blocks share the height left after the slim break rows; long days scroll.
    private func rowHeights(rows: [Timetable.Period], height: CGFloat) -> (classHeight: CGFloat, breakHeight: CGFloat, scrolls: Bool) {
        let breaks = CGFloat(rows.filter { $0.isBreak }.count)
        let classes = max(1, rows.filter { !$0.isBreak }.reduce(CGFloat(0)) { $0 + TimetableGrid.weight($1) })
        var sections: CGFloat = 0
        for (index, row) in rows.enumerated() where index > 0 && rows[index - 1].isActivity != row.isActivity {
            sections += 1
        }
        let breakHeight: CGFloat = expanded ? 22 : 18
        let rowsHeight = height - header - gap
        let gaps = CGFloat(max(0, rows.count - 1) + Int(sections)) * gap
        let fitted = (rowsHeight - gaps - breaks * breakHeight - sections * sectionHeight) / classes
        let minimum: CGFloat = 34
        return (max(minimum, min(fitted, 120)), breakHeight, fitted < minimum)
    }
}

/// One period across the week: a slim band for a break, or the period's name and a lesson
/// for each day.
struct TimetableRow: View {
    @ObservedObject var model: NotchModel
    let table: Timetable
    let period: Timetable.Period
    let today: Int?
    let minute: Int
    let labelWidth: CGFloat
    let classHeight: CGFloat
    let breakHeight: CGFloat
    let gap: CGFloat

    var body: some View {
        let isNow = today != nil && period.contains(minute)
        let editingPeriod = model.timetableEdit == .period(period.id)

        if period.isBreak {
            BreakRow(period: period, isNow: isNow, selected: editingPeriod, edit: { model.editPeriod(period.id) })
                .frame(height: breakHeight)
        } else {
            HStack(spacing: gap) {
                PeriodLabel(period: period, isNow: isNow, selected: editingPeriod, edit: { model.editPeriod(period.id) })
                    .frame(width: labelWidth)
                ForEach(0..<table.dayCount, id: \.self) { day in
                    cell(day: day)
                }
            }
            .frame(height: classHeight)
        }
    }

    private func cell(day: Int) -> LessonCell {
        let slot = Timetable.Slot(week: model.timetableWeek, day: day, period: period.id)
        let lesson = table.lesson(at: slot)
        var isPast = false
        if let today = today {
            isPast = day < today || (day == today && period.end <= minute)
        }
        return LessonCell(lesson: lesson,
                          colour: Theme.subject(table.colour(for: lesson?.subject ?? "")),
                          height: classHeight,
                          isActivity: period.isActivity,
                          isNow: day == today && period.contains(minute),
                          isPast: isPast,
                          selected: model.timetableEdit == .lesson(slot),
                          edit: { model.editLesson(day: day, period: period.id) })
    }
}

/// Mon to Fri across the top; today stands out.
struct DayHeader: View {
    let days: Int
    let today: Int?
    /// This week's Monday, to show dates; nil when looking at the other week.
    let monday: Date?
    let labelWidth: CGFloat
    let gap: CGFloat

    var body: some View {
        HStack(spacing: gap) {
            Color.clear
                .frame(width: labelWidth)
            ForEach(0..<days, id: \.self) { day in
                let isToday = day == today
                HStack(spacing: 4) {
                    Text(Timetable.shortDayNames[day])
                        .font(.system(size: 11.5, weight: .bold))
                    if let date = monday.flatMap({ Calendar.current.date(byAdding: .day, value: day, to: $0) }) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .opacity(isToday ? 0.75 : 0.6)
                    }
                }
                .foregroundStyle(isToday ? Theme.onAccent : Theme.secondary)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Capsule().fill(isToday ? Theme.text : Color.clear))
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A period's name and times, down the left. Click to change them.
struct PeriodLabel: View {
    let period: Timetable.Period
    let isNow: Bool
    let selected: Bool
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if isNow {
                        Circle()
                            .fill(Theme.text)
                            .frame(width: 5, height: 5)
                    }
                    Text(period.isActivity ? ClockTime.hour(period.start) : period.name)
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isNow ? Theme.text : (period.isActivity ? Theme.secondary : Theme.text2))
                        .lineLimit(1)
                }
                Text(period.isActivity ? period.name : period.times)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(period.isActivity ? "Hour blocks before and after school" : "Change \(period.name)'s name or times")
    }
}

/// Where school starts or ends: a hairline with a small label.
struct SectionLine: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiary)
                .fixedSize()
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.leading, 8)
    }
}

/// Recess, lunch: a slim band across the whole week.
struct BreakRow: View {
    let period: Timetable.Period
    let isNow: Bool
    let selected: Bool
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                HStack(spacing: 6) {
                    if isNow {
                        Circle()
                            .fill(Theme.text)
                            .frame(width: 5, height: 5)
                    }
                    Text(period.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isNow ? Theme.text : Theme.secondary)
                    Text(period.times)
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                .fixedSize()
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Change \(period.name)'s name or times")
    }
}

/// One lesson: its subject's colour, the subject, then room and teacher if there's room.
/// Empty slots show a faint outline and a + when you point at them.
struct LessonCell: View {
    let lesson: Timetable.Lesson?
    let colour: Color
    let height: CGFloat
    var isActivity = false
    let isNow: Bool
    let isPast: Bool
    let selected: Bool
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let subject = lesson?.subject.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let details = lesson.map { Timetable.Lesson(subject: "", room: $0.room.trimmingCharacters(in: .whitespaces),
                                                    teacher: $0.teacher.trimmingCharacters(in: .whitespaces)).details } ?? ""
        let filled = lesson != nil

        Button(action: edit) {
            ZStack(alignment: .topLeading) {
                if filled {
                    shape.fill(colour.opacity(isNow ? 0.32 : (hovering || selected ? 0.24 : 0.17)))
                    // The subject's colour as a stripe down the left.
                    HStack(spacing: 0) {
                        colour
                            .frame(width: 3)
                        Spacer(minLength: 0)
                    }
                    .clipShape(shape)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(subject.isEmpty ? "No subject" : subject)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(subject.isEmpty ? Theme.tertiary : Theme.text)
                        if !details.isEmpty && height >= 36 {
                            Text(details)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(colour.opacity(0.95))
                        }
                    }
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height >= 50 ? .topLeading : .leading)
                    .padding(.top, height >= 50 ? 7 : 0)
                } else {
                    shape.strokeBorder(Color.white.opacity(hovering || selected ? 0.22 : (isActivity ? 0.045 : 0.07)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if hovering || selected {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if isNow && filled && height >= 36 {
                    Text("NOW")
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 5)
                        .frame(height: 13)
                        .background(Capsule().fill(colour))
                        .padding(5)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .overlay(
                shape.strokeBorder(selected ? Theme.text : (isNow ? colour : Color.clear), lineWidth: selected ? 1.5 : 1.2)
            )
            .shadow(color: isNow ? colour.opacity(0.45) : Color.clear, radius: 8)
            .opacity(isPast && !selected ? 0.5 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(filled ? (isActivity ? "Edit this activity" : "Edit this lesson") : (isActivity ? "Add an activity" : "Add a lesson"))
    }
}

// MARK: Editing

/// The side panel for one lesson: subject, room, teacher and the subject's colour.
struct LessonEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    let slot: Timetable.Slot
    @FocusState private var focused: Field?

    enum Field {
        case subject
        case room
        case teacher
    }

    init(model: NotchModel, store: TimetableStore, slot: Timetable.Slot) {
        self.model = model
        self.store = store
        self.slot = slot
    }

    var body: some View {
        let table = store.timetable
        let lesson = table.lesson(at: slot)
        let period = table.period(slot.period)
        let isActivity = period?.isActivity ?? false
        let subject = lesson?.subject.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suggestions = table.subjects.filter { name in
            name.lowercased() != subject.lowercased() && (subject.isEmpty || name.lowercased().hasPrefix(subject.lowercased()))
        }

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: Timetable.dayNames[slot.day],
                         detail: (period.map { "\($0.name) · \($0.times)" } ?? "")
                             + (table.twoWeeks ? " · \(Timetable.weekName(slot.week))" : ""),
                         close: { model.timetableEdit = nil })

            EditorField(label: isActivity ? "Activity" : "Subject") {
                TextField(isActivity ? "e.g. Soccer training" : "e.g. Maths", text: binding(\.subject))
                    .focused($focused, equals: .subject)
                    .onSubmit { focused = .room }
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(suggestions.prefix(8), id: \.self) { name in
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
            EditorField(label: isActivity ? "Where" : "Room") {
                TextField(isActivity ? "e.g. Oval" : "e.g. B12", text: binding(\.room))
                    .focused($focused, equals: .room)
                    .onSubmit { focused = .teacher }
            }
            EditorField(label: isActivity ? "With" : "Teacher") {
                TextField(isActivity ? "e.g. Coach Sam" : "e.g. Ms Lee", text: binding(\.teacher))
                    .focused($focused, equals: .teacher)
                    .onSubmit { model.timetableEdit = nil }
            }

            if !subject.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0..<Timetable.colourCount, id: \.self) { index in
                        let chosen = table.colour(for: subject) == index
                        Button(action: { store.change { $0.setColour(index, for: subject) } }) {
                            Circle()
                                .fill(Theme.subject(index))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Theme.text, lineWidth: chosen ? 2 : 0).padding(-3))
                                .frame(width: 20, height: 20)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Colour for every \(subject) lesson")
                    }
                }
                .padding(.leading, 2)
            }

            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if lesson != nil {
                    PillButton(title: "Clear", action: {
                        store.change { $0.setLesson(nil, at: slot) }
                        model.timetableEdit = nil
                    })
                }
                Spacer(minLength: 0)
                PillButton(title: "Done", prominent: true, action: { model.timetableEdit = nil })
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear { focused = .subject }
    }

    /// Edits one part of the lesson, saving as you type.
    private func binding(_ part: WritableKeyPath<Timetable.Lesson, String>) -> Binding<String> {
        Binding(
            get: { store.timetable.lesson(at: slot)?[keyPath: part] ?? "" },
            set: { typed in
                store.change { table in
                    var lesson = table.lesson(at: slot) ?? Timetable.Lesson(subject: "")
                    lesson[keyPath: part] = typed
                    table.setLesson(lesson, at: slot)
                }
            }
        )
    }

    /// A subject you've used before, with its usual room and teacher.
    private func pick(_ subject: String) {
        store.change { table in
            var lesson = table.lesson(at: slot) ?? Timetable.Lesson(subject: "")
            let usual = table.usual(for: subject)
            lesson.subject = subject
            if lesson.room.trimmingCharacters(in: .whitespaces).isEmpty {
                lesson.room = usual?.room ?? ""
            }
            if lesson.teacher.trimmingCharacters(in: .whitespaces).isEmpty {
                lesson.teacher = usual?.teacher ?? ""
            }
            table.setLesson(lesson, at: slot)
        }
        focused = .room
    }
}

/// The side panel for a period: its name, when it starts and ends, and whether it's a break.
struct PeriodEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    let periodID: UUID
    @State private var name = ""
    @State private var start = ""
    @State private var end = ""
    @State private var loaded = false

    init(model: NotchModel, store: TimetableStore, periodID: UUID) {
        self.model = model
        self.store = store
        self.periodID = periodID
    }

    var body: some View {
        if store.timetable.period(periodID)?.isActivity == true {
            BlocksEditor(model: model, store: store)
        } else {
            periodForm
        }
    }

    @ViewBuilder
    private var periodForm: some View {
        let period = store.timetable.period(periodID)
        let startMinute = ClockTime.parse(start)
        let endMinute = ClockTime.parse(end)
        let problem: String? = {
            if startMinute == nil || endMinute == nil { return "Type times like 8:50 or 1:10 pm." }
            if let s = startMinute, let e = endMinute, e <= s { return "It needs to end after it starts." }
            return nil
        }()

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: period?.name ?? "Period",
                         detail: period?.isBreak == true ? "A break, across every day" : "The same times every day",
                         close: { model.timetableEdit = nil })

            EditorField(label: "Name") {
                TextField("e.g. Period 1", text: $name)
                    .onChange(of: name) { _ in save() }
            }
            HStack(spacing: 8) {
                EditorField(label: "Starts") {
                    TextField("8:50", text: $start)
                        .onChange(of: start) { _ in save() }
                }
                EditorField(label: "Ends") {
                    TextField("9:50", text: $end)
                        .onChange(of: end) { _ in save() }
                }
            }
            if let problem = problem, loaded {
                Text(problem)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFB340))
            }
            Toggle(isOn: Binding(
                get: { store.timetable.period(periodID)?.isBreak ?? false },
                set: { isBreak in
                    guard var changed = store.timetable.period(periodID) else { return }
                    changed.isBreak = isBreak
                    store.change { _ = $0.updatePeriod(changed) }
                }
            )) {
                Text("Break, like recess or lunch")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.body)
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 0)
            HStack(spacing: 8) {
                PillButton(title: "Remove", action: {
                    store.change { $0.removePeriod(periodID) }
                    model.timetableEdit = nil
                })
                .help("Removes this period and its lessons")
                Spacer(minLength: 0)
                PillButton(title: "Done", prominent: true, action: { model.timetableEdit = nil })
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear {
            if let period = period {
                name = period.name
                start = ClockTime.long(period.start)
                end = ClockTime.long(period.end)
            }
            DispatchQueue.main.async { loaded = true }
        }
    }

    /// Saves as you type, once the times make sense.
    private func save() {
        guard loaded, var changed = store.timetable.period(periodID),
              let startMinute = ClockTime.parse(start), let endMinute = ClockTime.parse(end), endMinute > startMinute else { return }
        changed.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? changed.name : name
        changed.start = startMinute
        changed.end = endMinute
        store.change { _ = $0.updatePeriod(changed) }
    }
}

/// The side panel for the hour blocks: how many before school and after.
struct BlocksEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore

    var body: some View {
        let table = store.timetable

        VStack(alignment: .leading, spacing: 12) {
            EditorHeader(title: "Hour blocks",
                         detail: "For extracurriculars, before and after school",
                         close: { model.timetableEdit = nil })
            BlockCountRow(title: "Before school",
                          detail: table.beforeSchool == 0 ? "None" : "From \(ClockTime.hour(max(0, table.schoolStart - table.beforeSchool * 60)))",
                          count: table.beforeSchool, range: 0...Timetable.maxBefore,
                          change: { count in store.change { $0.setBlocks(before: count) } })
            BlockCountRow(title: "After school",
                          detail: table.afterSchool == 0 ? "None" : "Until \(ClockTime.hour(min(24 * 60, table.schoolEnd + table.afterSchool * 60)))",
                          count: table.afterSchool, range: 0...Timetable.maxAfter,
                          change: { count in store.change { $0.setBlocks(after: count) } })
            Text("They follow the school day: change when school starts or ends by clicking a period. Taking a block away keeps what was in it, for if you add it back.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                PillButton(title: "Done", prominent: true, action: { model.timetableEdit = nil })
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// "After school · Until 9 pm  [−] 5 [+]".
struct BlockCountRow: View {
    let title: String
    let detail: String
    let count: Int
    let range: ClosedRange<Int>
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            CountStepper(count: count, range: range, change: change)
        }
    }
}

/// − 5 +, in a capsule.
struct CountStepper: View {
    let count: Int
    let range: ClosedRange<Int>
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "minus", label: "Fewer", size: 24, tint: count > range.lowerBound ? Theme.text2 : Theme.tertiary.opacity(0.5),
                       action: { if count > range.lowerBound { change(count - 1) } })
            Text("\(count)")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 18)
            IconButton(symbol: "plus", label: "More", size: 24, tint: count < range.upperBound ? Theme.text2 : Theme.tertiary.opacity(0.5),
                       action: { if count < range.upperBound { change(count + 1) } })
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(Theme.raised))
        .fixedSize()
    }
}

struct EditorHeader: View {
    let title: String
    let detail: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", label: "Close (Esc)", size: 24, tint: Theme.tertiary, action: close)
        }
    }
}

/// A labelled text box for the side panels.
struct EditorField<Field: View>: View {
    let label: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            field()
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        }
    }
}

// MARK: On the primary menu

/// Now and next: the class you're in and the one after, in their colours.
struct TimetableToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    @State var hovering = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let table = store.timetable
            let now = table.now(at: context.date)
            let next = table.next(after: context.date)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ToolIcon(symbol: "calendar")
                    Text("Timetable")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if table.twoWeeks {
                        Text(Timetable.weekName(table.week(of: context.date)))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                if table.isEmpty {
                    Text("Add your classes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Click to set up your week")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                } else {
                    if let now = now {
                        if let lesson = now.lesson, !lesson.subject.trimmingCharacters(in: .whitespaces).isEmpty {
                            ClassLine(label: "Now", colour: Theme.subject(table.colour(for: lesson.subject)),
                                      subject: lesson.subject, detail: [lesson.room, "until \(ClockTime.short(now.period.end))"]
                                          .filter { !$0.isEmpty }.joined(separator: " · "))
                        } else {
                            ClassLine(label: "Now", colour: Theme.tertiary,
                                      subject: now.period.isBreak ? now.period.name : "Free",
                                      detail: "until \(ClockTime.short(now.period.end))")
                        }
                    }
                    if let next = next, let lesson = next.moment.lesson {
                        ClassLine(label: "Next", colour: Theme.subject(table.colour(for: lesson.subject)),
                                  subject: lesson.subject,
                                  detail: [lesson.room, TimetableToolTile.when(next.date, now: context.date)]
                                      .filter { !$0.isEmpty }.joined(separator: " · "))
                    } else if now == nil {
                        Text("No classes coming up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text2)
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
        .onTapGesture { model.openTimetable() }
        .onHover { hovering = $0 }
        .help("Open the timetable")
    }

    /// "11:10", "Tomorrow 8:50" or "Mon 8:50".
    static func when(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let time = ClockTime.short(Timetable.minuteOfDay(date, calendar: calendar))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(Timetable.shortDayNames[Timetable.dayIndex(of: date, calendar: calendar)]) \(time)"
    }
}

/// "Now · Maths · B12 · until 10:20", with the subject's colour.
struct ClassLine: View {
    let label: String
    let colour: Color
    let subject: String
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(colour)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Theme.tertiary)
                    Text(subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                }
                Text(detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
        }
    }
}
