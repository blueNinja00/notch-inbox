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
                    if let level = model.levelHUD {
                        // The volume or brightness just changed: its symbol here, its bar opposite.
                        Image(systemName: level.symbol)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    } else {
                        if let volume = model.steadyLevel(.volume) {
                            LevelMini(reading: volume)
                        }
                        RestLeftEar(model: model, anyUnread: anyUnread)
                    }
                }
                .frame(width: ears)
            }
            Color.clear
                .frame(width: metrics.notchWidth)
            if ears > 0 {
                HStack(spacing: 8) {
                    if let level = model.levelHUD {
                        LevelBar(value: level.shown)
                            .frame(width: 40, height: 5)
                    } else {
                        ForEach(model.accounts.filter { model.unreadCount($0.id) > 0 }) { account in
                            UnreadNumber(count: model.unreadCount(account.id), color: account.color)
                        }
                        if let brightness = model.steadyLevel(.brightness) {
                            LevelMini(reading: brightness)
                        }
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
        .accessibilityLabel(Text(model.levelHUD?.label ?? RestView.spoken(unread: model.totalUnread, phone: model.phoneConnected)))
        .accessibilityAddTraits(.isButton)
    }

    /// What VoiceOver says for the closed notch.
    static func spoken(unread: Int, phone: String?) -> String {
        let mail = "Mail, \(unread) unread"
        guard let phone = phone else { return mail }
        return mail + ". \(phone) connected by cable"
    }
}

/// The left of the closed notch as it usually is: the phone's dot, then the focus timer's
/// minutes or an envelope.
private struct RestLeftEar: View {
    @ObservedObject var model: NotchModel
    let anyUnread: Bool

    var body: some View {
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
}

/// A small gauge that stays beside the closed notch: the level's symbol over a short bar.
struct LevelMini: View {
    let reading: LevelReading

    var body: some View {
        VStack(spacing: 2.5) {
            Image(systemName: reading.symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(height: 11)
            LevelBar(value: reading.shown)
                .frame(width: 16, height: 2.5)
        }
        .frame(width: 18)
        .help(reading.label)
    }
}

/// How loud or how bright, as a bar that fills from the left.
struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { area in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Theme.text)
                    .frame(width: area.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: value)
        .accessibilityHidden(true)
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
