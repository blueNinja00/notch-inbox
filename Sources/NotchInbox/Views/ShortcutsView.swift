import SwiftUI

/// Settings → Shortcuts: what each key does in the open notch, and a way to change it.
/// Click a key, then press the keys you want for it.
struct ShortcutSettings: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsHeading(title: "Shortcuts",
                        detail: "Keys that work while the notch is open and you've clicked in it. To change one, click its key and press the keys you want: something with ⌘, ⌃ or ⌥, or an F-key. Esc gives up, and Delete takes the key off.")
        if let note = model.keyNote {
            Text(note)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        }
        ForEach(KeyAction.Scope.allCases, id: \.self) { scope in
            ShortcutList(model: model, settings: settings, scope: scope)
        }
        SettingsDetail(text: "⌘⌫, and ⌘ or ⌥ with an arrow, also edit text. While there's something typed in the box you're in, those keys are left to the text.")
        if settings.keybinds.anyChanged {
            HStack(spacing: 8) {
                PillButton(title: "Put Them All Back", action: resetAll)
                Spacer(minLength: 0)
            }
        }
    }

    private func resetAll() {
        model.recordingKey = nil
        settings.resetKeys()
        model.keyNote = "Every shortcut is back on the key it came with."
    }
}

/// The shortcuts that work in one place, each with its key.
struct ShortcutList: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    let scope: KeyAction.Scope

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsDivider()
            Text(scope.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .padding(.top, 4)
            SettingsDetail(text: scope.detail)
            VStack(spacing: 0) {
                ForEach(scope.actions) { action in
                    ShortcutRow(title: action.title, key: settings.keybinds.label(for: action),
                                spoken: settings.keybinds.combo(for: action)?.spoken ?? "no key",
                                recording: model.recordingKey == action, changed: settings.keybinds.isChanged(action),
                                record: { record(action) }, reset: { reset(action) })
                }
            }
        }
        // Leaving the page gives up on a key that was being set.
        .onDisappear {
            model.recordingKey = nil
        }
    }

    /// Click a key to set it; click it again to give up.
    private func record(_ action: KeyAction) {
        model.keyNote = nil
        model.recordingKey = model.recordingKey == action ? nil : action
    }

    private func reset(_ action: KeyAction) {
        model.recordingKey = nil
        model.keyNote = settings.resetKey(action)
    }
}

/// One shortcut: what it does, and its key. The key is a button: click it and press new keys.
struct ShortcutRow: View {
    let title: String
    /// Its key as it's shown ("⌘N"), or "" if it has none.
    let key: String
    let spoken: String
    let recording: Bool
    /// Whether you've changed it from the key it came with.
    let changed: Bool
    let record: () -> Void
    let reset: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            if changed {
                IconButton(symbol: "arrow.uturn.backward", label: "Put it back on the key it came with", size: 22, tint: Theme.tertiary,
                           action: reset)
            }
            Button(action: record) {
                Text(ShortcutRow.shown(key: key, recording: recording))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minWidth: 86)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(recording ? "Press the keys for it. Esc gives up; Delete takes the key off." : "Click, then press the keys you want for it")
            .accessibilityLabel(Text(recording ? "\(title): press the keys for it" : "\(title): \(spoken). Click to change."))
        }
        .frame(height: 30)
    }

    static func shown(key: String, recording: Bool) -> String {
        if recording {
            return "Press keys…"
        }
        return key.isEmpty ? "None" : key
    }

    private var ink: Color {
        if recording {
            return Theme.onAccent
        }
        return key.isEmpty ? Theme.tertiary : Theme.text
    }

    private var fill: Color {
        if recording {
            return Theme.accent
        }
        return hovering ? Theme.hover : Theme.raised
    }
}
