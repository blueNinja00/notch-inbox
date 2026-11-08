import SwiftUI

/// The primary menu: one tile per tool. Mail is the first; more tools will sit beside it.
/// Hovering the notch shows it; clicking a tile opens that tool.
struct HomeView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let size = metrics.bodySize(.peek)

        VStack(spacing: 0) {
            TopRow(metrics: metrics) {
                TodayLabel()
                    .padding(.leading, 6)
            } trailing: {
                HomeActions(model: model)
            }

            HStack(spacing: 8) {
                MailToolTile(model: model)
                MoreToolsTile()
                    .frame(width: 150)
            }
            .frame(height: 96)
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.pinHome() }
    }
}

/// Day and time at the top left of the primary menu.
struct TodayLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Text(TodayLabel.day.string(from: context.date))
                    .foregroundStyle(Theme.text)
                Text(TodayLabel.time.string(from: context.date))
                    .foregroundStyle(Theme.tertiary)
            }
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

/// Update button, minimise and the app menu, at the top right of the primary menu.
struct HomeActions: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 2) {
            if let build = model.pendingUpdate {
                UpdateButton(build: build, action: { model.installUpdate() })
                    .padding(.trailing, 4)
            } else if let note = model.updateNote {
                UpdateNote(text: note)
                    .padding(.trailing, 4)
            }
            MinimiseButton(model: model)
            IconButton(symbol: "slider.horizontal.3", label: "Menu: updates, Gmail link, Quit",
                       action: { model.showAppMenu() })
        }
        .padding(.trailing, 4)
    }
}

/// Mail: total unread, the newest email, and each inbox's count. Click to open your inboxes.
struct MailToolTile: View {
    @ObservedObject var model: NotchModel
    @State var hovering = false

    var body: some View {
        let newest = model.accounts
            .compactMap { model.headline($0.id) }
            .max { $0.date < $1.date }

        Button(action: { model.openLanes() }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.raised))
                    Text("Mail")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if model.isSample {
                        SampleTag()
                    }
                    Spacer(minLength: 4)
                    Text(UnreadText.format(model.totalUnread))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(newest?.sender ?? "Nothing unread")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .layoutPriority(1)
                    if let newest = newest {
                        Text(newest.subject)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .lineLimit(1)

                HStack(spacing: 12) {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(account.color)
                                .frame(width: 6, height: 6)
                            Text("\(account.name) \(UnreadText.format(model.unreadCount(account.id)))")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 5)
            }
            .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open Mail")
        .accessibilityLabel(Text("Mail, \(model.totalUnread) unread"))
    }
}

/// Room for the next tools.
struct MoreToolsTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
            Text("More tools\ncoming soon")
                .font(.system(size: 11.5, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}
