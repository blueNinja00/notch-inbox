import AppKit
import SwiftUI

// MARK: The library

/// How the library's pieces look.
enum LibraryLook {
    /// A subject's colour: the one it has in your timetable.
    static func tint(_ subject: String, table: Timetable?) -> Color {
        guard let table = table else { return Theme.tertiary }
        return Theme.subject(table.colour(for: subject))
    }

    static func symbol(_ report: LibraryReport) -> String {
        report.isChain ? "link" : "doc.text"
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The library: every report your agents have finished, kept after the agents have left
/// the room. Search it, open a report, and pin one to a subject or an assignment.
struct ReportLibraryView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: ReportsStore

    var body: some View {
        let library = store.library
        let table = model.timetableStore?.timetable
        let work = model.assignmentsStore?.assignments

        if let report = library.report(model.reportOpen) {
            ReportPage(model: model, store: store, report: report, table: table,
                       subjects: ReportLibrary.pinSubjects(classes: table?.classes ?? [], assignments: work?.subjects ?? [], own: library.subjects),
                       assignments: work?.open ?? [], pinnedTo: work?.item(report.assignment))
                .id(report.id)
        } else {
            ReportList(model: model, library: library, table: table)
        }
    }
}

/// The list: the newest report first, or what a search found.
struct ReportList: View {
    @ObservedObject var model: NotchModel
    let library: ReportLibrary
    let table: Timetable?

    var body: some View {
        let subjects = library.subjects
        // (A subject nothing is pinned to any more isn't narrowing anything.)
        let picked = subjects.first { ReportLibrary.same($0, model.librarySubject) } ?? ""
        let query = model.librarySearch
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let found = library.search(query, subject: picked)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Library")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(library.countLine(showing: found.count, narrowed: searching || !picked.isEmpty))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                LibrarySearchField(model: model)
            }
            if !subjects.isEmpty {
                LibrarySubjectBar(subjects: subjects, picked: picked, table: table, pick: pick)
            }
            if found.isEmpty {
                Text(ReportLibrary.emptyLine(any: !library.reports.isEmpty, searching: searching, subject: picked))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(found) { report in
                            ReportRow(report: report, line: ReportLibrary.snippet(of: report, for: query),
                                      tint: LibraryLook.tint(report.subject, table: table),
                                      open: { model.showReport(report.id, part: ReportLibrary.part(of: report, matching: query)) })
                                .contextMenu {
                                    ReportMenu(model: model, report: report)
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Click a subject to see only what's pinned to it; click it again for everything.
    private func pick(_ subject: String) {
        model.librarySubject = ReportLibrary.same(subject, model.librarySubject) ? "" : subject
    }
}

/// The library's search box: it looks through names, jobs and the reports themselves.
struct LibrarySearchField: View {
    @ObservedObject var model: NotchModel
    @FocusState private var typing: Bool

    init(model: NotchModel) {
        self.model = model
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            TextField("Search your reports", text: $model.librarySearch)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .focused($typing)
            if !model.librarySearch.isEmpty {
                IconButton(symbol: "xmark", label: "Clear the search (Esc)", size: 20, tint: Theme.tertiary, action: { model.librarySearch = "" })
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(width: 230, height: 26)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
        // The Search shortcut puts the cursor here.
        .onAppear(perform: takeFocus)
        .onChange(of: model.agentsFocusTick) { _ in
            takeFocus()
        }
    }

    private func takeFocus() {
        guard model.takeFocus(.search) else { return }
        // (A moment later, so that a box that has only just appeared is there to take it.)
        DispatchQueue.main.async {
            typing = true
        }
    }
}

/// The subjects reports are pinned to: click one to see only its reports.
struct LibrarySubjectBar: View {
    let subjects: [String]
    let picked: String
    let table: Timetable?
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(subjects.prefix(14), id: \.self) { name in
                    PinChip(title: name, tint: LibraryLook.tint(name, table: table), selected: ReportLibrary.same(name, picked),
                            action: { pick(name) })
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// A subject or an assignment to pick: filled in when it's the one picked.
struct PinChip: View {
    let title: String
    /// A subject's colour, as a dot before its name.
    var tint: Color? = nil
    let selected: Bool
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let tint = tint {
                    Circle()
                        .fill(selected ? Theme.onAccent : tint)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        if selected {
            return Theme.accent
        }
        return hovering ? Theme.hover : Theme.raised
    }
}

/// A subject's name with its colour, beside a report's name.
struct SubjectTag: View {
    let name: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }
}

/// One report in the list: its name, where it's pinned, and its first words (or the words
/// around what you searched for).
struct ReportRow: View {
    let report: LibraryReport
    let line: String
    let tint: Color
    let open: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: LibraryLook.symbol(report))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.avatar))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(report.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if !report.subject.isEmpty {
                            SubjectTag(name: report.subject, tint: tint)
                        }
                        if report.assignment != nil {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Theme.tertiary)
                                .help("Pinned to an assignment")
                        }
                    }
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(MailTime.label(for: report.made))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.hover.opacity(0.55) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("\(report.name), \(MailTime.label(for: report.made))"))
    }
}

/// A report's right-click menu in the list.
struct ReportMenu: View {
    @ObservedObject var model: NotchModel
    let report: LibraryReport

    var body: some View {
        Button("Open") { model.showReport(report.id) }
        Button("Copy the Report") { LibraryLook.copy(report.newest?.text ?? "") }
        Divider()
        Button("Delete from the Library") { model.removeReport(report.id) }
    }
}

// MARK: One report

/// A report from the library: what was asked and what came back, with a chain's stages
/// side by side. Its name can be changed by typing over it.
struct ReportPage: View {
    @ObservedObject var model: NotchModel
    let store: ReportsStore
    let report: LibraryReport
    let table: Timetable?
    /// What it can be pinned to: subjects, and assignments still to hand in.
    let subjects: [String]
    let assignments: [Assignment]
    /// The assignment it's pinned to, if that's still in your list.
    let pinnedTo: Assignment?
    @State var pinning = false
    @State var copied = false

    var body: some View {
        let part = report.part(model.reportPart)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconButton(symbol: "chevron.left", label: "Back to the library", size: 26, action: { model.closeReport() })
                VStack(alignment: .leading, spacing: 1) {
                    TextField("Name this report", text: name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .help("Type over the name to change it")
                    Text("\(report.about) · \(MailTime.label(for: report.made))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                ReportActions(model: model, report: report, part: part, pinning: $pinning, copied: $copied)
            }
            if report.parts.count > 1 {
                ReportPartTabs(parts: report.parts, picked: part?.id, pick: { model.reportPart = $0 })
            }
            if pinning {
                ReportPinPicker(model: model, report: report, table: table, subjects: subjects, assignments: assignments, pinnedTo: pinnedTo)
            } else if report.isPinned {
                ReportPinLine(model: model, report: report, table: table, pinnedTo: pinnedTo)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if !report.task.isEmpty {
                        AgentTask(task: report.task)
                    }
                    if let part = part, !part.files.isEmpty {
                        ReportFileChips(model: model, part: part)
                    }
                    if let part = part {
                        AgentReportText(report: part.text, finished: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            // (Another part of a chain's work starts from its top.)
            .id(part?.id)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The name, read from the library as it's typed.
    private var name: Binding<String> {
        let id = report.id
        return Binding(
            get: { store.library.report(id)?.title ?? "" },
            set: { typed in model.renameReport(id, to: typed) }
        )
    }
}

/// Beside a report's name: copy it, pin it, show its folder, or take it out of the library.
struct ReportActions: View {
    @ObservedObject var model: NotchModel
    let report: LibraryReport
    let part: ReportPart?
    @Binding var pinning: Bool
    @Binding var copied: Bool

    var body: some View {
        HStack(spacing: 6) {
            SmallPill(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", action: copy)
                .help("Copy this report")
            SmallPill(title: pinning ? "Done" : "Pin", symbol: pinning ? "checkmark" : (report.isPinned ? "pin.fill" : "pin"),
                      action: { pinning.toggle() })
                .help("Pin this report to a subject or to an assignment, where it then shows")
            if let folder = part?.folder, !folder.isEmpty {
                IconButton(symbol: "folder", label: "Open the folder its agent worked in", size: 26,
                           action: { model.onShowReportFolder?(folder) })
            }
            IconButton(symbol: "trash", label: "Delete this report from the library (its agent's files stay in their folder)", size: 26,
                       action: { model.removeReport(report.id) })
        }
    }

    private func copy() {
        LibraryLook.copy(part?.text ?? "")
        copied = true
    }
}

/// A chain's work, stage by stage: the research notes, the draft, the checked version.
struct ReportPartTabs: View {
    let parts: [ReportPart]
    let picked: UUID?
    let pick: (UUID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(parts) { part in
                ReportPartTab(title: part.label, selected: part.id == picked, pick: { pick(part.id) })
            }
            Spacer(minLength: 0)
        }
    }
}

struct ReportPartTab: View {
    let title: String
    let selected: Bool
    let pick: () -> Void
    @State var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .onTapGesture(perform: pick)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        if selected {
            return Theme.raised
        }
        return hovering ? Theme.hover : Theme.lane
    }
}

/// Where a report is pinned, under its name. Click the assignment to go to it.
struct ReportPinLine: View {
    @ObservedObject var model: NotchModel
    let report: LibraryReport
    let table: Timetable?
    let pinnedTo: Assignment?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            if !report.subject.isEmpty {
                SubjectTag(name: report.subject, tint: LibraryLook.tint(report.subject, table: table))
            }
            if let item = pinnedTo {
                SmallPill(title: item.title.isEmpty ? "Assignment" : item.title, symbol: HomeTile.assignments.symbol,
                          action: { model.showAssignment(item.id) })
                    .help("Go to this assignment")
            }
            Spacer(minLength: 0)
        }
    }
}

/// Picking what a report is pinned to: one subject, and one assignment.
struct ReportPinPicker: View {
    @ObservedObject var model: NotchModel
    let report: LibraryReport
    let table: Timetable?
    let subjects: [String]
    let assignments: [Assignment]
    let pinnedTo: Assignment?

    var body: some View {
        // (The one it's pinned to stays in the row after it's been handed in.)
        let listed = ReportPinPicker.listed(assignments, with: pinnedTo)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentCaption(text: "Subject")
                    .frame(width: 74, alignment: .leading)
                if subjects.isEmpty {
                    ReportPinNote(text: "Your timetable's classes and your assignments' subjects show here.")
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(subjects.prefix(16), id: \.self) { name in
                                PinChip(title: name, tint: LibraryLook.tint(name, table: table),
                                        selected: ReportLibrary.same(name, report.subject),
                                        action: { model.pinReport(report.id, subject: name) })
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            HStack(spacing: 8) {
                AgentCaption(text: "Assignment")
                    .frame(width: 74, alignment: .leading)
                if listed.isEmpty {
                    ReportPinNote(text: "Assignments you still have to hand in show here.")
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(listed.prefix(16)) { item in
                                PinChip(title: item.title, selected: item.id == report.assignment,
                                        action: { model.pinReport(report.id, assignment: item.id) })
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
    }

    static func listed(_ assignments: [Assignment], with pinned: Assignment?) -> [Assignment] {
        let named = assignments.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let pinned = pinned, !named.contains(where: { $0.id == pinned.id }) else { return named }
        return [pinned] + named
    }
}

struct ReportPinNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
    }
}

/// The files a report's agent saved, to open with a click.
struct ReportFileChips: View {
    @ObservedObject var model: NotchModel
    let part: ReportPart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AgentCaption(text: part.files.count == 1 ? "File it saved" : "Files it saved")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(part.files.suffix(12), id: \.self) { file in
                        SmallPill(title: AgentFiles.shortName(file), symbol: AgentFiles.symbol(for: file),
                                  action: { model.onOpenReportFile?(part.folder, file) })
                            .help(AgentFiles.opensDirectly(file) ? "Open \(file)" : "Show \(file) in Finder")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: On an assignment

/// The reports pinned to an assignment: its research, and anything else you've pinned to it.
struct AssignmentReports: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: ReportsStore
    let item: Assignment

    var body: some View {
        let pinned = store.library.pinned(to: item.id)

        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(pinned.count == 1 ? "Report" : "Reports")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(pinned.prefix(8)) { report in
                            SmallPill(title: report.name, symbol: LibraryLook.symbol(report), action: { model.showReport(report.id) })
                                .help("Open this report in the Library: \(report.preview)")
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}
