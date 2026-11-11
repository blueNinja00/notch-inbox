import SwiftUI

/// Closed: the notch with an envelope on the left and per-account unread counts on the right,
/// a red dot on the left while a phone is plugged in by cable, and the focus timer's minutes
/// there while it runs.
struct RestView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let ears = model.restEars
        let anyUnread = model.accounts.contains { model.unreadCount($0.id) > 0 }

        HStack(spacing: 0) {
            if ears > 0 {
                HStack(spacing: 6) {
                    if model.phoneConnected != nil {
                        PhoneDot()
                    }
                    if model.focusRunning {
                        // The focus timer's minutes take the envelope's place while it runs.
                        FocusEar(timer: FocusTimer.shared)
                    } else if anyUnread {
                        Image(systemName: "envelope")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                    }
                }
                .frame(width: ears)
            }
            Color.clear
                .frame(width: metrics.notchWidth)
            if ears > 0 {
                HStack(spacing: 8) {
                    ForEach(model.accounts.filter { model.unreadCount($0.id) > 0 }) { account in
                        UnreadNumber(count: model.unreadCount(account.id), color: account.color)
                    }
                }
                .fixedSize()
                .frame(width: ears)
            }
        }
        .frame(height: metrics.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.goHome() }
        .help(model.phoneConnected.map { "\($0) connected by cable" } ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mail, \(model.totalUnread) unread" + (model.phoneConnected.map { ". \($0) connected by cable" } ?? "")))
        .accessibilityAddTraits(.isButton)
    }
}

/// The red dot that means a phone is plugged in by cable.
struct PhoneDot: View {
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Color(hex: 0xFF3B30))
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0xFF3B30).opacity(0.6), radius: 3)
    }
}

private struct UnreadNumber: View {
    let count: Int
    let color: Color

    var body: some View {
        Text(UnreadText.format(count))
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(count > 0 ? color : Theme.tertiary)
            .lineLimit(1)
            .fixedSize()
    }
}
