import SwiftUI

/// Click the peek: one lane per inbox. Click a lane's header, or any message
/// in it, to expand that inbox.
struct LanesView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let size = model.size(.lanes)

        VStack(spacing: 0) {
            TopRow(metrics: metrics) {
                ModuleTabs(model: model)
            } trailing: {
                PanelActions(model: model)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(model.accounts) { account in
                    LaneColumn(model: model, account: account)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

struct LaneColumn: View {
    @ObservedObject var model: NotchModel
    let account: MailAccount

    var body: some View {
        let messages = model.inbox(account.id)
        let cards = Array(messages.prefix(4))
        let more = messages.count - cards.count

        VStack(alignment: .leading, spacing: 4) {
            LaneHeader(account: account,
                       unread: model.unreadCount(account.id),
                       action: { model.open(accountID: account.id) })

            ForEach(cards) { message in
                LaneCard(message: message,
                         action: { model.open(accountID: account.id, messageID: message.id) })
            }

            if more > 0 {
                Button(action: { model.open(accountID: account.id) }) {
                    Text("+ \(more) more")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }

            if messages.isEmpty {
                Text(model.isSample ? "All caught up" : "Nothing unread. New mail shows up here as it arrives.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lane))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

struct LaneHeader: View {
    let account: MailAccount
    let unread: Int
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AccountBadge(account: account, size: 16)
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                CountPill(count: unread)
                Spacer(minLength: 4)
                KeyCap(text: account.shortcut)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Theme.unreadCard : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Expand the \(account.name) inbox"))
    }
}

struct LaneCard: View {
    let message: MailMessage
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if message.isUnread {
                        UnreadDot()
                    }
                    Text(message.sender)
                        .font(.system(size: 12.5, weight: message.isUnread ? .semibold : .medium))
                        .foregroundStyle(message.isUnread ? Theme.text : Theme.readText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MailTime.label(for: message.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                Text(message.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(message.isUnread ? Theme.secondary : Theme.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.isUnread ? Theme.unreadCard : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.14 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
