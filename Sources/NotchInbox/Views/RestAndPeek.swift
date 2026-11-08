import SwiftUI

/// Closed: the notch with an envelope on the left and per-account unread counts on the right.
struct RestView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let ears = model.restEars

        HStack(spacing: 0) {
            if ears > 0 {
                Image(systemName: "envelope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mail, \(model.totalUnread) unread"))
        .accessibilityAddTraits(.isButton)
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
