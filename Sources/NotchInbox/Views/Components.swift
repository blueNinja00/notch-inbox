import SwiftUI

/// Colour circle with the account's letter.
struct AccountBadge: View {
    let account: MailAccount
    var size: CGFloat = 16

    var body: some View {
        Text(account.letter)
            .font(.system(size: size * 0.53, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(Circle().fill(account.color))
    }
}

/// A small keyboard-key label, e.g. the 1–3 inbox shortcuts.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.keyCap))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(Theme.raised))
    }
}

struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(Theme.text)
            .frame(width: 6, height: 6)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    var tint: Color = Theme.secondary
    var action: () -> Void = {}
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Theme.hover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
        .onHover { hovering = $0 }
    }
}

/// The row beside the camera: content on the left and right, nothing over the notch itself.
struct TopRow<Leading: View, Trailing: View>: View {
    let metrics: NotchMetrics
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: metrics.notchGap)
            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: metrics.topRow)
    }
}

/// "Mail" tab plus a slot for future notch modules.
struct ModuleTabs: View {
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "envelope")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Mail")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(Capsule().fill(Theme.raised))

            IconButton(symbol: "plus", label: "Add a module (coming soon)", size: 28, tint: Theme.tertiary)
        }
        .padding(.leading, 4)
    }
}

struct PanelActions: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 2) {
            if let build = model.pendingUpdate {
                UpdateButton(build: build, action: { model.installUpdate() })
                    .padding(.trailing, 4)
            }
            IconButton(symbol: "magnifyingglass", label: "Search mail (coming soon)")
            IconButton(symbol: "square.and.pencil", label: "New message (coming soon)")
            IconButton(symbol: "slider.horizontal.3", label: "Settings (coming soon)")
        }
        .padding(.trailing, 4)
    }
}

/// Appears next to the panel actions when a newer build is ready.
struct UpdateButton: View {
    let build: Int
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Update")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Theme.text.opacity(hovering ? 1 : 0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Install build \(build) and restart Notch Inbox")
        .onHover { hovering = $0 }
    }
}

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text("All inboxes")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(Capsule().fill(Theme.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }
}
