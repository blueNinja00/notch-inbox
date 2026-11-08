import SwiftUI

/// Closed: the notch with an envelope on the left and per-account unread counts on the right.
struct RestView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let showEars = model.totalUnread > 0

        HStack(spacing: 0) {
            if showEars {
                Image(systemName: "envelope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: NotchMetrics.earWidth)
            }
            Color.clear
                .frame(width: metrics.notchWidth)
            if showEars {
                HStack(spacing: 6) {
                    ForEach(model.accounts) { account in
                        UnreadNumber(count: model.unreadCount(account.id), color: account.color)
                    }
                }
                .frame(width: NotchMetrics.earWidth)
            }
        }
        .frame(height: metrics.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.openLanes() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mail, \(model.totalUnread) unread"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct UnreadNumber: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(count > 0 ? color : Theme.tertiary)
    }
}

/// Hover: one tile per account with its unread count and newest sender.
/// Clicking anywhere on it opens the three lanes.
struct PeekView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let size = metrics.bodySize(.peek, showEars: true)

        VStack(spacing: 0) {
            TopRow(metrics: metrics) {
                HStack(spacing: 7) {
                    Image(systemName: "envelope")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Mail")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.text)
                .padding(.leading, 6)
            } trailing: {
                let summary: String = model.isSample ? "Sample mail" : "\(model.totalUnread) unread"
                Text(summary)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .padding(.trailing, 6)
            }

            HStack(spacing: 8) {
                ForEach(model.accounts) { account in
                    PeekTile(account: account,
                             unread: model.unreadCount(account.id),
                             headline: model.headline(account.id),
                             emptyText: model.isSample ? "All caught up" : "Nothing unread")
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.openLanes() }
    }
}

struct PeekTile: View {
    let account: MailAccount
    let unread: Int
    let headline: MailMessage?
    var emptyText = "All caught up"
    @State var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AccountBadge(account: account, size: 16)
                Text(account.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(unread)")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline?.sender ?? emptyText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                Text(headline?.subject ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            .lineLimit(1)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 11, trailing: 12))
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}
