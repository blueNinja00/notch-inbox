# Notch Inbox

A menu-bar app that turns the MacBook notch into one inbox for three email accounts. Hover to peek, click to see all three side by side, click an inbox to expand it.

It shows sample mail until you link your Gmail through the browser (below). A settings page comes next.

## Install

Paste this into Terminal (macOS 13 Ventura or later):

```sh
curl -fL -o /tmp/NotchInbox.zip https://github.com/blueNinja00/notch-inbox/releases/latest/download/NotchInbox.zip && ditto -x -k /tmp/NotchInbox.zip /Applications && open "/Applications/Notch Inbox.app"
```

It downloads the latest build, puts **Notch Inbox** in your Applications folder and starts it. To have it start when you log in, add it under **System Settings → General → Login Items**.

## Link your Gmail

Notch Inbox reads your mail through the browser where your Gmail accounts are already signed in (Chrome, Arc, Brave or Edge). No passwords, nothing to sign in to again.

1. Open the notch, click the menu button at its top right (the sliders icon) and choose **Set Up Browser Link…**. Finder opens with the **Notch Inbox Link** folder selected.
2. In the browser, open `chrome://extensions` (Arc: `arc://extensions`) and turn on **Developer mode**.
3. Drag the **Notch Inbox Link** folder onto that page.

Within a minute, the notch shows the unread **Primary** mail of every Gmail account signed in to that browser (up to three), with Gmail's exact unread counts. When you read something in Gmail, it greys out in the notch. Opening an email in the notch shows Gmail's preview; **Open in Gmail** (or **O**) opens the full email to reply or archive.

Gmail always opens in **Google Chrome**, where your accounts are signed in, even if another browser is your default. Without Chrome it uses Arc, Brave or Edge.

How it works: every minute the add-on reads each signed-in account's unread-mail feed from `mail.google.com`, using the browser's existing sign-in, and passes it to the app over `127.0.0.1`. The app only listens on this Mac and only accepts uploads from this add-on. Your mail isn't sent anywhere else, and it never goes to GitHub.

## Updates

Every change pushed to this repository is built on GitHub's Macs and published as a numbered build (see [Releases](../../releases)). The app looks for a new build when it starts and every few hours. When one is ready:

- an **Update** button appears at the top right of the open notch, and
- **Install Update** appears in the app menu.

Click either one to download the new build, swap it in and restart. Nothing installs without your click. The app menu also has **Check for Updates…** and shows which build you're running.

**The app menu** opens from the menu button (sliders icon) at the top right of the open notch. The same menu sits under an envelope icon in the menu bar, but on a MacBook macOS hides menu-bar icons that don't fit beside the notch, so the notch's button is the reliable way in.

## Using it

It shows on every screen: in the MacBook's notch, and as a notch-shaped tab at the top of any external display. It appears on every desktop (Space) too, including full-screen apps. Only one notch opens at a time.

- **Glance:** unread counts for each account sit beside the notch.
- **Hover the notch:** a peek drops down with one tile per account and its newest sender.
- **Click the peek:** it opens into three lanes, one per inbox.
- **Click a lane's header, or any email in it:** that inbox expands, with the list on the left and the full email plus a reply box on the right. The other two inboxes shrink to slim tabs at the sides; click one to switch.
- **Click outside, or press Esc** to close (Esc steps back one level).

After you've clicked into the panel: **1 / 2 / 3** switch inbox, **E** archives, **U** marks unread, **Return** sends a reply. Replies start out from the account the email arrived in (marked "auto"); click another account to change it.

## Sample mail

Until the browser link is set up, the accounts (Personal, Work, Studio) and emails are made up, marked **Sample mail**, and archiving and replying only happen inside the app. Search, snooze and settings are placeholders for now.

## Building it yourself (optional)

Needs Xcode or Apple's command-line tools (`xcode-select --install`):

```sh
./scripts/build-app.sh
open "build/Notch Inbox.app"
```

## Where things live

| File | What it does |
|---|---|
| `AppDelegate.swift` | Launch; the app menu, in the notch and in the menu bar |
| `BrowserOpener.swift` | Opens Gmail and links in Chrome rather than the default browser |
| `NotchPanel.swift` | The window at the notch; hover, click and keyboard handling |
| `NotchPlacement.swift`, `Layout.swift` | Finds the notch and sizes each level |
| `NotchModel.swift` | State and actions: open, archive, mark unread, reply |
| `Mail.swift`, `SampleMail.swift` | Account and message types, sample data. A real mail source plugs in by implementing `MailProvider` |
| `Updater.swift`, `ReleaseFeed.swift` | Checks this repo's releases and installs newer builds |
| `BrowserExtension/` | The **Notch Inbox Link** browser add-on |
| `BrowserLink.swift`, `HTTPRequest.swift` | Receives the add-on's feeds on 127.0.0.1 |
| `GmailFeed.swift`, `LiveMailbox.swift` | Reads Gmail's feed; keeps read mail greyed instead of dropping it |
| `BrowserExtensionInstaller.swift` | Puts the add-on where the browser can load it |
| `Views/` | The SwiftUI screens: resting notch, peek, lanes, expanded inbox |
| `Theme.swift` | Colours from the design |
| `.github/workflows/release.yml` | Builds and publishes a release for every push to `main` |
