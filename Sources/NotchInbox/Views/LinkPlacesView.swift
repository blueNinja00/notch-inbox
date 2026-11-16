import SwiftUI

/// Settings → Mail accounts: which browser profile each inbox's links open in. A link in
/// an email (and Open in Gmail) opens where that inbox's address is signed in; this shows
/// what was found for each inbox, and lets you pick another.
struct LinkPlaceSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let profiles = settings.browserProfiles

        VStack(alignment: .leading, spacing: 8) {
            Text("Where links open")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
            SettingsDetail(text: BrowserProfiles.about(browser: settings.profileBrowser, profiles: profiles.count))
            if !profiles.isEmpty {
                ForEach(settings.accounts) { account in
                    LinkPlaceRow(account: account.id, place: settings.linkPlace(for: account.id), profiles: profiles,
                                 choose: { settings.setLinkPlace($0, for: account.id) })
                }
            }
        }
        // (The browser's profiles are read again whenever this shows, in case one was added.)
        .onAppear {
            settings.onReadBrowserProfiles?()
        }
    }
}

/// Right-click an inbox in Mail → Open Links In: the same choice as in Settings, for that
/// inbox. Automatic says which profile it found.
struct LinkPlaceMenu: View {
    @ObservedObject var settings: AppSettings
    let email: String

    var body: some View {
        let profiles = settings.browserProfiles
        let place = settings.linkPlace(for: email)
        let choices = BrowserProfiles.choices(profiles)

        if !profiles.isEmpty {
            Menu("Open Links In") {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Toggle(isOn: Binding(
                        get: { place == choice.value },
                        set: { on in
                            if on { settings.setLinkPlace(choice.value, for: email) }
                        }
                    )) {
                        Text(BrowserProfiles.menuTitle(choice, email: email, profiles: profiles))
                    }
                }
            }
        }
    }
}

/// One inbox: where its links open now, and the places to choose from.
struct LinkPlaceRow: View {
    let account: String
    let place: LinkPlace
    let profiles: [BrowserProfile]
    let choose: (LinkPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(account)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(BrowserProfiles.line(for: account, place: place, in: profiles))
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                ChoiceSegments(options: LinkPlaceRow.options(profiles), selected: place, choose: choose)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lane))
    }

    /// Automatic, each of the browser's profiles by name, and the window in front.
    static func options(_ profiles: [BrowserProfile]) -> [ChoiceSegments<LinkPlace>.Option] {
        BrowserProfiles.choices(profiles).map { ChoiceSegments<LinkPlace>.Option(value: $0.value, title: $0.title, help: $0.help) }
    }
}
