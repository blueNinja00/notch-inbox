import Foundation
#if canImport(Combine)
import Combine
#endif

/// A note: plain text. Its first line is its title.
struct Note: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var updated: Date

    var title: String {
        lines.first ?? "New note"
    }

    /// The line after the title, for lists and the primary menu.
    var preview: String {
        lines.dropFirst().first ?? ""
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Your notes, newest first, kept in a file only you can read:
/// ~/Library/Application Support/Notch Inbox/Notes.json. They never leave this Mac.
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Notch Inbox", isDirectory: true)
            .appendingPathComponent("Notes.json")
    }

    init(url: URL = NotesStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode([Note].self, from: data) {
            notes = saved.sorted { $0.updated > $1.updated }
        }
    }

    func note(_ id: UUID?) -> Note? {
        guard let id = id else { return nil }
        return notes.first { $0.id == id }
    }

    /// A blank note at the top of the list.
    @discardableResult
    func add(now: Date = Date()) -> Note {
        let note = Note(id: UUID(), text: "", updated: now)
        notes.insert(note, at: 0)
        saveSoon()
        return note
    }

    /// Saves what you typed; the note moves to the top.
    func update(_ id: UUID, text: String, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        var note = notes.remove(at: index)
        note.text = text
        note.updated = now
        notes.insert(note, at: 0)
        saveSoon()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        saveSoon()
    }

    /// Clears away blank notes you started and left, apart from the one in front of you.
    func removeEmpty(except keep: UUID?) {
        let before = notes.count
        notes.removeAll { $0.isEmpty && $0.id != keep }
        if notes.count != before {
            saveSoon()
        }
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Writes the notes to disk straight away (also on quit).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notes.filter { !$0.isEmpty }) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Notch Inbox: couldn't save notes: \(error.localizedDescription)")
        }
    }
}
