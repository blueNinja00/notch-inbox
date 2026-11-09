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

Within a minute, the notch shows the unread mail of every Gmail account signed in to that browser (up to three), with Gmail's unread counts:

- **Primary tab, plus Google mail** for everyday accounts: Google Classroom, Docs, Drive and Calendar notices are included even when Gmail files them under Updates.
- **Whole inbox** (every tab) for an address made for receipts or sign-ups (a catch-all, say), since Gmail files that mail outside Primary.

Change either per account, or hide an account, in the app menu (sliders button) under the account's address.

**Reading in the notch marks it read in Gmail.** Open an email in the notch and it greys out and the unread count drops at once; within about 30 seconds the add-on marks it read in Gmail too, then checks that Gmail took it (the add-on's popup shows "Marked read in Gmail"). If Gmail hasn't caught up after 10 minutes, the notch shows it unread again.

The notch lists **unread** mail, which is what Gmail's feed shares. Mail you read after it reached the notch stays there, greyed. Mail that was already read before then doesn't show, so an account where everything is read shows "Nothing unread" until new mail comes in.

**Whole emails.** Click an email in the notch to read all of it there, laid out the way its sender designed it: a Classroom assignment with its class, due date and **Open** button, a newsletter, a receipt. Links open in the browser. To reply, forward or archive, click **Reply in Gmail** (or press **O**).

Gmail always opens in **Google Chrome**, where your accounts are signed in, even if another browser is your default. Without Chrome it uses Arc, Brave or Edge.

**How it works.** Every minute, within seconds when an open Gmail tab shows new or read mail, and within 30 seconds of the app starting, the add-on reads each signed-in account's unread-mail feeds from `mail.google.com`, using the browser's existing sign-in. It also opens the new emails through Gmail's **Show original** and decodes them. It passes all this to the app over `127.0.0.1`. The app only listens on this Mac and only accepts uploads from this add-on. Your mail isn't sent anywhere else and never goes to GitHub. Emails are shown with scripts turned off; pictures in them load from the sender's servers, as in any mail app.

If opening emails that way would count as reading them in Gmail, the add-on notices on its first try and from then on only fetches emails you open in the notch.

The app keeps a copy of what the notch shows in `~/Library/Application Support/Notch Inbox/Mailbox.json`, readable only by you, so your mail is there the moment it starts, after an update say.

**After an app update.** The add-on comes with the app and updates itself: it reloads in the browser when the app brings a new version. The one exception is going from the first version (1.0) to a newer one: click the reload arrow on **Notch Inbox Link** in `chrome://extensions` once, or quit and reopen Chrome.

## Updates

Every change pushed to this repository is built on GitHub's Macs and published as a numbered build (see [Releases](../../releases)). The app looks for a new build when it starts and every 2 minutes. When one is ready:

- an **Update** button appears at the top right of the open notch, and
- **Install Update** appears in the app menu.

Click either one to download the new build, swap it in and restart. Nothing installs without your click. The app menu also has **Check for Updates…** and shows which build you're running.

**The app menu** opens from the menu button (sliders icon) at the top right of the open notch. The same menu sits under an envelope icon in the menu bar, but on a MacBook macOS hides menu-bar icons that don't fit beside the notch, so the notch's button is the reliable way in.

## Using it

It shows on every screen: in the MacBook's notch, and as a notch-shaped tab at the top of any external display. It appears on every desktop (Space) too, including full-screen apps. Only one notch opens at a time.

- **Glance:** unread counts for each account sit beside the notch, in full (3992, not 4k; only 10,000 and up are shortened). Accounts with nothing unread are left out.
- **Hover the notch:** the primary menu drops down, with one tile per tool: **Mail** (total unread, the newest email, each inbox's count) and **Notes** (how many, and the latest). More tools will join them. Click anywhere on it to keep it open.
- **Assistant:** chat with Qwen, an AI that runs on your Mac through [Ollama](https://ollama.com), for everyday help: planning your day, summarising email, what's due, writing replies. It can see your newest emails and notes if you let it (a checkbox under the chat); nothing leaves your Mac. The first time, it shows the one Terminal command to download the right Qwen model for your Mac's memory.
- **Notes:** a list on the left, the note on the right; it saves as you type, and the first line is the title. The expand button makes it bigger. Notes are kept in `~/Library/Application Support/Notch Inbox/Notes.json`, readable only by you.
- **Make it bigger:** drag the bottom edge of the open panel, or the grip in its bottom-right corner (it grows on both sides, staying centred on the notch). Double-click the grip for the standard size. Sizes are remembered.
- **Click the Mail tile:** it opens into three lanes, one per inbox. The grid button at the top left goes back to the primary menu.
- **Click a lane's header, or any email in it:** that inbox expands, with the list on the left and the full email plus a reply box on the right. The other two inboxes shrink to slim tabs at the sides; click one to switch.
- **Click outside, or press Esc** to close. Esc steps back one level: email → inboxes → primary menu → closed.
- **Two modes:** the switch at the top right of the primary menu (or the app menu) picks between **Notch at the Top**, which opens when you hover, and **Mail Tab**: everything at the notch is hidden, numbers included, leaving a small black tab with a mail icon hanging from the top of the screen. Drag it along the top, even onto another screen; it stays where you leave it and steps around a camera notch. Click it to open the primary menu (the tab steps aside while it's open) and right-click it for the menu.

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
| `GmailFeed.swift`, `LiveMailbox.swift` | Reads Gmail's feeds, picks Primary or the whole inbox per account, keeps read mail greyed instead of dropping it |
| `EmailContent.swift`, `Views/EmailWebView.swift` | Tidies whole emails and shows them (no scripts; links go to the browser) |
| `MailboxFile.swift` | The copy of the notch's mail kept between launches |
| `BrowserExtension/mime.js` | Decodes whole emails in the add-on (MIME, base64, quoted-printable, charsets) |
| `BrowserExtensionInstaller.swift` | Puts the add-on where the browser can load it |
| `Views/` | The SwiftUI screens: resting notch, peek, lanes, expanded inbox |
| `Theme.swift` | Colours from the design |
| `.github/workflows/release.yml` | Builds and publishes a release for every push to `main` |
