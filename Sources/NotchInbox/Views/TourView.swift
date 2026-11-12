import SwiftUI

/// The tour: what the notch is, then each tool in turn, a page at a time. On the left, what
/// it's for and a few things to know; on the right, the real thing as it looks right now.
/// It opens by itself the first time the app runs, and from Settings → General after that.
struct TourView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant

    var body: some View {
        let size = model.size(model.level)
        let pages = Tour.pages(for: setup)
        let index = min(max(model.tourPage, 0), pages.count - 1)
        let page = pages[index]

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "map", title: "Tour") {
                    Text("\(index + 1) of \(pages.count)")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .padding(.leading, 6)
                }
            } trailing: {
                PillButton(title: "Skip the Tour", action: { model.finishTour() })
                    .help("Close the tour for good. Settings → General can show it again.")
                    .padding(.trailing, 6)
            }

            HStack(spacing: 10) {
                TourCard(model: model, page: page)
                TourPreview(model: model, settings: settings, assistant: assistant, kind: page.kind)
                    .frame(width: min(380, size.width * 0.38))
            }
            .id(page.id)
            .transition(.opacity)
            .padding(.top, 6)
            .frame(maxHeight: .infinity)

            TourFooter(model: model, pages: pages, index: index)
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: index)
    }

    /// How the app is set up, for the tour's wording.
    private var setup: Tour.Setup {
        Tour.Setup(gmailLinked: !model.isSample,
                   assistantName: assistant.engine.name,
                   assistantIsClaude: assistant.engine.isClaude,
                   assistantReady: assistant.status.isReady,
                   mailTab: model.minimised,
                   extrasOn: settings.showsExtras,
                   inboxes: model.accounts.count,
                   inboxesToAdd: model.spareInboxes.count)
    }
}

/// A page's words: its name, what it's for, a few things to know, and a button to go and
/// try it.
struct TourCard: View {
    @ObservedObject var model: NotchModel
    let page: TourPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Theme.accent))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(page.title)
                                .font(.system(size: 23, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(page.summary)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.points) { point in
                            TourPointRow(point: point)
                        }
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 12, trailing: 20))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)

            if let action = page.action {
                HStack(spacing: 10) {
                    PillButton(title: action.title, action: { model.tryFromTour(action.target) })
                    Text("The tour waits for you: a Tour button at the top left brings you back.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 8, leading: 20, bottom: 18, trailing: 20))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

/// One thing to know, with its symbol.
struct TourPointRow: View {
    let point: TourPage.Point

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: point.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.raised))
            Text(point.text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

/// The right-hand side of a page: the real tile (or row, or themes) the page is about, as
/// it looks right now. It's only for looking at, apart from the themes, which you can try.
struct TourPreview: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant
    let kind: TourPage.Kind

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            picture
            if let caption = TourPreview.caption(kind) {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lane))
    }

    @ViewBuilder
    private var picture: some View {
        switch kind {
        case .welcome:
            TourNotchPicture()
        case .mail:
            MailToolTile(model: model)
                .frame(height: 190)
                .allowsHitTesting(false)
        case .planner:
            if let planner = model.plannerStore, let timetable = model.timetableStore {
                PlannerToolTile(model: model, store: planner, timetable: timetable)
                    .frame(height: 132)
                    .allowsHitTesting(false)
            }
        case .timetable:
            if let timetable = model.timetableStore {
                TimetableToolTile(model: model, store: timetable)
                    .frame(height: 132)
                    .allowsHitTesting(false)
            }
        case .notes:
            if let notes = model.notesStore {
                NotesToolTile(model: model, store: notes)
                    .frame(height: 120)
                    .allowsHitTesting(false)
            }
            if let bookmarks = model.bookmarksStore {
                BookmarksToolTile(model: model, store: bookmarks)
                    .frame(height: 120)
                    .allowsHitTesting(false)
            }
        case .assistant:
            AssistantToolTile(model: model, assistant: assistant)
                .frame(height: 132)
                .allowsHitTesting(false)
        case .extras:
            TourExtras(model: model, settings: settings)
        case .looks:
            TourThemes(settings: settings)
        case .privacy:
            TourBadge(symbol: "lock.shield.fill", title: "Kept on this Mac", detail: "Mail · Notes · Timetable · Planner")
        case .done:
            TourBadge(symbol: "checkmark.seal.fill", title: "That's the tour", detail: "Hover the notch whenever you need it.")
        }
    }

    /// What's under the picture.
    static func caption(_ kind: TourPage.Kind) -> String? {
        switch kind {
        case .welcome: return "The notch, open: a tile for each tool."
        case .mail, .planner, .timetable, .notes, .assistant: return "Its tile on the primary menu, as it is right now."
        case .extras: return "The extras, as they are right now."
        case .looks: return "Click a theme to try it."
        case .privacy, .done: return nil
        }
    }
}

/// A small drawing of the top of the screen with the notch open: the menu bar, the black
/// panel hanging from it, a tile for each tool, and the pointer that opened it.
struct TourNotchPicture: View {
    private static let tools = ["envelope.fill", "checklist", "calendar", "note.text", "sparkles"]

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 12, style: .continuous)

        ZStack(alignment: .top) {
            // The desktop, with the menu bar across its top.
            screen.fill(Theme.raised)
            Rectangle()
                .fill(Theme.hover)
                .frame(height: 12)
            // The notch, open.
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(TourNotchPicture.tools, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface))
                    }
                }
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.surface)
                            .frame(height: 10)
                    }
                }
            }
            .padding(EdgeInsets(top: 16, leading: 12, bottom: 8, trailing: 12))
            .frame(width: 244)
            .background(NotchShape(bottomRadius: 12, shoulder: 5).fill(Color.black))
            // The pointer, on the notch.
            Image(systemName: "cursorarrow")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.6), radius: 2)
                .offset(x: 30, y: 4)
        }
        .frame(height: 150)
        .clipShape(screen)
        .overlay(screen.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The extras that are switched on, stacked up as they look on the primary menu.
struct TourExtras: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            if settings.showsNowPlaying {
                NowPlayingChip(model: model, watcher: NowPlayingWatcher.shared)
                    .frame(height: 40)
            }
            if settings.showsFocus {
                FocusChip(model: model, timer: FocusTimer.shared)
                    .frame(height: 40)
            }
            if settings.keepsClipboard {
                ClipboardChip(model: model, watcher: ClipboardWatcher.shared)
                    .frame(height: 40)
            }
            if settings.showsShelf, let shelf = model.shelfStore {
                ShelfChip(model: model, store: shelf)
                    .frame(height: 40)
            }
            if !settings.showsExtras {
                TourBadge(symbol: "tray.full", title: "All switched off", detail: "Settings → Extras turns them on.")
            }
        }
        .allowsHitTesting(false)
    }
}

/// The themes, to click and try on the spot.
struct TourThemes: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
            ForEach(ThemeChoice.presets) { theme in
                TourThemeButton(theme: theme, selected: settings.theme == theme, choose: { settings.theme = theme })
            }
        }
    }
}

/// One theme to try: its picture, and its name underneath.
struct TourThemeButton: View {
    let theme: ThemeChoice
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        Button(action: choose) {
            VStack(spacing: 5) {
                ThemePicture(palette: theme.palette)
                    .frame(height: 46)
                    .overlay(shape.strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
                Text(theme.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Theme.text : Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Try \(theme.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A big symbol with a line or two under it, for pages with nothing live to show.
struct TourBadge: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Under the page: a dot per page to jump with, then Back and Next.
struct TourFooter: View {
    @ObservedObject var model: NotchModel
    let pages: [TourPage]
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(pages.enumerated()), id: \.offset) { number, page in
                    Button(action: { model.tourPage = number }) {
                        Capsule()
                            .fill(number == index ? Theme.accent : Theme.raised)
                            .frame(width: number == index ? 20 : 8, height: 8)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(page.title)
                    .accessibilityLabel(Text("Page \(number + 1): \(page.title)"))
                }
            }
            .padding(.leading, 6)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                KeyCap(text: "←")
                KeyCap(text: "→")
                Text("turn the pages")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            .padding(.trailing, 4)

            if index > 0 {
                PillButton(title: "Back", action: { model.tourBack() })
            }
            PillButton(title: index >= pages.count - 1 ? "Done" : "Next", prominent: true, action: { model.tourNext() })
        }
        .frame(height: 28)
    }
}

/// A small accent-coloured button that opens the tour, or goes back to it.
struct TourChip: View {
    let title: String
    let symbol: String
    let hint: String
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Theme.accent.opacity(hovering ? 1 : 0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(hint)
        .onHover { hovering = $0 }
    }
}
