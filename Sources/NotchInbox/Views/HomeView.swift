import SwiftUI

/// The primary menu: one tile per tool (Mail, Timetable, Notes, Assistant). Hovering the
/// notch shows it; clicking a tile opens that tool.
struct HomeView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let size = model.size(.peek)

        VStack(spacing: 0) {
            TopRow(metrics: metrics) {
                TodayLabel()
                    .padding(.leading, 6)
            } trailing: {
                HomeActions(model: model)
            }

            // Short: the tools in a row. Dragged taller: Mail on the left with your latest
            // emails; the timetable, notes and assistant on the right.
            GeometryReader { area in
                if area.size.height > 200 {
                    HStack(spacing: 8) {
                        MailToolTile(model: model)
                        VStack(spacing: 8) {
                            if let timetable = model.timetableStore {
                                TimetableToolTile(model: model, store: timetable)
                            }
                            HStack(spacing: 8) {
                                if let store = model.notesStore {
                                    NotesToolTile(model: model, store: store)
                                }
                                AssistantToolTile(model: model, assistant: Assistant.shared)
                            }
                        }
                        .frame(width: min(max(area.size.width * 0.42, 320), 520))
                    }
                } else {
                    HStack(spacing: 8) {
                        MailToolTile(model: model)
                        if let timetable = model.timetableStore {
                            TimetableToolTile(model: model, store: timetable)
                                .frame(width: min(max(area.size.width * 0.22, 172), 300))
                        }
                        if let store = model.notesStore {
                            NotesToolTile(model: model, store: store)
                                .frame(width: min(max(area.size.width * 0.19, 140), 260))
                        }
                        AssistantToolTile(model: model, assistant: Assistant.shared)
                            .frame(width: min(max(area.size.width * 0.19, 140), 260))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.pinHome() }
    }
}

/// Day and time at the top left of the primary menu.
struct TodayLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Text(TodayLabel.day.string(from: context.date))
                    .foregroundStyle(Theme.text)
                Text(TodayLabel.time.string(from: context.date))
                    .foregroundStyle(Theme.tertiary)
            }
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

/// The Update button (when there is one) and Settings, at the top right of the primary menu.
struct HomeActions: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 2) {
            if let build = model.pendingUpdate {
                UpdateButton(build: build, action: { model.installUpdate() })
                    .padding(.trailing, 4)
            } else if let note = model.updateNote {
                UpdateNote(text: note)
                    .padding(.trailing, 4)
            }
            SettingsButton(model: model)
        }
        .padding(.trailing, 4)
    }
}

/// Mail: total unread and each inbox's count, then your newest emails, as many as fit.
/// Click an email to open it, or anywhere else on the tile to open your inboxes.
struct MailToolTile: View {
    @ObservedObject var model: NotchModel
    @State var hovering = false

    var body: some View {
        let shown = Set(model.accounts.map { $0.id })
        let recent = model.messages
            .filter { shown.contains($0.accountID) }
            .sorted { $0.date > $1.date }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ToolIcon(symbol: "envelope.fill")
                Text("Mail")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if model.isSample {
                    SampleTag()
                }
                Spacer(minLength: 4)
                Text(UnreadText.format(model.totalUnread))
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }

            // Each inbox's unread count: with names when there's room.
            ViewThatFits(in: .horizontal) {
                accountCounts(named: true)
                accountCounts(named: false)
            }

            GeometryReader { list in
                let rows = max(1, Int((list.size.height + 2) / 24))
                VStack(alignment: .leading, spacing: 2) {
                    if recent.isEmpty {
                        Text("Nothing unread")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                    }
                    ForEach(recent.prefix(rows)) { message in
                        RecentEmailRow(model: model, message: message, senderWidth: min(180, list.size.width * 0.3))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { model.openLanes() }
        .onHover { hovering = $0 }
        .help("Open Mail")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Mail, \(model.totalUnread) unread"))
    }

    private func accountCounts(named: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(model.accounts) { account in
                HStack(spacing: 5) {
                    Circle()
                        .fill(account.color)
                        .frame(width: 6, height: 6)
                    Text(named
                         ? "\(account.name) \(UnreadText.format(model.unreadCount(account.id)))"
                         : UnreadText.format(model.unreadCount(account.id)))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .help(account.name)
            }
        }
    }
}

/// One email in the Mail tile: whose inbox, who from, what about, when. Click to open it.
struct RecentEmailRow: View {
    @ObservedObject var model: NotchModel
    let message: MailMessage
    let senderWidth: CGFloat
    @State var hovering = false

    var body: some View {
        Button(action: { model.open(accountID: message.accountID, messageID: message.id) }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.account(message.accountID)?.color ?? Theme.tertiary)
                    .frame(width: 6, height: 6)
                Text(message.sender)
                    .font(.system(size: 12, weight: message.isUnread ? .semibold : .regular))
                    .foregroundStyle(message.isUnread ? Theme.text2 : Theme.readText)
                    .frame(width: senderWidth, alignment: .leading)
                Text(message.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(message.isUnread ? Theme.secondary : Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(MailTime.label(for: message.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Theme.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Notes: how many, then your latest notes, as many as fit. Click one to open it.
struct NotesToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: NotesStore
    @State var hovering = false

    var body: some View {
        let written = store.notes.filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ToolIcon(symbol: "note.text")
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 4)
                if !written.isEmpty {
                    Text("\(written.count)")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
            }

            if written.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No notes yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Click to write one")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { list in
                    let rows = max(1, Int((list.size.height + 4) / 38))
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(written.prefix(rows)) { note in
                            Button(action: {
                                model.selectedNoteID = note.id
                                model.openNotes()
                            }) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text2)
                                    Text(note.preview.isEmpty ? MailTime.label(for: note.updated) : note.preview)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.tertiary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if written.isEmpty {
                model.newNote()
            } else {
                model.openNotes()
            }
        }
        .onHover { hovering = $0 }
        .help("Open Notes")
    }
}

/// A tool's round icon.
struct ToolIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Theme.raised))
    }
}
