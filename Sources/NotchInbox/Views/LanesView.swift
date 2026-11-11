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
            if model.searching {
                MailSearchBar(model: model)
                    .padding(.top, 6)
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
        let messages = model.shownInbox(account.id)
        let searching = !model.searchWords.isEmpty

        VStack(alignment: .leading, spacing: 4) {
            LaneHeader(model: model,
                       account: account,
                       unread: model.unreadCount(account.id),
                       action: { model.open(accountID: account.id) })

            if messages.isEmpty {
                Text(searching ? "No emails match." : (model.isSample ? "All caught up" : "Nothing unread. New mail shows up here as it arrives."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                Spacer(minLength: 0)
            } else {
                // Every email the notch has for this inbox, filling the lane; scroll for more.
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(messages) { message in
                            LaneCard(message: message,
                                     action: { model.open(accountID: account.id, messageID: message.id) })
                                .contextMenu { MessageMenu(model: model, message: message) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
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

/// An inbox's name and unread count: click to expand it. The tick marks everything in it
/// read; right-click for "Mark All as Unread" too.
struct LaneHeader: View {
    @ObservedObject var model: NotchModel
    let account: MailAccount
    let unread: Int
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 2) {
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

            if model.undoAccount == account.id {
                IconButton(symbol: "arrow.uturn.backward", label: "Undo Mark All", size: 26,
                           action: { model.undoMarkAll() })
            } else if unread > 0 {
                IconButton(symbol: "checkmark.circle", label: "Mark all as read", size: 26,
                           action: { model.markAll(account.id, read: true) })
            }
        }
        .contextMenu { InboxMenu(model: model, account: account) }
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
