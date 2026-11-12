import AppKit
import SwiftUI

/// Settings, inside the notch: sections down the left, the chosen one on the right.
/// Everything that used to be in the drop-down menu lives here.
struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant

    var body: some View {
        let size = model.size(model.level)

        VStack(spacing: 0) {
            TopRow(metrics: model.metrics) {
                ToolTabs(model: model, symbol: "gearshape", title: "Settings") {
                    EmptyView()
                }
            } trailing: {
                HStack(spacing: 2) {
                    if let note = model.updateNote {
                        UpdateNote(text: note)
                            .padding(.trailing, 4)
                    }
                    IconButton(symbol: "xmark", label: "Close Settings (Esc)", action: { model.goHome() })
                }
                .padding(.trailing, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                SettingsSidebar(model: model, settings: settings)
                    .frame(width: 172)

                ScrollViewReader { page in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        switch model.settingsSection {
                        case .general:
                            GeneralSettings(model: model, settings: settings)
                        case .accounts:
                            AccountSettings(model: model, settings: settings)
                        case .assistant:
                            AssistantSettings(assistant: assistant, settings: settings)
                        case .timetable:
                            if let store = model.timetableStore {
                                TimetableSettings(model: model, store: store)
                            }
                        case .planner:
                            if let store = model.plannerStore {
                                PlannerSettings(model: model, settings: settings, assistant: assistant, store: store)
                            }
                        case .extras:
                            ExtrasSettings(model: model, settings: settings, timer: FocusTimer.shared)
                        case .gmail:
                            GmailLinkSettings(settings: settings)
                        case .updates:
                            UpdateSettings(settings: settings)
                        }
                    }
                    .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(model.settingsSection)
                .onAppear {
                    // Changing your own theme redraws everything: come back to its editor.
                    guard model.settingsSection == .general, settings.theme == .custom, settings.customThemeJustEdited else { return }
                    DispatchQueue.main.async {
                        page.scrollTo(SettingsView.themeEditorID, anchor: .center)
                    }
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            }
            .padding(.top, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { assistant.checkSetup() }
    }

    /// Where Settings scrolls back to after a change to your own theme.
    static let themeEditorID = "own-theme-editor"
}

// MARK: Sidebar

struct SettingsSidebar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                SidebarRow(section: section,
                           selected: model.settingsSection == section,
                           flagged: flagged(section),
                           choose: { model.settingsSection = section })
            }
            Spacer(minLength: 8)
            QuitRow(action: { settings.quit() })
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A dot beside a section that needs a look: an update to install, or a Gmail link that stopped.
    private func flagged(_ section: SettingsSection) -> Bool {
        switch section {
        case .updates:
            if case .available = settings.update { return true }
            return false
        case .gmail:
            return settings.link.lastSync != nil && !settings.link.isHealthy
        default:
            return false
        }
    }
}

struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let flagged: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if flagged {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuitRow: View {
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text("Quit Notch Inbox")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Theme.text : Theme.tertiary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.surface : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: General

struct GeneralSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Theme",
                        detail: "The colours of everything on the notch. The notch itself stays black, like the camera housing it hangs from.")
        ThemePicker(settings: settings)
        if settings.theme == .custom {
            CustomThemeEditor(settings: settings)
                .id(SettingsView.themeEditorID)
        }
        SettingsDivider()
        HomeMenuSettings(settings: settings)
        SettingsDivider()
        SettingsHeading(title: "Show Notch Inbox as")
        HStack(spacing: 10) {
            ModeCard(symbol: "menubar.rectangle", title: "Notch at the top",
                     detail: "Opens when you hover over the notch. Unread counts sit beside the camera.",
                     selected: !model.minimised, choose: { model.setMinimised(false) })
            ModeCard(symbol: "envelope", title: "Mail tab",
                     detail: "A small tab you can slide along the top of the screen. Click it to open.",
                     selected: model.minimised, choose: { model.setMinimised(true) })
        }

        SettingsDivider()
        GeneralHelp(model: model)
    }
}

/// Panel sizes, the keyboard shortcuts, and the tour to watch again.
struct GeneralHelp: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        SettingsRow(title: "Panel sizes",
                    detail: "Drag the bottom edge or corner of an open panel to resize it. Double-click the corner for its standard size.") {
            PillButton(title: "Reset All Sizes", action: { model.resetAllSizes() })
        }
        SettingsDivider()
        SettingsRow(title: "Keyboard",
                    detail: "Esc goes back a step. In Mail, 1, 2 and 3 open your inboxes, / searches, U marks the open email unread (or read) and O opens it in Gmail.") {
            EmptyView()
        }
        SettingsDivider()
        SettingsRow(title: "Tour",
                    detail: "A minute-long look at what everything does. It opened by itself the first time; this shows it again.") {
            PillButton(title: "Show the Tour", action: { model.openTour(fromStart: true) })
        }
    }
}

/// The themes, as swatches to click: eight ready-made, and one you make yourself.
struct ThemePicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(ThemeChoice.allCases) { theme in
                ThemeSwatch(theme: theme,
                            palette: theme == .custom ? settings.customTheme.palette : theme.palette,
                            selected: settings.theme == theme, choose: { settings.theme = theme })
            }
        }
    }
}

/// Making your own theme: the colour that washes the tiles, how much of it, how bright
/// the tiles are, and the accent. Text stays readable whatever you pick.
struct CustomThemeEditor: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let theme = settings.customTheme

        VStack(alignment: .leading, spacing: 12) {
            ColourRow(title: "Colour", detail: "Washes the tiles and panels.",
                      colours: CustomTheme.swatches, chosen: theme.tint,
                      pick: { colour in settings.customTheme.tint = colour })
            HStack(spacing: 14) {
                HexField(title: "Or a hex code", colour: theme.tint, pick: { colour in settings.customTheme.tint = colour })
                VStack(alignment: .leading, spacing: 4) {
                    CustomThemeLabel(text: "How much colour")
                    ChoiceSegments(options: CustomTheme.Strength.allCases.map {
                        ChoiceSegments<CustomTheme.Strength>.Option(value: $0, title: $0.title, help: "\($0.title) colour in the tiles")
                    }, selected: theme.strength, choose: { settings.customTheme.strength = $0 })
                }
                VStack(alignment: .leading, spacing: 4) {
                    CustomThemeLabel(text: "Tiles")
                    ChoiceSegments(options: CustomTheme.Tiles.allCases.map {
                        ChoiceSegments<CustomTheme.Tiles>.Option(value: $0, title: $0.title, help: "\($0.title) tiles")
                    }, selected: theme.tiles, choose: { settings.customTheme.tiles = $0 })
                }
                Spacer(minLength: 0)
            }
            AccentRow(settings: settings)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
    }
}

struct CustomThemeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
    }
}

/// A row of colours to click.
struct ColourRow: View {
    let title: String
    let detail: String
    let colours: [UInt32]
    let chosen: UInt32?
    let pick: (UInt32) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                CustomThemeLabel(text: title)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(colours, id: \.self) { colour in
                    ColourDot(colour: colour, selected: colour == chosen, choose: { pick(colour) })
                }
            }
        }
    }
}

/// One colour, as a dot to click.
struct ColourDot: View {
    let colour: UInt32
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(Color(hex: colour))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : (hovering ? 0.5 : 0.12)), lineWidth: selected ? 2 : 1))
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(CustomTheme.hex(colour))
        .accessibilityLabel(Text("Colour \(CustomTheme.hex(colour))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Typing an exact colour, like #5E9EFF. It's used when you press Return.
struct HexField: View {
    let title: String
    let colour: UInt32
    let pick: (UInt32) -> Void
    @State private var typed: String
    @State private var refused = false

    init(title: String, colour: UInt32, pick: @escaping (UInt32) -> Void) {
        self.title = title
        self.colour = colour
        self.pick = pick
        _typed = State(initialValue: CustomTheme.hex(colour))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CustomThemeLabel(text: refused ? "Not a colour: try #5E9EFF" : title)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: CustomTheme.colour(fromHex: typed) ?? colour))
                    .frame(width: 12, height: 12)
                TextField("#5E9EFF", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(width: 74)
                    .onSubmit(use)
                    .onChange(of: typed) { _ in refused = false }
            }
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        }
    }

    private func use() {
        if let found = CustomTheme.colour(fromHex: typed) {
            pick(found)
        } else {
            refused = true
        }
    }
}

/// The accent: the colour itself, or another for buttons and whatever's selected.
struct AccentRow: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let theme = settings.customTheme

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                CustomThemeLabel(text: "Accent")
                Text("Buttons, today, and whatever's selected.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 8) {
                SmallPill(title: theme.accent == nil ? "Same as the colour ✓" : "Same as the colour", symbol: "link",
                          action: { settings.customTheme.accent = nil })
                ForEach(CustomTheme.accents, id: \.self) { colour in
                    ColourDot(colour: colour, selected: theme.accent == colour, choose: { settings.customTheme.accent = colour })
                }
            }
        }
    }
}

/// Which tools have a tile on the primary menu, and in what order.
struct HomeMenuSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let menu = settings.homeMenu

        SettingsHeading(title: "Primary menu",
                        detail: "Choose which tools have a tile on the menu the notch opens to, and their order (the arrows). You can also right-click a tile there to move or hide it. Six fit in a row; more go in two rows.")
        VStack(spacing: 0) {
            ForEach(Array(menu.order.enumerated()), id: \.element) { index, tile in
                if index > 0 {
                    SettingsDivider()
                }
                HomeTileSettingRow(settings: settings, tile: tile,
                                   isFirst: index == 0, isLast: index == menu.order.count - 1)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
        if menu != HomeMenu.standard {
            HStack {
                Spacer(minLength: 0)
                PillButton(title: "Back to the Standard Menu", action: { settings.homeMenu = HomeMenu.standard })
            }
        }
    }
}

/// One tool in Settings: its place on the primary menu, and whether it has a tile there.
struct HomeTileSettingRow: View {
    @ObservedObject var settings: AppSettings
    let tile: HomeTile
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let shown = settings.homeMenu.isShown(tile)
        let onlyOne = shown && !settings.homeMenu.canHide(tile)

        HStack(spacing: 10) {
            Image(systemName: tile.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(shown ? Theme.text : Theme.tertiary)
                .frame(width: 22)
            Text(tile.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(shown ? Theme.text2 : Theme.tertiary)
            if !shown {
                Text("Not on the menu")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.up", label: "Move \(tile.title) earlier", size: 22,
                           action: { settings.moveTile(tile, by: -1) })
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)
                IconButton(symbol: "chevron.down", label: "Move \(tile.title) later", size: 22,
                           action: { settings.moveTile(tile, by: 1) })
                    .disabled(isLast)
                    .opacity(isLast ? 0.3 : 1)
            }
            Toggle("", isOn: Binding(get: { settings.homeMenu.isShown(tile) }, set: { settings.setTile(tile, shown: $0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(onlyOne)
                .help(onlyOne ? "The primary menu always keeps one tile." : (shown ? "Take \(tile.title) off the primary menu" : "Put \(tile.title) on the primary menu"))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// One theme: a little picture of it (a tile, two lines of text and a button), and its name.
struct ThemeSwatch: View {
    let theme: ThemeChoice
    let palette: ThemePalette
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button(action: choose) {
            HStack(spacing: 9) {
                ThemePicture(palette: palette)
                    .frame(width: 38, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(theme.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(shape.fill(selected ? Theme.raised : Theme.lane))
            .overlay(shape.strokeBorder(selected ? Theme.accent : Color.white.opacity(hovering ? 0.12 : 0.05), lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(theme.title): \(theme.detail.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A theme in miniature, drawn in its own colours.
struct ThemePicture: View {
    let palette: ThemePalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        ZStack(alignment: .bottomTrailing) {
            shape.fill(Color(hex: palette.surface))
            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(Color(hex: palette.text))
                    .frame(width: 18, height: 3)
                Capsule()
                    .fill(Color(hex: palette.tertiary))
                    .frame(width: 12, height: 3)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Circle()
                .fill(Color(hex: palette.accent))
                .frame(width: 9, height: 9)
                .padding(5)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// One of the two ways to show the app, as a card you click.
struct ModeCard: View {
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accent : Theme.tertiary)
                }
                .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.raised : Theme.lane))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.22 : (hovering ? 0.12 : 0.05)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Mail accounts

struct AccountSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let showing = settings.accounts.filter { $0.inNotch }.count

        SettingsHeading(title: "Mail accounts",
                        detail: "Choose which inboxes show in the notch, up to three side by side, and their order (the arrows). The notch starts with one; switch others on here, or use Add an inbox in Mail. Primary shows Gmail's Primary tab plus Classroom and other mail from Google; Whole inbox shows every tab.")
        if settings.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Gmail accounts linked yet.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                PillButton(title: "Set Up the Gmail Link", prominent: true, action: { model.settingsSection = .gmail })
            }
        } else {
            VStack(spacing: 8) {
                ForEach(Array(settings.accounts.enumerated()), id: \.element.id) { index, account in
                    AccountSettingRow(account: account, settings: settings,
                                      isFirst: index == 0, isLast: index == settings.accounts.count - 1,
                                      isOnly: account.inNotch && showing == 1)
                }
            }
        }
        SettingsDivider()
        MailStorageSettings(settings: settings)
    }
}

/// How much mail the notch keeps on this Mac, and how many whole emails to keep.
struct MailStorageSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsRow(title: "Mail kept on this Mac",
                    detail: settings.storage.summary() + ". The notch keeps every email it has seen (up to 10,000 an account), so you can scroll and search back a long way. Emails are saved in full as they arrive; when there are more than you choose here, the oldest go back to a preview.") {
            ChoiceSegments(options: WholeEmailStore.limits.map { limit in
                ChoiceSegments<Int>.Option(value: limit,
                                           title: limit == 0 ? "All" : AppSettings.Storage.number(limit),
                                           help: limit == 0 ? "Keep every email in full" : "Keep the newest \(AppSettings.Storage.number(limit)) emails in full")
            }, selected: settings.wholeEmailLimit, choose: { settings.wholeEmailLimit = $0 })
        }
        .onAppear { settings.measureStorage() }
        SettingsRow(title: "Earlier mail",
                    detail: "Gmail only tells the notch about new unread mail. This fetches, once, a list of the last 30 days of each inbox (read mail too) by opening Gmail in a background tab in your browser and reading its list. Nothing in Gmail is changed, and the list stays on this Mac."
                        + (settings.historyNote.map { "\n" + $0 } ?? "")) {
            PillButton(title: settings.historyRunning ? "Fetching…" : "Fetch the Last 30 Days", action: { settings.onFetchHistory?() })
                .disabled(settings.historyRunning)
        }
    }
}

struct AccountSettingRow: View {
    let account: AppSettings.Account
    @ObservedObject var settings: AppSettings
    /// Where it is in the list, for the arrows that move it.
    var isFirst = false
    var isLast = false
    /// The only inbox in the notch: the notch always keeps one, so it can't be switched off.
    var isOnly = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(account.hidden ? Theme.tertiary.opacity(0.5) : (account.colorHex.map { Color(hex: $0) } ?? Theme.tertiary))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.id)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(account.hidden ? Theme.tertiary : Theme.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.up", label: "Move earlier in the notch", size: 22,
                           tint: isFirst ? Theme.tertiary.opacity(0.4) : Theme.secondary,
                           action: { settings.moveAccount(account.id, by: -1) })
                    .disabled(isFirst)
                IconButton(symbol: "chevron.down", label: "Move later in the notch", size: 22,
                           tint: isLast ? Theme.tertiary.opacity(0.4) : Theme.secondary,
                           action: { settings.moveAccount(account.id, by: 1) })
                    .disabled(isLast)
            }
            ChoiceSegments(options: [
                ChoiceSegments<InboxChoice>.Option(value: .primary, title: "Primary",
                                      help: "Gmail's Primary tab, plus Classroom and other mail from Google"),
                ChoiceSegments<InboxChoice>.Option(value: .everything, title: "Whole inbox",
                                      help: "Every tab: Primary, Promotions, Social and Updates"),
            ], selected: account.inbox, choose: { settings.chooseInbox($0, for: account.id) })
            .opacity(account.hidden ? 0.5 : 1)
            Toggle("", isOn: Binding(get: { !account.hidden }, set: { settings.setHidden(!$0, for: account.id) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(isOnly)
                .help(switchHelp)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
    }

    private var status: String {
        if account.hidden { return "Not in the notch" }
        if !account.inNotch { return "No room: three show already. Switch one off, or move this up." }
        return "\(UnreadText.format(account.unread)) unread · in the notch"
    }

    private var switchHelp: String {
        if isOnly { return "The notch always keeps one inbox. Add another before taking this one out." }
        return account.hidden ? "Show in the notch" : "Take out of the notch"
    }
}

// MARK: Assistant

struct AssistantSettings: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Who answers")
        VStack(spacing: 6) {
            ForEach(AssistantEngine.allCases, id: \.self) { engine in
                EngineRow(engine: engine, selected: assistant.engine == engine, choose: { assistant.engine = engine })
            }
        }

        if assistant.engine.isClaude {
            SettingsRow(title: "Model", detail: modelDetail) {
                ChoiceSegments(options: ClaudeModel.allCases.map {
                    ChoiceSegments<ClaudeModel>.Option(value: $0, title: $0.title, help: $0.note)
                }, selected: assistant.claudeModel, choose: { assistant.claudeModel = $0 })
            }
        }

        SettingsDivider()
        switch assistant.engine {
        case .claudeCode:
            ClaudeCodeStatus(assistant: assistant)
        case .claudeAPI:
            APIKeyEditor(assistant: assistant)
        case .qwen:
            QwenStatus(assistant: assistant)
        }

        SettingsDivider()
        AssistantReach(assistant: assistant)

        SettingsDivider()
        ChatSettings(assistant: assistant, store: assistant.chats)

        SettingsDivider()
        TypingSettings(assistant: assistant, settings: settings)

        SettingsDivider()
        AgentSettings(assistant: assistant, settings: settings)
    }

    private var modelDetail: String {
        switch assistant.claudeModel {
        case .haiku: return "Haiku answers fastest; good for quick questions."
        case .sonnet: return "Sonnet is quick and capable: the best fit for most things."
        case .opus: return "Opus thinks hardest, but is slower and uses more of your plan."
        }
    }
}

/// What the assistant may see and do: the web, your timetable and planner, your
/// assignments, bookmarks and agents, your emails and notes. Each has its own switch.
struct AssistantReach: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        let claude = assistant.engine.isClaude

        SettingsHeading(title: "What it can see and do",
                        detail: "It only changes anything when you ask it to, and it says what it changed.")
        if assistant.engine == .claudeCode {
            SettingsToggle(title: "Look things up on the web",
                           detail: "It can search the web and read pages before it answers. What it searches for is sent to Anthropic.",
                           isOn: $assistant.usesWeb)
        } else {
            SettingsDetail(text: "Looking things up on the web needs “Claude, with your Claude plan”. \(assistant.engine.name) here answers from what it knows.")
        }
        SettingsToggle(title: "See and change my timetable",
                       detail: claude
                           ? "Ask things like \"add soccer on Tuesdays at 5\". Your timetable is sent to Anthropic with each question."
                           : "Ask things like \"add soccer on Tuesdays at 5\". Your timetable stays on this Mac.",
                       isOn: $assistant.editsTimetable)
        SettingsToggle(title: "See and change my planner",
                       detail: claude
                           ? "Ask things like \"what's due this week?\" or \"add a Maths test on Friday\". Your homework and exams are sent to Anthropic with each question."
                           : "Ask things like \"what's due this week?\" or \"add a Maths test on Friday\". Your homework and exams stay on this Mac.",
                       isOn: $assistant.editsPlanner)
        ForEach(assistant.abilities, id: \.tag) { ability in
            SettingsToggle(title: ability.title,
                           detail: ability.detail + (claude ? " What it sees of them is sent to Anthropic with each question." : " They stay on this Mac."),
                           isOn: Binding(get: { assistant.allows(ability.tag) }, set: { assistant.setAllowed(ability.tag, $0) }))
        }
        SettingsToggle(title: "Share my newest emails and notes",
                       detail: claude
                           ? "The last 30 days of email the notch holds (sender, subject and time of up to 120, and how the newest 25 start), and your latest notes, are sent to Anthropic with each question. Off keeps them on this Mac. Agents never see your mail; the assistant writes what matters into their jobs."
                           : "Qwen sees the last 30 days of email the notch holds (sender, subject and time, and how the newest start), and your latest notes. They stay on this Mac.",
                       isOn: $assistant.sharesContext)
    }
}

/// Your saved chats: where they're kept, and deleting them all.
struct ChatSettings: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var store: ChatsStore
    @State var sure = false

    var body: some View {
        let count = store.book.chats.filter { !$0.isEmpty }.count

        SettingsRow(title: "Your chats", detail: ChatSettings.detail(count: count)) {
            if sure {
                HStack(spacing: 6) {
                    PillButton(title: "Delete All", prominent: true, action: {
                        assistant.clearChats()
                        sure = false
                    })
                    PillButton(title: "Keep", action: { sure = false })
                }
            } else {
                PillButton(title: "Delete All Chats…", action: { sure = true })
                    .disabled(count == 0)
            }
        }
    }
}

extension ChatSettings {
    static func detail(count: Int) -> String {
        let kept = "Chats are kept on this Mac, in a file only you can read, so they're still there after a restart or an update. The newest \(ChatBook.mostChats) are kept, and the list down the side of the assistant switches between them."
        if count == 0 { return kept }
        return kept + (count == 1 ? " There's 1 now." : " There are \(count) now.")
    }
}

/// Typing into your documents: what it does, and the permission macOS wants for it.
struct TypingSettings: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Typing into your documents",
                        detail: "Beside each answer, the keyboard button types it where your cursor is in the app you were in (Pages, Word, Google Docs…), as plain text, replacing anything selected. Use Selection, under the chat, attaches what you've selected there to your next question, so you can ask about it or have it rewritten.")
        AccessibilityStatus(settings: settings,
                            allowed: "macOS lets Notch Inbox type for you",
                            missing: "macOS hasn't allowed Notch Inbox to type for you yet",
                            without: "Until it does, an answer is copied instead, for you to paste with ⌘V, and Use Copied attaches what you've copied yourself.")
        SettingsDetail(text: assistant.engine.isClaude
                       ? "What you attach is sent to Anthropic with your question. Nothing in your documents is read unless you click Use Selection, and your clipboard is put back as it was after typing."
                       : "What you attach stays on this Mac. Nothing in your documents is read unless you click Use Selection, and your clipboard is put back as it was after typing.")
    }
}

/// Whether macOS lets Notch Inbox press keys in other apps (Accessibility, in System
/// Settings), with the buttons that ask for it.
struct AccessibilityStatus: View {
    @ObservedObject var settings: AppSettings
    let allowed: String
    let missing: String
    /// What happens in the meantime.
    let without: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.accessibilityAllowed {
                StatusLine(state: .good, text: allowed)
            } else {
                StatusLine(state: .waiting, text: missing)
                SettingsDetail(text: without + " Click Allow and macOS asks; switch Notch Inbox on under Privacy & Security → Accessibility. macOS treats every update as a new app, so it asks again after each one.")
                HStack(spacing: 8) {
                    PillButton(title: "Allow…", prominent: true, action: { settings.onAskForAccessibility?() })
                    PillButton(title: "Check Again", action: { settings.onCheckAccessibility?() })
                }
            }
        }
        .onAppear { settings.onCheckAccessibility?() }
    }
}

/// Agents: how many work at once, whether they use the web, and which folders they may read.
struct AgentSettings: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var settings: AppSettings

    var body: some View {
        let tools = assistant.engine == .claudeCode

        SettingsHeading(title: "Agents",
                        detail: tools
                            ? "Separate Claudes that you, or the assistant, hand bigger jobs to. Each works in a folder of its own, and can't run commands or see your mail, notes or other files."
                            : "Separate AIs that you, or the assistant, hand bigger jobs to. With \(assistant.engine.title), an agent can only think and write; the web and saved files need “Claude, with your Claude plan”.")
        SettingsRow(title: "Working at once", detail: "The rest wait their turn. More at once uses more of your plan.") {
            ChoiceSegments(options: AgentSettings.options, selected: settings.agentsAtOnce, choose: { settings.agentsAtOnce = $0 })
        }
        if tools {
            SettingsToggle(title: "Let agents use the web",
                           detail: "They can search and read pages, and what they search for is sent to Anthropic. Off, they work from what they know.",
                           isOn: $settings.agentsUseWeb)
        }
        SettingsToggle(title: "Team chat",
                       detail: tools
                           ? "Working agents share a chat: they post what they find, read each other's posts so they don't double up, and can ask the chief of staff. You can post there too, from the top of the agent room. The chief's answers there use a little more of your plan."
                           : "A chat in the agent room where you and the chief of staff can talk. Agents can only join it with “Claude, with your Claude plan”.",
                       isOn: $settings.agentsTeamChat)
        SettingsToggle(title: "Chime when an agent finishes",
                       detail: "A sound when a report is ready, or when an agent couldn't finish.",
                       isOn: $settings.agentsChime)
        if tools {
            AgentFolderSettings(settings: settings)
            SettingsRow(title: "What agents have saved",
                        detail: "Each agent's files are kept in its own folder, inside “Notch Agents” in your home folder, until you delete them.") {
                PillButton(title: "Show in Finder", action: { settings.onShowAgentsFolder?() })
            }
        }
    }
}

extension AgentSettings {
    /// One to four agents at a time.
    static let options: [ChoiceSegments<Int>.Option] = AppSettings.agentChoices.map { count in
        ChoiceSegments<Int>.Option(value: count, title: "\(count)",
                                   help: count == 1 ? "One agent at a time" : "Up to \(count) agents at a time")
    }
}

/// The folders of yours that agents may read.
struct AgentFolderSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsRow(title: "Folders agents may read",
                    detail: "For a job that needs your own files, like notes to revise from. Agents can read these folders and can't change them. An agent that also uses the web could be tricked by a page into passing on what it read, so only share folders with nothing private in them.") {
            PillButton(title: "Add a Folder…", action: { settings.onChooseAgentFolder?() })
        }
        if !settings.agentReadFolders.isEmpty {
            VStack(spacing: 4) {
                ForEach(settings.agentReadFolders, id: \.self) { folder in
                    AgentFolderRow(path: folder, remove: { settings.removeAgentFolder(folder) })
                }
            }
        }
        if let problem = settings.agentFolderProblem {
            Text(problem)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AgentFolderRow: View {
    let path: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text(AgentFolders.shown(path, home: NSHomeDirectory()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
            Spacer(minLength: 6)
            IconButton(symbol: "xmark", label: "Stop sharing this folder with agents", size: 24, action: remove)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lane))
    }
}

/// One way for the assistant to answer, as a row you click.
struct EngineRow: View {
    let engine: AssistantEngine
    let selected: Bool
    let choose: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Image(systemName: engine.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(selected ? Theme.hover : Theme.raised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(engine.caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.raised : Theme.lane))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.22 : (hovering ? 0.12 : 0.05)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ClaudeCodeStatus: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        switch assistant.status {
        case .checking:
            StatusLine(state: .waiting, text: "Looking for Claude Code on this Mac…")
        case .noClaudeCode:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(state: .problem, text: "Claude Code isn't installed on this Mac")
                SettingsDetail(text: "Install it in Terminal with this command, then type claude, press Return and sign in to your Claude account.")
                CommandBox(command: ClaudeSetup.installCommand)
                PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                StatusLine(state: .good, text: "Using Claude Code at \(shortPath)")
                SettingsDetail(text: "If Claude says it isn't signed in, open Terminal, type claude, press Return and sign in.")
            }
        }
    }

    private var shortPath: String {
        let path = assistant.claudePath ?? "claude"
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }
}

struct APIKeyEditor: View {
    @ObservedObject var assistant: Assistant
    @State var typed = ""
    @State var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = assistant.apiKeyHint {
                HStack(spacing: 8) {
                    StatusLine(state: .good, text: "API key saved: \(hint)")
                    Spacer(minLength: 8)
                    PillButton(title: "Remove", action: { assistant.removeAPIKey() })
                }
            } else {
                StatusLine(state: .problem, text: "No API key yet")
            }
            HStack(spacing: 8) {
                SecureField(assistant.apiKeyHint == nil ? "Paste your API key (sk-ant-…)" : "Paste a new key to replace it", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                    .onSubmit(save)
                PillButton(title: "Save", prominent: true, action: save)
            }
            if let problem = problem {
                Text(problem)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
            SettingsDetail(text: "Make a key at console.anthropic.com → API Keys. You pay Anthropic per question. The key stays on this Mac, in a file only your account can read.")
        }
    }

    private func save() {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if assistant.saveAPIKey(typed) {
            typed = ""
            problem = nil
        } else {
            problem = "That doesn't look like an API key. Copy it again from the console."
        }
    }
}

struct QwenStatus: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        switch assistant.status {
        case .checking:
            StatusLine(state: .waiting, text: "Looking for Qwen on this Mac…")
        case .noOllama, .noModel:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(state: .problem, text: assistant.status == .noOllama ? "Ollama isn't running" : "No Qwen model downloaded yet")
                SettingsDetail(text: assistant.status == .noOllama
                               ? "Install Ollama from ollama.com and open it. Then download Qwen in Terminal (several GB, so use Wi-Fi):"
                               : "Download the Qwen model that suits this Mac in Terminal (several GB, so use Wi-Fi):")
                CommandBox(command: "ollama pull \(assistant.suggestedModel)")
                PillButton(title: "Check Again", prominent: true, action: { assistant.checkSetup() })
            }
        default:
            StatusLine(state: .good, text: "Using \(assistant.modelName) with Ollama, on this Mac")
        }
    }
}

// MARK: Timetable

struct TimetableSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TimetableStore
    @State var confirmClear = false

    var body: some View {
        let table = store.timetable

        SettingsHeading(title: "Timetable",
                        detail: "Your day from 6 am to 10 pm: school, and an hour block for each hour around it. Click a slot in the timetable to fill it in, or ask the assistant to. It's kept on this Mac.")
        SettingsRow(title: "School",
                    detail: "\(ClockTime.long(table.schoolStart)) to \(ClockTime.long(table.schoolEnd)). Click School in the timetable to change its times.") {
            ChoiceSegments(options: [
                ChoiceSegments<Bool>.Option(value: true, title: "One block", help: "School as one block, 8 am to 4 pm"),
                ChoiceSegments<Bool>.Option(value: false, title: "Periods", help: "Seven periods, recess and lunch, 8 am to 4 pm"),
            ], selected: table.schoolIsOneBlock, choose: { oneBlock in
                guard oneBlock != store.timetable.schoolIsOneBlock else { return }
                store.change { table in
                    if oneBlock {
                        table.useSchoolBlock()
                    } else {
                        table.useSchoolPeriods()
                    }
                }
            })
        }
        VStack(alignment: .leading, spacing: 12) {
            BlockCountRow(title: "Hour blocks before school",
                          detail: table.beforeSchool == 0 ? "None" : "For extracurriculars from \(ClockTime.hour(max(0, table.schoolStart - table.beforeSchool * 60)))",
                          count: table.beforeSchool, range: 0...Timetable.maxBefore,
                          change: { count in store.change { $0.setBlocks(before: count) } })
            BlockCountRow(title: "Hour blocks after school",
                          detail: table.afterSchool == 0 ? "None" : "For extracurriculars until \(ClockTime.hour(min(24 * 60, table.schoolEnd + table.afterSchool * 60)))",
                          count: table.afterSchool, range: 0...Timetable.maxAfter,
                          change: { count in store.change { $0.setBlocks(after: count) } })
            SettingsToggle(title: "Saturday and Sunday",
                           detail: "For weekend sport, music and jobs.",
                           isOn: Binding(get: { store.timetable.weekends },
                                         set: { on in store.change { $0.weekends = on } }))
        }
        SettingsDivider()
        SettingsToggle(title: "Two-week timetable",
                       detail: "For schools with a Week A and a Week B. Each week has its own lessons.",
                       isOn: Binding(get: { store.timetable.twoWeeks },
                                     set: { on in store.change { $0.twoWeeks = on } }))
        if table.twoWeeks {
            SettingsRow(title: "This week is", detail: "The timetable works out every other week from this.") {
                ChoiceSegments(options: [
                    ChoiceSegments<Int>.Option(value: 0, title: "Week A", help: "This week is Week A"),
                    ChoiceSegments<Int>.Option(value: 1, title: "Week B", help: "This week is Week B"),
                ], selected: table.week(of: Date()), choose: { week in
                    store.change { $0.setThisWeek(week) }
                    model.timetableWeek = week
                })
            }
        }
        SettingsDivider()
        SettingsRow(title: "Clear every lesson", detail: "Periods, times and hour blocks stay, ready for a new term.") {
            PillButton(title: confirmClear ? "Click Again to Clear" : "Clear Lessons", prominent: confirmClear, action: {
                if confirmClear {
                    store.change { $0.clearLessons() }
                    confirmClear = false
                } else {
                    confirmClear = true
                }
            })
            .disabled(table.isEmpty && !confirmClear)
            .opacity(table.isEmpty && !confirmClear ? 0.5 : 1)
        }
        PillButton(title: "Open Timetable", prominent: true, action: { model.openTimetable() })
    }
}

// MARK: Planner

struct PlannerSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant
    @ObservedObject var store: PlannerStore

    var body: some View {
        SettingsHeading(title: "Planner",
                        detail: "Your homework and exams, kept on this Mac. Type them in, ask the assistant to add them, or let your email do it.")
        PlannerMailSettings(settings: settings, assistant: assistant)
        SettingsDivider()
        PlannerStudySettings(settings: settings)
        SettingsDivider()
        SettingsRow(title: "Finished homework",
                    detail: store.planner.finished.isEmpty ? "Nothing finished to clear. Finished homework clears itself after a month."
                        : "\(store.planner.finished.count) finished. They clear themselves after a month.") {
            PillButton(title: "Clear Finished", action: { store.change { $0.clearDone() } })
                .disabled(store.planner.finished.isEmpty)
                .opacity(store.planner.finished.isEmpty ? 0.5 : 1)
        }
        PillButton(title: "Open Planner", prominent: true, action: { model.openPlanner() })
    }
}

/// What the planner takes from your mail, and who reads it.
struct PlannerMailSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var assistant: Assistant

    var body: some View {
        let name = assistant.engine.name

        SettingsToggle(title: "Add homework from Google Classroom emails",
                       detail: "New assignments, their due dates and returned work are read from Classroom's emails here, on this Mac, with no AI. Nothing is sent anywhere.",
                       isOn: $settings.classroomHomework)
        SettingsToggle(title: "Find due dates in my other emails with \(name)",
                       detail: assistant.engine.isClaude
                           ? "Off, your emails stay on this Mac. On, emails that mention something like a due date, an exam or a form to return are sent to Anthropic for Claude to read: who it's from, the subject and the first 1,500 characters, starting with the last two weeks. It uses Claude Haiku, a few emails at a time."
                           : "Emails that mention something like a due date, an exam or a form to return are read by Qwen on this Mac. Nothing leaves it.",
                       isOn: $assistant.findsDueDates)
        if assistant.findsDueDates {
            StatusLine(state: settings.finding.problem != nil ? .problem : (settings.finding.busy ? .waiting : .good),
                       text: assistant.status.isReady ? settings.finding.summary : "Waiting for \(name) to be set up (Settings → Assistant)")
        }
        SettingsToggle(title: "Let the assistant see and change my planner",
                       detail: assistant.engine.isClaude
                           ? "For \"what's due this week?\" and \"add a Maths test on Friday\". Your homework and exams are sent to Anthropic with each question you ask."
                           : "For \"what's due this week?\" and \"add a Maths test on Friday\". They stay on this Mac.",
                       isOn: $assistant.editsPlanner)
    }
}

/// Fitting homework into free time.
struct PlannerStudySettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsToggle(title: "Plan my study time",
                       detail: "Fits homework and exam revision into the free time on your timetable, soonest due first, and shows it in the planner and in the timetable's empty slots.",
                       isOn: $settings.plansStudy)
        if settings.plansStudy {
            SettingsRow(title: "Study in a day",
                        detail: "The most to plan for one day. Homework due sooner than that allows is still planned in time.") {
                ChoiceSegments(options: AppSettings.studyChoices.map { minutes in
                    ChoiceSegments<Int>.Option(value: minutes,
                                               title: minutes == 0 ? "Any" : DueText.length(minutes),
                                               help: minutes == 0 ? "As much as fits in your free time" : "Up to \(DueText.length(minutes)) of study a day")
                }, selected: settings.studyMinutesADay, choose: { settings.studyMinutesADay = $0 })
            }
        }
    }
}

// MARK: Extras

struct ExtrasSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var timer: FocusTimer

    var body: some View {
        SettingsHeading(title: "Extras",
                        detail: "Small helpers in a row under the primary menu's tiles, with more room in the Extras panel (click any of them). Switch off the ones you don't want.")
        SettingsToggle(title: "Now playing",
                       detail: "Shows what Spotify or Music is playing, with previous, play or pause, and next. The first time you press a button, macOS asks whether Notch Inbox may control that app; it may ask again after an update. Nothing is looked up online.",
                       isOn: $settings.showsNowPlaying)
        SettingsDivider()
        FocusSettings(settings: settings, timer: timer)
        SettingsDivider()
        SettingsToggle(title: "Clipboard history",
                       detail: "Keeps the last 30 things you copy, so you can copy one again. They're held in memory only: never saved to disk, never sent anywhere, never shown to the assistant, and gone when the app quits. Copies that password managers mark as private are skipped.",
                       isOn: $settings.keepsClipboard)
        SettingsDivider()
        SettingsToggle(title: "Shelf",
                       detail: "Drag files to the notch to park them, then drag them out where they're going. The shelf remembers where the files are; it doesn't copy or move them.",
                       isOn: $settings.showsShelf)
        SettingsDivider()
        LevelsSettings(settings: settings)
        PillButton(title: "Open Extras", prominent: true, action: { model.openExtras() })
    }
}

/// Volume and brightness at the notch, and whether the notch takes their keys over.
struct LevelsSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsToggle(title: "Volume and brightness",
                       detail: "When you change the volume or the brightness, the closed notch shows it for a moment, and the Extras panel has a slider for each. This needs no permission. Brightness is for this Mac's own screen.",
                       isOn: $settings.showsLevels)
        if settings.showsLevels {
            SettingsToggle(title: "Keep them beside the notch",
                           detail: "Two small gauges stay beside the closed notch all the time: the volume on the left, the brightness on the right. Off, they only show for a moment when one changes.",
                           isOn: $settings.levelsAlways)
            SettingsToggle(title: "Hide macOS's own pop-up",
                           detail: "The notch takes over the volume and brightness keys and changes them itself, so macOS's pop-up doesn't show as well. Only those keys are looked at. With a second screen plugged in, the brightness keys are left to macOS.",
                           isOn: $settings.replacesSystemLevels)
            if settings.replacesSystemLevels {
                AccessibilityStatus(settings: settings,
                                    allowed: "The notch has the volume and brightness keys",
                                    missing: "macOS hasn't allowed Notch Inbox to take the keys over yet",
                                    without: "Until it does, the keys work as usual and macOS's pop-up shows too.")
            }
        }
    }
}

/// The focus timer's switch and lengths.
struct FocusSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var timer: FocusTimer

    var body: some View {
        SettingsToggle(title: "Focus timer",
                       detail: "A stretch of focus, then a short break. While it runs, the minutes left show beside the closed notch; when it's up there's a chime and the notch opens. In the planner, point at a planned stretch and click its timer to start one for it.",
                       isOn: $settings.showsFocus)
        if settings.showsFocus {
            SettingsRow(title: "Focus for", detail: "How long a round lasts.") {
                ChoiceSegments(options: FocusTimer.focusChoices.map {
                    ChoiceSegments<Int>.Option(value: $0, title: "\($0) min", help: "\($0) minutes of focus")
                }, selected: timer.focusMinutes, choose: { timer.focusMinutes = $0 })
            }
            SettingsRow(title: "Break for", detail: "How long the break after it lasts.") {
                ChoiceSegments(options: FocusTimer.breakChoices.map {
                    ChoiceSegments<Int>.Option(value: $0, title: "\($0) min", help: "A \($0)-minute break")
                }, selected: timer.breakMinutes, choose: { timer.breakMinutes = $0 })
            }
        }
    }
}

// MARK: Gmail link

struct GmailLinkSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let link = settings.link

        SettingsHeading(title: "Gmail link",
                        detail: "A small add-on in Chrome passes the mail of every Gmail account signed in there to this app. It only talks to Gmail and to this app, on this Mac.")
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            StatusLine(state: link.lastSync == nil ? .problem : (link.isHealthy ? .good : .waiting),
                       text: link.summary(now: context.date))
        }
        VStack(alignment: .leading, spacing: 3) {
            SettingsDetail(text: "Add-on running in Chrome: \(link.addOnRunning ?? "not heard from yet")")
            SettingsDetail(text: "Add-on this app installs: \(link.addOnInstalled ?? "not installed yet")")
        }
        HStack(spacing: 8) {
            PillButton(title: "Set Up Browser Link…", prominent: link.lastSync == nil, action: { settings.setUpBrowserLink() })
            PillButton(title: "Show Add-on Folder", action: { settings.showAddOnFolder() })
            PillButton(title: "Copy Debug Info", action: { settings.copyDebugInfo() })
        }
        SettingsDetail(text: "Copy Debug Info copies counts and addresses only, never what your emails say.")
        SettingsDivider()
        SettingsDetail(text: "Read and unread are the notch's own. Emails you open stay read through restarts and updates, and an inbox's tick (or a right-click on its name) marks all of it read or unread. Gmail itself isn't changed.")
    }
}

// MARK: Updates

struct UpdateSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Updates",
                        detail: "Notch Inbox looks for a new build every 2 minutes. It only installs one when you click Install.")
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.build > 0 ? "Build \(settings.build)" : "Local build")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                if let checked = settings.lastUpdateCheck {
                    TimelineView(.periodic(from: Date(), by: 30)) { _ in
                        Text("Last checked \(MailTime.label(for: checked))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            switch settings.update {
            case .available(let build, _):
                PillButton(title: "Install Build \(build)", prominent: true, action: { settings.installUpdate() })
            case .checking, .installing, .unavailable:
                EmptyView()
            default:
                PillButton(title: "Check for Updates", action: { settings.checkForUpdates() })
            }
        }
        if case .available(_, let notes) = settings.update, !notes.isEmpty {
            Text(notes)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.body)
                .lineLimit(10)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        }
    }

    private var statusText: String {
        switch settings.update {
        case .idle: return "Not checked yet"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Up to date"
        case .available(let build, _): return "Build \(build) is ready to install"
        case .installing: return "Installing… Notch Inbox restarts by itself"
        case .failed(let message): return message
        case .unavailable: return "Updates work in the installed app"
        }
    }
}

// MARK: Pieces

struct SettingsHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let detail = detail {
                SettingsDetail(text: detail)
            }
        }
    }
}

struct SettingsDetail: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// A setting with its title and explanation on the left and its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                SettingsDetail(text: detail)
            }
            control()
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A green, amber or red dot with a line of status.
struct StatusLine: View {
    enum Tone {
        case good
        case waiting
        case problem
    }

    let state: Tone
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var color: Color {
        switch state {
        case .good: return Color(hex: 0x34C759)
        case .waiting: return Color(hex: 0xFFB340)
        case .problem: return Color(hex: 0xFF5F57)
        }
    }
}

/// Two or three choices side by side in a capsule, like a segmented control.
struct ChoiceSegments<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let help: String
    }

    let options: [Option]
    let selected: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selected
                Button(action: { choose(option.value) }) {
                    Text(option.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(isSelected ? Theme.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.help)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
        .fixedSize()
    }
}
