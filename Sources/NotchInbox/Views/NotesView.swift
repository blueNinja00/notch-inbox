import SwiftUI

/// Notes: a list on the left and the note you're writing on the right. The expand button
/// (or dragging the corner) makes it bigger. Everything saves as you type.
struct NotesView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: NotesStore
    let expanded: Bool
    @FocusState private var writing: Bool

    init(model: NotchModel, store: NotesStore, expanded: Bool) {
        self.model = model
        self.store = store
        self.expanded = expanded
    }

    var body: some View {
        let size = model.size(expanded ? .detail : .lanes)
        let current = store.note(model.selectedNoteID)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "note.text", title: "Notes") {
                    EmptyView()
                }
            } trailing: {
                HStack(spacing: 2) {
                    IconButton(symbol: "square.and.pencil", label: "New note", action: {
                        model.newNote()
                        writing = true
                    })
                    IconButton(symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? "Make notes smaller" : "Expand notes",
                               action: { expanded ? model.back() : model.expandNotes() })
                    IconButton(symbol: "slider.horizontal.3", label: "Menu: updates, Gmail link, Quit",
                               action: { model.showAppMenu() })
                }
                .padding(.trailing, 4)
            }

            if store.notes.isEmpty {
                VStack(spacing: 10) {
                    Text("No notes yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Button(action: {
                        model.newNote()
                        writing = true
                    }) {
                        Text("New Note")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.text))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    NotesList(model: model, store: store)
                        .frame(width: expanded ? 250 : 200)

                    if let note = current {
                        TextEditor(text: Binding(
                            get: { store.note(note.id)?.text ?? "" },
                            set: { store.update(note.id, text: $0) }
                        ))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.body)
                        .scrollContentBackground(.hidden)
                        .focused($writing)
                        .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                        .id(note.id)
                    } else {
                        Text("Pick a note, or start a new one.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

struct NotesList: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: NotesStore

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                ForEach(store.notes) { note in
                    NoteRow(note: note,
                            selected: note.id == model.selectedNoteID,
                            select: { model.selectNote(note.id) },
                            delete: { store.delete(note.id) })
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct NoteRow: View {
    let note: Note
    let selected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(note.preview.isEmpty ? MailTime.label(for: note.updated) : note.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                IconButton(symbol: "trash", label: "Delete note", size: 22, tint: Theme.tertiary, action: delete)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear)))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
