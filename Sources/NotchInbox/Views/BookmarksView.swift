import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bookmarks: the links you use, to open with a click. Add one by typing or pasting it, or
/// by dragging a link from your browser. The pencil on a bookmark edits it at the side.
struct BookmarksView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore

    var body: some View {
        let size = model.size(.lanes)
        let shown = store.bookmarks(in: model.bookmarkGroup)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "bookmark.fill", title: "Bookmarks") {
                    if !store.bookmarks.isEmpty {
                        CountPill(count: store.bookmarks.count)
                            .padding(.leading, 6)
                    }
                }
            } trailing: {
                SettingsButton(model: model)
                    .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    BookmarkAddField(model: model)
                    if !store.groups.isEmpty {
                        BookmarkGroups(model: model, groups: store.groups)
                    }
                    if shown.isEmpty {
                        BookmarksEmpty(anySaved: !store.bookmarks.isEmpty)
                    } else {
                        BookmarkGrid(model: model, store: store, bookmarks: shown)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                .onDrop(of: BookmarkDrop.types, isTargeted: nil) { providers in
                    BookmarkDrop.take(providers, into: model)
                }

                if let id = model.bookmarkEdit {
                    BookmarkEditor(model: model, store: store, bookmarkID: id)
                        .id(id)
                        .frame(width: 250)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 6)
            .animation(Theme.spring, value: model.bookmarkEdit)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// What a bookmark looks like: its letter on its site's colour.
struct BookmarkBadge: View {
    let bookmark: Bookmark
    var size: CGFloat = 30

    var body: some View {
        Text(BookmarkText.letter(for: bookmark.title))
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.78))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.subject(BookmarkText.tint(for: bookmark.url))))
            .accessibilityHidden(true)
    }
}

/// The box that adds a bookmark: type or paste a link, with a name before it if you like.
struct BookmarkAddField: View {
    @ObservedObject var model: NotchModel
    @State private var typed = ""
    @State private var refused = false
    @FocusState private var typing: Bool

    init(model: NotchModel) {
        self.model = model
    }

    var body: some View {
        let parsed = BookmarkText.parse(typed)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                TextField("Add a bookmark: Desmos desmos.com", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .focused($typing)
                    .onSubmit(add)
                    .onChange(of: typed) { _ in refused = false }
                SmallPill(title: "Paste", symbol: "doc.on.clipboard", action: paste)
                    .help("Add the link that's on your clipboard")
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
            Text(hint(parsed))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(refused ? Theme.warning : Theme.tertiary)
                .lineLimit(1)
                .padding(.leading, 10)
        }
    }

    private func hint(_ parsed: BookmarkText.Parsed?) -> String {
        if refused {
            return "There's no web address in that."
        }
        if let parsed = parsed {
            return "\(parsed.title) · \(BookmarkText.site(of: parsed.url)) · press Return to add"
        }
        return "Type or paste a link, with a name before it if you like. Or drag a link here from your browser."
    }

    private func add() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.addBookmark(typed: text) {
            typed = ""
        } else if !text.isEmpty {
            refused = true
        }
        typing = true
    }

    /// Adds the link on the clipboard. The clipboard is only read when you click Paste.
    private func paste() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        refused = !model.addBookmark(typed: text)
    }
}

/// The groups, as chips to filter by.
struct BookmarkGroups: View {
    @ObservedObject var model: NotchModel
    let groups: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                BookmarkGroupChip(title: "All", selected: model.bookmarkGroup == nil, choose: { model.bookmarkGroup = nil })
                ForEach(groups, id: \.self) { group in
                    BookmarkGroupChip(title: group,
                                      selected: model.bookmarkGroup?.caseInsensitiveCompare(group) == .orderedSame,
                                      choose: { model.bookmarkGroup = group })
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct BookmarkGroupChip: View {
    let title: String
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.onAccent : Theme.text2)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(selected ? Theme.accent : (hovering ? Theme.hover : Theme.raised)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Nothing to show: no bookmarks yet, or none in this group.
struct BookmarksEmpty: View {
    let anySaved: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bookmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text(anySaved ? "Nothing in this group" : "No bookmarks yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text(anySaved ? "Pick another group, or add a link above." : "Add the pages you open every day: your school portal, Classroom, a textbook.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bookmarks, as cards to click.
struct BookmarkGrid: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore
    let bookmarks: [Bookmark]

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(model: model, store: store, bookmark: bookmark)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// One bookmark: click it to open the page; the pencil (or a right-click) edits it.
struct BookmarkCard: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore
    let bookmark: Bookmark
    @State var hovering = false

    var body: some View {
        let editing = model.bookmarkEdit == bookmark.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        HStack(spacing: 2) {
            Button(action: { model.openBookmark(bookmark) }) {
                HStack(spacing: 9) {
                    BookmarkBadge(bookmark: bookmark)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bookmark.title.isEmpty ? bookmark.site : bookmark.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(bookmark.site)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(bookmark.url)")

            if hovering || editing {
                IconButton(symbol: "pencil", label: "Edit this bookmark", size: 24,
                           tint: editing ? Theme.text : Theme.secondary,
                           action: { model.editBookmark(bookmark.id) })
            }
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 6))
        .background(shape.fill(editing ? Theme.raised : (hovering ? Theme.hover : Theme.lane)))
        .overlay(shape.strokeBorder(Color.white.opacity(editing ? 0.18 : 0), lineWidth: 1))
        .onHover { hovering = $0 }
        .contextMenu { BookmarkMenu(model: model, store: store, bookmark: bookmark) }
    }
}

/// A bookmark's right-click menu.
struct BookmarkMenu: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore
    let bookmark: Bookmark

    var body: some View {
        Button("Open") { model.openBookmark(bookmark) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.url, forType: .string)
        }
        Button("Edit…") { model.editBookmark(bookmark.id) }
        Divider()
        Button("Move Earlier") { store.move(bookmark.id, by: -1, in: model.bookmarkGroup) }
            .disabled(!store.canMove(bookmark.id, by: -1, in: model.bookmarkGroup))
        Button("Move Later") { store.move(bookmark.id, by: 1, in: model.bookmarkGroup) }
            .disabled(!store.canMove(bookmark.id, by: 1, in: model.bookmarkGroup))
        Divider()
        Button("Delete") { model.removeBookmark(bookmark.id) }
    }
}

/// The side panel that edits a bookmark. Changes save as you type.
struct BookmarkEditor: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore
    let bookmarkID: UUID
    /// The link as typed: it's only saved while it's a web address.
    @State private var link: String
    @FocusState private var typingName: Bool

    init(model: NotchModel, store: BookmarksStore, bookmarkID: UUID) {
        self.model = model
        self.store = store
        self.bookmarkID = bookmarkID
        _link = State(initialValue: store.bookmark(bookmarkID)?.url ?? "")
    }

    var body: some View {
        let bookmark = store.bookmark(bookmarkID)
        let linkWorks = BookmarkText.address(from: link) != nil

        VStack(alignment: .leading, spacing: 9) {
            EditorHeader(title: "Bookmark", detail: bookmark.map { $0.site } ?? "", close: { model.bookmarkEdit = nil })
            if let bookmark = bookmark {
                EditorField(label: "Name") {
                    TextField("e.g. Maths textbook", text: binding(\.title))
                        .focused($typingName)
                }
                EditorField(label: "Link") {
                    TextField("https://…", text: $link)
                        .onChange(of: link) { typed in
                            // Half-typed links aren't saved; the last one that worked stays.
                            if BookmarkText.address(from: typed) != nil {
                                change { $0.url = typed }
                            }
                        }
                }
                if !linkWorks {
                    Text("That isn't a web address yet. The bookmark keeps its old link until it is.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                EditorField(label: "Group (optional)") {
                    TextField("e.g. Maths", text: binding(\.group))
                }
                BookmarkGroupPicks(groups: store.groups, current: bookmark.group, pick: { name in change { $0.group = name } })
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    PillButton(title: "Delete", action: { model.removeBookmark(bookmarkID) })
                    Spacer(minLength: 0)
                    PillButton(title: "Open", action: { model.openBookmark(bookmark) })
                    PillButton(title: "Done", prominent: true, action: { model.bookmarkEdit = nil })
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func change(_ edit: (inout Bookmark) -> Void) {
        guard var bookmark = store.bookmark(bookmarkID) else { return }
        edit(&bookmark)
        store.update(bookmark)
    }

    private func binding(_ part: WritableKeyPath<Bookmark, String>) -> Binding<String> {
        Binding(
            get: { store.bookmark(bookmarkID)?[keyPath: part] ?? "" },
            set: { typed in change { $0[keyPath: part] = typed } }
        )
    }
}

/// The groups you already have, to file a bookmark under with a click.
struct BookmarkGroupPicks: View {
    let groups: [String]
    let current: String
    let pick: (String) -> Void

    var body: some View {
        let others = groups.filter { $0.caseInsensitiveCompare(current.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame }

        if !others.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(others.prefix(8), id: \.self) { group in
                        BookmarkGroupChip(title: group, selected: false, choose: { pick(group) })
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: Dropping links

/// Takes a link dragged from a browser (or some text with a link in it) as a new bookmark.
enum BookmarkDrop {
    static let types: [UTType] = [.url, .plainText]

    @discardableResult
    static func take(_ providers: [NSItemProvider], into model: NotchModel) -> Bool {
        // A file isn't a bookmark: it goes on the shelf, if the shelf is on.
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            guard AppSettings.shared.showsShelf, let shelf = model.shelfStore else { return false }
            return ShelfDrop.take(providers, into: shelf)
        }
        var any = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                any = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, !url.isFileURL else { return }
                    DispatchQueue.main.async {
                        model.addBookmark(typed: url.absoluteString)
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                any = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text = text else { return }
                    DispatchQueue.main.async {
                        model.addBookmark(typed: text)
                    }
                }
            }
        }
        return any
    }
}

// MARK: On the primary menu

/// Bookmarks on the primary menu: the first few, each a click away. Click anywhere else
/// on the tile for all of them.
struct BookmarksToolTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BookmarksStore
    @State var hovering = false

    var body: some View {
        let bookmarks = store.bookmarks

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ToolIcon(symbol: "bookmark.fill")
                Text("Bookmarks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No bookmarks yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Text("Click to add one")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { list in
                    let rows = max(1, Int((list.size.height + 3) / 25))
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(bookmarks.prefix(rows)) { bookmark in
                            BookmarkLine(model: model, bookmark: bookmark)
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
        .onTapGesture { model.openBookmarks() }
        .onHover { hovering = $0 }
        .onDrop(of: BookmarkDrop.types, isTargeted: nil) { providers in
            model.pinHome()
            return BookmarkDrop.take(providers, into: model)
        }
        .help("Open your bookmarks")
    }
}

/// One bookmark on the tile: click to open the page.
struct BookmarkLine: View {
    @ObservedObject var model: NotchModel
    let bookmark: Bookmark
    @State var hovering = false

    var body: some View {
        Button(action: { model.openBookmark(bookmark) }) {
            HStack(spacing: 7) {
                BookmarkBadge(bookmark: bookmark, size: 16)
                Text(bookmark.title.isEmpty ? bookmark.site : bookmark.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Theme.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(bookmark.url)")
    }
}
