import SwiftUI

/// One inbox expanded: its messages on the left, the open message and a quick
/// reply on the right. The other inboxes shrink to slim rails, keeping their places.
struct DetailView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let size = metrics.bodySize(.detail, showEars: true)
        let activeIndex = model.accounts.firstIndex(where: { $0.id == model.activeAccountID }) ?? 0
        let leftRails = Array(model.accounts.prefix(activeIndex))
        let rightRails = Array(model.accounts.dropFirst(activeIndex + 1))

        VStack(spacing: 0) {
            TopRow(metrics: metrics) {
                BackButton(action: { model.back() })
            } trailing: {
                PanelActions(model: model)
            }

            HStack(spacing: 8) {
                ForEach(leftRails) { account in
                    InboxRail(account: account,
                              unread: model.unreadCount(account.id),
                              action: { model.open(accountID: account.id) })
                }
                if let active = model.activeAccount {
                    ExpandedInbox(model: model, account: active)
                }
                ForEach(rightRails) { account in
                    InboxRail(account: account,
                              unread: model.unreadCount(account.id),
                              action: { model.open(accountID: account.id) })
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// A collapsed inbox: badge, unread count and its name running vertically.
struct InboxRail: View {
    let account: MailAccount
    let unread: Int
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                AccountBadge(account: account, size: 22)
                Text("\(unread)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(account.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 96, height: 20)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 96)
                Spacer(minLength: 0)
                KeyCap(text: account.shortcut)
            }
            .padding(.vertical, 12)
            .frame(width: 56)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lane))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Expand the \(account.name) inbox, \(unread) unread"))
    }
}

struct ExpandedInbox: View {
    @ObservedObject var model: NotchModel
    let account: MailAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AccountBadge(account: account, size: 16)
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let email = account.email, email != account.name {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                CountPill(count: model.unreadCount(account.id))
                Spacer(minLength: 4)
                if !model.canAct {
                    IconButton(symbol: "arrow.up.right.square", label: "Open this inbox in Gmail", size: 24,
                               action: { model.openAccountInGmail(account.id) })
                }
                KeyCap(text: account.shortcut)
            }
            .padding(.horizontal, 6)
            .frame(height: 32)

            HStack(spacing: 8) {
                MessageList(model: model, account: account)
                    .frame(width: 300)
                ReadingPane(model: model, account: account)
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

struct MessageList: View {
    @ObservedObject var model: NotchModel
    let account: MailAccount

    var body: some View {
        let messages = model.inbox(account.id)

        ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(messages) { message in
                    MessageRow(message: message,
                               selected: message.id == model.openMessageID,
                               action: { model.open(accountID: account.id, messageID: message.id) })
                }
                if messages.isEmpty {
                    Text("All caught up — nothing left in this inbox.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.tertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct MessageRow: View {
    let message: MailMessage
    let selected: Bool
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        let strong = message.isUnread || selected

        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if message.isUnread {
                        UnreadDot()
                    }
                    Text(message.sender)
                        .font(.system(size: 12.5, weight: strong ? .semibold : .medium))
                        .foregroundStyle(strong ? Theme.text : Theme.readText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MailTime.label(for: message.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                Text(message.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(strong ? Theme.text2 : Theme.readText)
                    .lineLimit(1)
                Text(message.snippet)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.raised : (hovering ? Theme.surface : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ReadingPane: View {
    @ObservedObject var model: NotchModel
    let account: MailAccount

    var body: some View {
        Group {
            if let message = model.openMessage {
                VStack(alignment: .leading, spacing: 0) {
                    MessageHeader(message: message,
                                  account: account,
                                  canAct: model.canAct,
                                  archive: { model.archiveOpen() },
                                  markUnread: { model.markOpenUnread() },
                                  openInGmail: { model.openInGmail() })

                    Text(message.subject)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .padding(.top, 12)

                    if let html = message.html {
                        // A whole HTML email (Classroom notices, newsletters…) as designed.
                        if let attachment = message.attachment {
                            AttachmentChip(name: attachment)
                                .padding(.top, 8)
                        }
                        EmailWebView(html: html, openLink: { model.openLink($0) })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 10)
                    } else {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(message.body.enumerated()), id: \.offset) { item in
                                    Text(LinkedText.make(item.element))
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(Theme.body)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let attachment = message.attachment {
                                    AttachmentChip(name: attachment)
                                        .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                        .scrollIndicators(.hidden)
                        .environment(\.openURL, OpenURLAction { url in
                            model.openLink(url)
                            return .handled
                        })
                    }

                    if model.canAct {
                        Composer(model: model)
                            .padding(.top, 8)
                    } else {
                        GmailActions(note: message.isWhole
                                        ? "Reply, forward or archive it in Gmail. It opens in Chrome."
                                        : model.previewNote(for: message),
                                     open: { model.openInGmail() })
                            .padding(.top, 8)
                    }
                }
            } else {
                Text("Nothing left in \(account.name) — inbox zero.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

struct MessageHeader: View {
    let message: MailMessage
    let account: MailAccount
    let canAct: Bool
    let archive: () -> Void
    let markUnread: () -> Void
    let openInGmail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Text(message.initials)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.avatar))
                AccountBadge(account: account, size: 16)
                    .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(message.sender)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Circle()
                        .fill(account.color)
                        .frame(width: 7, height: 7)
                    Text("to \(account.name) · \(MailTime.label(for: message.date))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if canAct {
                    IconButton(symbol: "archivebox", label: "Archive (E)", action: archive)
                    IconButton(symbol: "clock", label: "Snooze (coming soon)")
                    IconButton(symbol: "envelope.badge", label: "Mark as unread (U)", action: markUnread)
                }
                IconButton(symbol: "arrow.up.right.square", label: "Open in Gmail (O)", action: openInGmail)
            }
        }
    }
}

/// For real Gmail: replying, forwarding and archiving happen in Gmail, in Chrome.
struct GmailActions: View {
    let note: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Reply in Gmail")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Theme.text))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Opens this email in Gmail, in Chrome")

            Text(note)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain text with its web addresses made clickable.
enum LinkedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func make(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = detector else { return attributed }
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let target = Range<AttributedString.Index>(range, in: attributed) else { continue }
            attributed[target].link = url
        }
        return attributed
    }
}

struct AttachmentChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .medium))
            Text(name)
                .font(.system(size: 12.5))
        }
        .foregroundStyle(Theme.text2)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
    }
}

/// Quick reply. "Reply from" starts on the inbox the message arrived in (marked "auto").
struct Composer: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sentFrom = model.sentFrom {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(model.replyFrom?.color ?? Theme.text)
                    Text("Reply sent from \(sentFrom)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    Text("Reply from")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.trailing, 4)
                    ForEach(model.accounts) { account in
                        FromChip(account: account,
                                 selected: account.id == model.replyFrom?.id,
                                 isAuto: account.id == model.activeAccountID,
                                 action: { model.chooseReplyAccount(account.id) })
                    }
                }

                HStack(spacing: 8) {
                    TextField("Reply to \(model.openMessage?.firstName ?? "")…", text: $model.replyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                        .onSubmit { model.send() }
                        .frame(height: 38)
                    KeyCap(text: "↵")
                    Button(action: { model.send() }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(model.replyFrom?.color ?? Theme.text))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(Text("Send reply"))
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.composer))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct FromChip: View {
    let account: MailAccount
    let selected: Bool
    let isAuto: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(account.color)
                    .frame(width: 7, height: 7)
                Text(account.name)
                    .font(.system(size: 12, weight: .semibold))
                if isAuto {
                    Text("auto")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.readText)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? account.color.opacity(0.16) : Color.clear))
            .overlay(
                Capsule()
                    .strokeBorder(selected ? account.color.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
