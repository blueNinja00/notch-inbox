import AppKit
import SwiftUI

/// Your week as a calendar: the hours down the side, Monday to Friday across, every class and
/// activity at its own times in its subject's colour. Click any time to add one, click one
/// to edit it in the side panel, drag it to move it, or click a bell time to change it.
/// Today and the class on now are lit up.
struct TimetableView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    /// For the study sessions planned into empty slots.
    @ObservedObject var planner: PlannerStore
    @ObservedObject var settings: AppSettings
    let expanded: Bool

    init(model: NotchModel, store: TimetableStore, planner: PlannerStore, settings: AppSettings, expanded: Bool) {
        self.model = model
        self.store = store
        self.planner = planner
        self.settings = settings
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
                WeekCalendar(model: model, store: store, planner: planner, settings: settings, expanded: expanded)
                if let edit = model.timetableEdit {
                    Group {
                        switch edit {
                        case .event(let id):
                            EventEditor(model: model, store: store, id: id)
                                .id("event-\(id.uuidString)")
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
                                .fill(selected ? Theme.onAccent : Theme.accent)
                                .frame(width: 5, height: 5)
                        }
                        Text(Timetable.weekName(week))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(selected ? Theme.accent : Color.clear))
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

// MARK: The week

/// The week as a calendar: the hours down the left (with the school day's bell times),
/// a column for each day, and every class and activity at its own times. Click any time
/// to add one there; click one to edit it; drag it to move it, or its bottom edge to make
/// it longer or shorter. Classes at the same time sit side by side.
struct WeekCalendar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    /// For the study sessions planned into free time.
    @ObservedObject var planner: PlannerStore
    @ObservedObject var settings: AppSettings
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
            // Homework and revision planned into this week's free time.
            let planned = showingThisWeek && settings.plansStudy
                ? WeekCalendar.planned(planner.planner, table: table, now: now, daily: settings.studyMinutesADay,
                                       steps: model.assignmentsStore?.assignments.planTasks() ?? [])
                : [:]

            GeometryReader { area in
                let labelWidth: CGFloat = expanded ? 78 : 66
                let layout = WeekCalendar.Layout(table: table, width: area.size.width, height: area.size.height - header - gap,
                                                 labelWidth: labelWidth, gap: gap, expanded: expanded)

                VStack(spacing: gap) {
                    DayHeader(days: table.dayCount, today: today,
                              monday: showingThisWeek ? Timetable.monday(of: now, calendar: calendar) : nil,
                              labelWidth: labelWidth, gap: gap)
                        .frame(height: header)
                    ScrollViewReader { scroller in
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: gap) {
                                TimeAxis(model: model, table: table, layout: layout)
                                ForEach(0..<table.dayCount, id: \.self) { day in
                                    DayColumn(model: model, store: store, table: table, day: day, layout: layout,
                                              events: table.events(day: day, week: model.timetableWeek),
                                              planned: planned[day] ?? [],
                                              today: today, minute: minute)
                                }
                            }
                        }
                        .scrollIndicators(layout.scrolls ? .automatic : .never)
                        .onAppear {
                            // A long day scrolls: start an hour before now, or at the start of school.
                            guard layout.scrolls else { return }
                            let target = WeekCalendar.firstHour(table: table, minute: today == nil ? nil : minute)
                            DispatchQueue.main.async {
                                scroller.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
                .overlay {
                    if table.isEmpty {
                        WeekCalendarHint()
                    }
                }
            }
        }
    }

    /// The sizes everything is drawn at: how tall a minute is, and how wide a day.
    struct Layout {
        let start: Int
        let end: Int
        let scale: CGFloat
        let columnWidth: CGFloat
        let gap: CGFloat
        let labelWidth: CGFloat
        let height: CGFloat
        let scrolls: Bool

        init(table: Timetable, width: CGFloat, height: CGFloat, labelWidth: CGFloat, gap: CGFloat, expanded: Bool) {
            start = table.shownStart
            end = table.shownEnd
            let days = CGFloat(max(1, table.dayCount))
            columnWidth = max(40, (width - labelWidth - gap * days) / days)
            // The school day (and an hour) fits on screen, within reason; the rest scrolls.
            let school = CGFloat(max(240, table.schoolEnd - table.schoolStart + 60))
            scale = min(expanded ? 2.2 : 1.6, max(0.55, height / school))
            self.gap = gap
            self.labelWidth = labelWidth
            self.height = CGFloat(end - start) * scale
            scrolls = self.height > height + 1
        }

        func y(_ minute: Int) -> CGFloat { CGFloat(minute - start) * scale }
        func minute(at y: CGFloat) -> Int { start + Int((y / scale).rounded(.down)) }
        var step: CGFloat { columnWidth + gap }
    }

    /// The hour to show at the top: the one before now, or the start of school.
    static func firstHour(table: Timetable, minute: Int?) -> Int {
        let first = table.shownStart / 60
        let last = max(first, table.shownEnd / 60 - 1)
        let wanted = minute.map { $0 / 60 - 1 } ?? table.schoolStart / 60
        return max(first, min(last, wanted))
    }

    /// A study session planned into free time this week.
    struct Planned: Identifiable {
        let id: Int
        let start: Int
        let end: Int
        let title: String
    }

    /// This week's study sessions, by day (0 is Monday).
    static func planned(_ planner: Planner, table: Timetable, now: Date, daily: Int, steps: [PlannerTask] = [],
                        calendar: Calendar = .current) -> [Int: [Planned]] {
        let sessions = StudyPlanner.plan(tasks: planner.tasks + steps, exams: planner.exams, timetable: table, now: now,
                                         calendar: calendar, daily: daily)
        let monday = Timetable.monday(of: now, calendar: calendar)
        var result: [Int: [Planned]] = [:]
        for (index, session) in sessions.enumerated() {
            let day = calendar.dateComponents([.day], from: monday, to: calendar.startOfDay(for: session.start)).day ?? -1
            guard (0..<table.dayCount).contains(day) else { continue }
            let start = Timetable.minuteOfDay(session.start, calendar: calendar)
            result[day, default: []].append(Planned(id: index, start: start, end: start + session.minutes, title: session.title))
        }
        return result
    }
}

/// On an empty timetable: how to fill it in.
struct WeekCalendarHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Click any time on a day to add a class or activity")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text("Drag it to move it, or its bottom edge to change when it ends. Or ask the assistant.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface.opacity(0.92)))
        .allowsHitTesting(false)
    }
}

/// Down the left: the hours, and the school day's bell times by name. Click a bell time to
/// change it.
struct TimeAxis: View {
    @ObservedObject var model: NotchModel
    let table: Timetable
    let layout: WeekCalendar.Layout

    var body: some View {
        VStack(spacing: 0) {
            // One row an hour, to scroll to.
            ForEach(layout.start / 60 ..< max(layout.start / 60 + 1, layout.end / 60), id: \.self) { hour in
                Color.clear
                    .frame(width: layout.labelWidth, height: 60 * layout.scale)
                    .id(hour)
            }
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(TimeAxis.hours(table: table, layout: layout), id: \.self) { minute in
                    Text(ClockTime.hour(minute))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .offset(x: 4, y: layout.y(minute) + 1)
                }
                ForEach(table.periods) { period in
                    BellLabel(period: period, height: CGFloat(period.end - period.start) * layout.scale, width: layout.labelWidth,
                              selected: model.timetableEdit == .period(period.id), edit: { model.editPeriod(period.id) })
                        .offset(y: layout.y(period.start))
                }
            }
        }
    }

    /// The hours labelled: every hour shown, except inside the school day (its bell times
    /// are labelled there instead).
    static func hours(table: Timetable, layout: WeekCalendar.Layout) -> [Int] {
        stride(from: layout.start, to: layout.end, by: 60).filter { minute in
            !(minute >= table.schoolStart && minute < table.schoolEnd)
        }
    }
}

/// A bell time's name (and times, if there's room) beside the hours. Click to change it.
struct BellLabel: View {
    let period: Timetable.Period
    let height: CGFloat
    let width: CGFloat
    let selected: Bool
    let edit: () -> Void
    @State var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if height >= 11 {
                Text(period.name)
                    .font(.system(size: period.isBreak ? 10 : 11, weight: .semibold))
                    .foregroundStyle(period.isBreak ? Theme.tertiary : Theme.text2)
            }
            if height >= 26 {
                Text(period.times)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .lineLimit(1)
        .padding(.leading, 4)
        .frame(width: width, height: max(1, height), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected || hovering ? Theme.hover.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .onHover { hovering = $0 }
        .help("Change \(period.name)'s name or times")
    }
}

/// Lines across a day: one on each hour.
struct HourLines: Shape {
    let hours: Int
    let step: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard hours > 0 else { return path }
        for index in 0...hours {
            let y = CGFloat(index) * step
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

/// One day: its classes and activities at their times, the school day's breaks as bands,
/// study planned into free time (faintly), and on today a line at the time it is now.
/// Click an empty time to add a class there.
struct DayColumn: View {
    @ObservedObject var model: NotchModel
    let store: TimetableStore
    let table: Timetable
    let day: Int
    let layout: WeekCalendar.Layout
    let events: [Timetable.Event]
    let planned: [WeekCalendar.Planned]
    let today: Int?
    let minute: Int

    var body: some View {
        let lanes = Timetable.lanes(events)
        let isToday = day == today

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isToday ? 0.035 : 0.018))
            HourLines(hours: (layout.end - layout.start) / 60, step: 60 * layout.scale)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
            // Click an empty time to add a class there.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    model.addEvent(day: day, at: layout.minute(at: point.y))
                }
                .help("Click to add a class or activity at that time")
            if day < 5 {
                ForEach(table.breaks) { period in
                    BreakBand(period: period, height: CGFloat(period.end - period.start) * layout.scale)
                        .offset(y: layout.y(period.start))
                }
            }
            ForEach(planned) { session in
                PlannedBlock(title: session.title, height: CGFloat(session.end - session.start) * layout.scale)
                    .frame(width: layout.columnWidth)
                    .offset(y: layout.y(session.start))
            }
            ForEach(events) { event in
                block(event, lane: lanes[event.id] ?? (lane: 0, of: 1), isToday: isToday)
            }
            if isToday && minute >= layout.start && minute < layout.end {
                NowLine(width: layout.columnWidth)
                    .offset(y: layout.y(minute) - 3)
            }
        }
        .frame(width: layout.columnWidth, height: layout.height)
    }

    private func block(_ event: Timetable.Event, lane: (lane: Int, of: Int), isToday: Bool) -> some View {
        let laneWidth = layout.columnWidth / CGFloat(max(1, lane.of))
        var isPast = false
        if let today = today {
            isPast = day < today || (isToday && event.end <= minute)
        }
        return EventBlock(event: event, colour: Theme.subject(table.colour(for: event.subject)),
                          width: max(10, laneWidth - 2), height: max(14, CGFloat(event.minutes) * layout.scale), layout: layout,
                          isNow: isToday && event.contains(minute), isPast: isPast,
                          selected: model.timetableEdit == .event(event.id),
                          open: { model.editEvent(event.id) },
                          move: { days, minutes in
                              store.change { $0.move(event.id, day: event.day + days, start: event.start + minutes) }
                          },
                          resize: { minutes in
                              store.change { $0.resize(event.id, end: event.end + minutes) }
                          })
            .offset(x: laneWidth * CGFloat(lane.lane), y: layout.y(event.start))
    }
}

/// Recess, lunch: a faint band across a school day.
struct BreakBand: View {
    let period: Timetable.Period
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: max(1, height))
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

/// Study the planner fitted into free time: a dashed outline with what it's for.
struct PlannedBlock: View {
    let title: String
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 4) {
            Image(systemName: "book")
                .font(.system(size: 9.5, weight: .semibold))
            if height >= 14 {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(8, height))
        .overlay(shape.strokeBorder(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .allowsHitTesting(false)
        .help("Planned for study: \(title)")
    }
}

/// The time it is now, across today.
struct NowLine: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 1.5)
        }
        .frame(width: width, height: 6)
        .allowsHitTesting(false)
    }
}

/// One class or activity: its subject's colour, its name, its times and where. Click it to
/// edit it; drag it to move it (to another time, or another day); drag its bottom edge to
/// change when it ends. Times snap to five minutes.
struct EventBlock: View {
    let event: Timetable.Event
    let colour: Color
    let width: CGFloat
    let height: CGFloat
    let layout: WeekCalendar.Layout
    let isNow: Bool
    let isPast: Bool
    let selected: Bool
    let open: () -> Void
    /// Moved by so many days and minutes.
    let move: (Int, Int) -> Void
    /// Made longer (or shorter) by so many minutes.
    let resize: (Int) -> Void
    @State var drag: CGSize = .zero
    @State var stretch: CGFloat = 0
    @State var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let moved = EventBlock.snapped(drag.height, scale: layout.scale)
        let longer = EventBlock.snapped(stretch, scale: layout.scale)
        let start = event.start + moved
        let end = max(event.start + Timetable.shortest, event.end + longer) + moved
        let busy = drag != .zero || stretch != 0
        let shown = max(14, height + CGFloat(longer) * layout.scale)

        ZStack(alignment: .topLeading) {
            shape.fill(colour.opacity(isNow ? 0.36 : (hovering || selected || busy ? 0.3 : 0.22)))
            HStack(spacing: 0) {
                colour.frame(width: 3)
                Spacer(minLength: 0)
            }
            .clipShape(shape)
            EventLabel(subject: event.subject, times: "\(ClockTime.short(start))–\(ClockTime.short(end))", room: event.room,
                       colour: colour, height: shown)
            // The bottom edge: drag it to change when it ends.
            Color.clear
                .frame(height: min(7, shown / 3))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in stretch = value.translation.height }
                    .onEnded { value in
                        let minutes = EventBlock.snapped(value.translation.height, scale: layout.scale)
                        stretch = 0
                        if minutes != 0 { resize(minutes) }
                    })
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
        }
        .frame(width: width, height: shown)
        .overlay(shape.strokeBorder(selected ? Theme.accent : (isNow ? colour : Color.clear), lineWidth: selected ? 1.5 : 1.2))
        .shadow(color: busy ? Color.black.opacity(0.35) : (isNow ? colour.opacity(0.45) : Color.clear), radius: busy ? 6 : 8)
        .opacity(isPast && !selected && !busy ? 0.5 : 1)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in drag = value.translation }
            .onEnded { value in
                let days = Int((value.translation.width / layout.step).rounded())
                let minutes = EventBlock.snapped(value.translation.height, scale: layout.scale)
                drag = .zero
                if days != 0 || minutes != 0 { move(days, minutes) }
            })
        .offset(x: CGFloat(Int((drag.width / layout.step).rounded())) * layout.step, y: CGFloat(moved) * layout.scale)
        .zIndex(busy ? 2 : (selected ? 1 : 0))
        .onHover { hovering = $0 }
        .help("\(event.subject.isEmpty ? "Class" : event.subject), \(event.times). Click to edit; drag to move.")
    }

    /// A drag of so many points as minutes, to the nearest five.
    static func snapped(_ points: CGFloat, scale: CGFloat) -> Int {
        guard scale > 0 else { return 0 }
        let minutes = Double(points / scale)
        return Int((minutes / Double(Timetable.snap)).rounded()) * Timetable.snap
    }
}

/// A class's words: its name, then its times and where, as room allows.
struct EventLabel: View {
    let subject: String
    let times: String
    let room: String
    let colour: Color
    let height: CGFloat

    var body: some View {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 1) {
            if height >= 30 {
                Text(name.isEmpty ? "New class" : name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(name.isEmpty ? Theme.tertiary : Theme.text)
                Text(room.isEmpty ? times : "\(times) · \(room)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(colour.opacity(0.95))
            } else {
                (Text(name.isEmpty ? "New class" : name).foregroundColor(name.isEmpty ? Theme.tertiary : Theme.text)
                    + Text("  " + times).foregroundColor(colour))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .lineLimit(1)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.top, height >= 30 ? 5 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height >= 30 ? .topLeading : .leading)
        .allowsHitTesting(false)
    }
}

// MARK: Editing

/// The side panel for one class or activity: what it is, where and with whom, when it
/// starts and ends (or which bell time it's on), the other days it's on, and its colour.
/// Everything saves as you type.
struct EventEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    let id: UUID
    @FocusState private var focused: Field?

    enum Field {
        case subject
        case room
        case teacher
    }

    init(model: NotchModel, store: TimetableStore, id: UUID) {
        self.model = model
        self.store = store
        self.id = id
    }

    var body: some View {
        if let event = store.timetable.event(id) {
            form(event)
        } else {
            // (It was deleted, or tidied away.)
            Color.clear
                .onAppear { model.timetableEdit = nil }
        }
    }

    @ViewBuilder
    private func form(_ event: Timetable.Event) -> some View {
        let table = store.timetable
        let subject = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestions = table.subjects.filter { name in
            name.lowercased() != subject.lowercased() && (subject.isEmpty || name.lowercased().hasPrefix(subject.lowercased()))
        }
        let outside = event.start < table.schoolStart || event.start >= table.schoolEnd || event.day >= 5

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: Timetable.dayNames[event.day],
                         detail: event.times + (table.twoWeeks ? " · \(Timetable.weekName(event.week))" : ""),
                         close: { model.timetableEdit = nil })
            EditorField(label: outside ? "Activity" : "Subject") {
                TextField(outside ? "e.g. Soccer training" : "e.g. Maths", text: binding(\.subject))
                    .focused($focused, equals: .subject)
                    .onSubmit { focused = .room }
            }
            if !suggestions.isEmpty {
                SubjectSuggestions(names: Array(suggestions.prefix(8)), table: table, pick: pick)
            }
            EditorField(label: outside ? "Where" : "Room") {
                TextField(outside ? "e.g. Oval" : "e.g. B12", text: binding(\.room))
                    .focused($focused, equals: .room)
                    .onSubmit { focused = .teacher }
            }
            EditorField(label: outside ? "With" : "Teacher") {
                TextField(outside ? "e.g. Coach Sam" : "e.g. Ms Lee", text: binding(\.teacher))
                    .focused($focused, equals: .teacher)
                    .onSubmit { model.timetableEdit = nil }
            }
            EventTimes(store: store, id: id)
            EventDays(store: store, id: id)
            if !subject.isEmpty {
                SubjectColours(store: store, subject: subject)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                PillButton(title: "Delete", action: {
                    store.change { $0.removeEvent(id) }
                    model.timetableEdit = nil
                })
                Spacer(minLength: 0)
                PillButton(title: "Done", prominent: true, action: { model.timetableEdit = nil })
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear {
            if subject.isEmpty { focused = .subject }
        }
    }

    /// Edits one part of the class, saving as you type.
    private func binding(_ part: WritableKeyPath<Timetable.Event, String>) -> Binding<String> {
        Binding(
            get: { store.timetable.event(id)?[keyPath: part] ?? "" },
            set: { typed in
                store.change { table in
                    table.change(id) { $0[keyPath: part] = typed }
                }
            }
        )
    }

    /// A subject you've used before, with its usual room and teacher.
    private func pick(_ subject: String) {
        store.change { table in
            let usual = table.usual(for: subject)
            table.change(id) { event in
                event.subject = subject
                if event.room.trimmingCharacters(in: .whitespaces).isEmpty {
                    event.room = usual?.room ?? ""
                }
                if event.teacher.trimmingCharacters(in: .whitespaces).isEmpty {
                    event.teacher = usual?.teacher ?? ""
                }
            }
        }
        focused = .room
    }
}

/// Subjects you've used before, as chips in their colours.
struct SubjectSuggestions: View {
    let names: [String]
    let table: Timetable
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(names, id: \.self) { name in
                    PinChip(title: name, tint: Theme.subject(table.colour(for: name)), selected: false, action: { pick(name) })
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// A subject's colour, for every class of it.
struct SubjectColours: View {
    @ObservedObject var store: TimetableStore
    let subject: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<Timetable.colourCount, id: \.self) { index in
                let chosen = store.timetable.colour(for: subject) == index
                Circle()
                    .fill(Theme.subject(index))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Theme.text, lineWidth: chosen ? 2 : 0).padding(-3))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
                    .onTapGesture { store.change { $0.setColour(index, for: subject) } }
                    .help("Colour for every \(subject) class")
            }
        }
        .padding(.leading, 2)
    }
}

/// When a class starts and ends: typed (saved once they make sense), or one of the school
/// day's bell times with a click.
struct EventTimes: View {
    @ObservedObject var store: TimetableStore
    let id: UUID
    @State var start = ""
    @State var end = ""
    @State var loaded = false

    var body: some View {
        let table = store.timetable
        let event = table.event(id)
        let problem = loaded ? Timetable.timesProblem(start: start, end: end) : nil
        let bells = table.periods.filter { !$0.isBreak }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EditorField(label: "Starts") {
                    TextField("5:15 pm", text: $start)
                        .onChange(of: start) { _ in save() }
                }
                EditorField(label: "Ends") {
                    TextField("6:00 pm", text: $end)
                        .onChange(of: end) { _ in save() }
                }
            }
            if let problem = problem {
                Text(problem)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFB340))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bells.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(bells) { period in
                            PinChip(title: period.name, selected: event?.start == period.start && event?.end == period.end,
                                    action: { use(period) })
                                .help("\(period.name): \(period.times)")
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear(perform: load)
        // Dragged in the timetable while this is open: the times follow.
        .onChange(of: event.map { "\($0.start)-\($0.end)" } ?? "") { _ in
            refresh()
        }
    }

    private func load() {
        refresh()
        DispatchQueue.main.async { loaded = true }
    }

    /// Shows the times saved, unless what's typed already means them.
    private func refresh() {
        guard let event = store.timetable.event(id) else { return }
        if ClockTime.parse(start) != event.start || ClockTime.parse(end) != event.end {
            start = ClockTime.long(event.start)
            end = ClockTime.long(event.end)
        }
    }

    /// Saves as you type, once the times make sense.
    private func save() {
        guard loaded, let from = ClockTime.parse(start), let to = ClockTime.parse(end), Timetable.validTimes(start: from, end: to),
              let event = store.timetable.event(id), event.start != from || event.end != to else { return }
        store.change { table in
            table.change(id) { changed in
                changed.start = from
                changed.end = to
            }
        }
    }

    /// Puts the class on a bell time.
    private func use(_ period: Timetable.Period) {
        store.change { table in
            table.change(id) { changed in
                changed.start = period.start
                changed.end = period.end
            }
        }
        start = ClockTime.long(period.start)
        end = ClockTime.long(period.end)
    }
}

/// The days a class is on: click another day to put the same class there too (same
/// times, same room), or click it again to take it off.
struct EventDays: View {
    @ObservedObject var store: TimetableStore
    let id: UUID

    var body: some View {
        let table = store.timetable
        let on = table.days(of: id)
        let own = table.event(id)?.day

        VStack(alignment: .leading, spacing: 4) {
            Text("On")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 4) {
                ForEach(0..<table.dayCount, id: \.self) { day in
                    PinChip(title: Timetable.shortDayNames[day], selected: on.contains(day), action: {
                        guard day != own else { return }
                        store.change { $0.repeatOn(id, day: day, !on.contains(day)) }
                    })
                    .help(day == own ? "The day this one's on" : (on.contains(day) ? "Take it off \(Timetable.dayNames[day])" : "Put it on \(Timetable.dayNames[day]) too"))
                }
            }
        }
    }
}

/// A hairline with a small label, between parts of a list (the Planner uses it).
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
                .background(Capsule().fill(isToday ? Theme.accent : Color.clear))
                .frame(maxWidth: .infinity)
            }
        }
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
        periodForm
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
                         detail: period?.isBreak == true ? "A break, on every school day" : "A bell time: classes on it move with it",
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
                .help("Removes this bell time, and the classes on its times")
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
                                      subject: lesson.subject, detail: [lesson.room, "until \(ClockTime.short(now.end))"]
                                          .filter { !$0.isEmpty }.joined(separator: " · "))
                        } else {
                            ClassLine(label: "Now", colour: Theme.tertiary, subject: now.name,
                                      detail: "until \(ClockTime.short(now.end))")
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
