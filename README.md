# Notch Inbox

A menu-bar app that turns the MacBook notch into one inbox for three email accounts. Hover to peek, click to see all three side by side, click an inbox to expand it.

It shows sample mail until you link your Gmail through the browser (below). **Settings** open inside the notch from the gear at its top right.

## Install

Paste this into Terminal (macOS 13 Ventura or later):

```sh
pkill -x NotchInbox; curl -fL --retry 4 --retry-delay 3 -o /tmp/NotchInbox.zip https://github.com/blueNinja00/notch-inbox/releases/latest/download/NotchInbox.zip && rm -rf "/Applications/Notch Inbox.app" && ditto -x -k /tmp/NotchInbox.zip /Applications && open "/Applications/Notch Inbox.app"
```

It downloads the latest build, puts **Notch Inbox** in your Applications folder (replacing any copy already there, after quitting it) and starts it. GitHub sometimes answers a download with a server error; it tries again a few times. To have it start when you log in, add it under **System Settings → General → Login Items**.

## Link your Gmail

Notch Inbox reads your mail through the browser where your Gmail accounts are already signed in (Chrome, Arc, Brave or Edge). No passwords, nothing to sign in to again.

1. Open the notch, click the gear at its top right, choose **Gmail link** and click **Set Up Browser Link…**. Finder opens with the **Notch Inbox Link** folder selected.
2. In the browser, open `chrome://extensions` (Arc: `arc://extensions`) and turn on **Developer mode**.
3. Drag the **Notch Inbox Link** folder onto that page.

Within a minute, the notch shows the unread mail of every Gmail account signed in to that browser (up to three), with Gmail's unread counts:

- **Primary tab, plus Google mail** for everyday accounts: Google Classroom, Docs, Drive and Calendar notices are included even when Gmail files them under Updates.
- **Whole inbox** (every tab) for an address made for receipts or sign-ups (a catch-all, say), since Gmail files that mail outside Primary.

Change either per account, or hide an account, in **Settings → Mail accounts**.

**Reading in the notch keeps a tally of its own.** Open an email in the notch and it greys out and the unread count drops at once. The notch remembers what you've read there, in its saved copy of your mail on this Mac, so it stays read through restarts and every update. Gmail itself isn't changed: the email stays unread there until you read it in Gmail. (Earlier builds tried to mark it read in Gmail too, out of sight; Gmail doesn't offer a dependable way to do that from a browser add-on, so it was taken out.) An email you read in the notch is forgotten only once it's over four months old and Gmail no longer lists it as unread.

The notch lists **unread** mail, which is what Gmail's feed shares. Mail you read after it reached the notch stays there, greyed. Mail that was already read before then doesn't show, so an account where everything is read shows "Nothing unread" until new mail comes in.

**Whole emails.** Click an email in the notch to read all of it there, laid out the way its sender designed it: a Classroom assignment with its class, due date and **Open** button, a newsletter, a receipt. Links open in the browser. To reply, forward or archive, click **Reply in Gmail** (or press **O**).

Gmail always opens in **Google Chrome**, where your accounts are signed in, even if another browser is your default. Without Chrome it uses Arc, Brave or Edge.

**How it works.** Every minute, within seconds when an open Gmail tab shows new or read mail, and within 30 seconds of the app starting, the add-on reads each signed-in account's unread-mail feeds from `mail.google.com`, using the browser's existing sign-in. It also opens the new emails through Gmail's **Show original** and decodes them. It passes all this to the app over `127.0.0.1`. The app only listens on this Mac and only accepts uploads from this add-on. Your mail isn't sent anywhere else and never goes to GitHub. Emails are shown with scripts turned off; pictures in them load from the sender's servers, as in any mail app.

If opening emails that way would count as reading them in Gmail, the add-on notices on its first try and from then on only fetches emails you open in the notch.

The app keeps a copy of what the notch shows in `~/Library/Application Support/Notch Inbox/Mailbox.json`, readable only by you, so your mail is there the moment it starts, after an update say.

**After an app update.** The add-on comes with the app and updates itself: it reloads in the browser when the app brings a new version. The one exception is going from the first version (1.0) to a newer one: click the reload arrow on **Notch Inbox Link** in `chrome://extensions` once, or quit and reopen Chrome.

## Updates

Every change pushed to this repository is built on GitHub's Macs and published as a numbered build (see [Releases](../../releases)). The app looks for a new build when it starts and every 2 minutes, by checking where github.com's "latest release" link leads. (Not GitHub's API, which allows apps that aren't signed in 60 questions an hour per network, shared by every app on it; it's only asked for a new build's notes, or when github.com doesn't answer. If a check you ask for fails, **Settings → Updates** says why.) When one is ready:

- an **Update** button appears at the top right of the open notch, and
- **Settings → Updates** shows the new build, its notes and an **Install** button.

Click either one to download the new build, swap it in and restart. Nothing installs without your click. **Settings → Updates** also has **Check for Updates** and shows which build you're running.

## Settings

Click the gear at the top right of the open notch. Settings open inside the notch, with a section per topic down the left:

- **General:** Notch at the top or Mail tab (below), and resetting panel sizes.
- **Mail accounts:** per account, Primary or Whole inbox, and whether it shows in the notch.
- **Assistant:** who answers (below), which Claude model, whether it may see and change your timetable, and whether it may see your newest emails and notes.
- **Timetable:** school as one block or periods, hour blocks before and after school, weekends, Week A and Week B, and clearing every lesson for a new term.
- **Gmail link:** whether the browser add-on is working, set it up, show its folder, and **Copy Debug Info** (counts and addresses only, never what your emails say).
- **Updates:** your build, checking and installing.
- **Quit Notch Inbox**, at the bottom.

An envelope in the menu bar has a short menu too (Open, Settings…, Quit), as does right-clicking the mail tab. On a MacBook, macOS hides menu-bar icons that don't fit beside the notch, so the gear is the reliable way in.

## The assistant

Ask about your day, your email or anything else. In **Settings → Assistant**, pick who answers:

- **Claude, with your Claude plan** (the default): answers through [Claude Code](https://claude.com/claude-code) on your Mac, signed in to your Claude account, so it counts toward your plan's usage and needs no API key. Install it once in Terminal with `curl -fsSL https://claude.ai/install.sh | bash`, then type `claude` and sign in. Each question runs Claude Code with no tools, skills or MCP servers, in a folder of its own, and nothing is saved to your Claude Code history.
- **Claude, with an API key:** paste a key from [console.anthropic.com](https://console.anthropic.com); you pay Anthropic per question. The key is kept in `~/Library/Application Support/Notch Inbox`, readable only by you.
- **Qwen, on this Mac:** runs locally through [Ollama](https://ollama.com); free and private, but slower and less capable. Settings shows the one Terminal command to download the right Qwen model for your Mac's memory (several GB).

For Claude, pick **Haiku 5.5** (fastest), **Sonnet 5.5** (the default) or **Opus 5.5** (smartest). **See and change my timetable** (on to start with) lets it read your timetable and change it when you ask. **Share my newest emails and notes** lets it see the senders, subjects and times of your 20 newest emails and your latest notes. With Claude they're sent to Anthropic with your question, so it starts off; with Qwen they stay on your Mac, so it starts on.

## Using it

It shows on every screen: in the MacBook's notch, and as a notch-shaped tab at the top of any external display. It appears on every desktop (Space) too, including full-screen apps. Only one notch opens at a time.

- **Glance:** unread counts for each account sit beside the notch, in full (3992, not 4k; only 10,000 and up are shortened). Accounts with nothing unread are left out.
- **Phone plugged in:** a red dot appears on the left of the notch while your phone (an iPhone, or an Android phone) is connected to the Mac by USB cable, and the primary menu names it. In Mail tab mode the dot sits on the tab. Wireless connections don't count. The app hears about it from macOS the moment a USB device comes or goes; nothing is read from the phone.
- **Hover the notch:** the primary menu drops down, with one tile per tool: **Mail** (total unread, the newest email, each inbox's count), **Timetable** (the class you're in now and the next one), **Notes** (how many, and the latest) and **Assistant**. Click anywhere on it to keep it open.
- **Assistant:** chat with Claude (or Qwen, on your Mac) for everyday help: planning your day, summarising email, what's due, writing replies. See [The assistant](#the-assistant).
- **Timetable:** your school week, Monday to Friday, with every class in its subject's colour. See [Timetable](#timetable).
- **Notes:** a list on the left, the note on the right; it saves as you type, and the first line is the title. The expand button makes it bigger. Notes are kept in `~/Library/Application Support/Notch Inbox/Notes.json`, readable only by you.
- **Make it bigger:** drag the bottom edge of the open panel, or the grip in its bottom-right corner (it grows on both sides, staying centred on the notch). Double-click the grip for the standard size. Sizes are remembered.
- **Click the Mail tile:** it opens into three lanes, one per inbox. The grid button at the top left goes back to the primary menu.
- **Click a lane's header, or any email in it:** that inbox expands, with the list on the left and the full email plus a reply box on the right. The other two inboxes shrink to slim tabs at the sides; click one to switch.
- **Click outside, or press Esc** to close. Esc steps back one level: email → inboxes → primary menu → closed.
- **Two modes:** **Settings → General** picks between **Notch at the top**, which opens when you hover, and **Mail tab**: everything at the notch is hidden, numbers included, leaving a small black tab with a mail icon hanging from the top of the screen. Drag it along the top, even onto another screen; it stays where you leave it and steps around a camera notch. Click it to open the primary menu (the tab steps aside while it's open) and right-click it for a short menu.

After you've clicked into the panel: **1 / 2 / 3** switch inbox, **E** archives, **U** marks unread, **Return** sends a reply. Replies start out from the account the email arrived in (marked "auto"); click another account to change it.

## Timetable

Click the Timetable tile on the primary menu. Your day runs down the left, from 6 am to 10 pm: **school as one block from 8 am to 4 pm**, with an **hour block for each hour before and after school, for your extracurriculars**. School is filled in on weekdays; change a day's block to "Excursion", say, by clicking it. Monday to Friday runs across the top. Today's column is marked, what's on now is lit up with a **NOW** tag, and what's finished today fades. A long day scrolls, starting where you are in it.

- **Add or change a lesson or activity:** click a slot. A panel on the right takes the subject, room and teacher (for an hour block: the activity, where and with whom), and saves as you type. Subjects you've used before appear as chips; picking one fills in its usual room and teacher too. Every lesson of a subject shares its colour; pick another colour in the same panel.
- **Change a period:** click its name on the left (or a break band, like Recess). Change its name, start and end time ("8:50", "1:10 pm" or "13:10"; without am or pm, 1 to 6 o'clock count as afternoon), or make it a break. **+** at the top adds a period at the end of the school day.
- **Ask the assistant:** "add soccer on Tuesdays at 5", "clear Friday evening", "I have swim squad Monday and Wednesday at 6 am". It makes the change and says what it changed (Settings → Assistant → **See and change my timetable**, on to start with).
- **School as periods instead:** **Settings → Timetable → School: Periods** splits it into seven periods, recess and lunch; **One block** puts it back.
- **Hour blocks:** click one's time on the left, or go to **Settings → Timetable**, to choose how many come before school (up to 4) and after (up to 8). They follow the school day, so if school ends at 3:30 they start at 3:30. Taking one away keeps what was in it.
- **Weekends:** turn on **Saturday and Sunday** in **Settings → Timetable** for weekend sport, music or a job.
- **Week A and Week B:** turn on **Two-week timetable** in **Settings → Timetable** and say which week this is. A switch at the top of the timetable shows either week, with a dot on this one.
- **Esc** closes the side panel; **Done** or Return does too. The expand button makes the timetable bigger.

A timetable from an earlier build moves to this day by itself: if its school day was still the starting one, school becomes the one block, and activities you'd added stay in their hours. It's kept in `~/Library/Application Support/Notch Inbox/Timetable.json`, readable only by you. With **See and change my timetable** on, the assistant sees your timetable (with Claude, it's sent to Anthropic with each question), so you can ask "What have I got tomorrow?".

## Sample mail

Until the browser link is set up, the accounts (Personal, Work, Studio) and emails are made up, marked **Sample mail**, and archiving and replying only happen inside the app. Search and snooze are placeholders for now.

## Building it yourself (optional)

Needs Xcode or Apple's command-line tools (`xcode-select --install`):

```sh
./scripts/build-app.sh
open "build/Notch Inbox.app"
```

## Where things live

| File | What it does |
|---|---|
| `AppDelegate.swift` | Launch; connects Settings to the mailbox, updater and browser link; the menu-bar envelope |
| `AppSettings.swift`, `Views/SettingsView.swift` | Settings inside the notch |
| `Timetable.swift`, `Views/TimetableView.swift` | The timetable: school, hour blocks, lessons, Week A/B, now and next |
| `TimetableAgent.swift` | What the assistant is told about the timetable, and making the changes it asks for |
| `PhoneCable.swift`, `PhoneCableWatcher.swift` | The red dot while a phone is plugged in by USB |
| `Assistant.swift`, `AssistantEngines.swift`, `AssistantPrompt.swift`, `ClaudeCode.swift` | The assistant: Claude through Claude Code or the API, or Qwen through Ollama |
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
| `Views/` | The SwiftUI screens: resting notch, primary menu, lanes, expanded inbox, notes, assistant, settings |
| `Theme.swift` | Colours from the design |
| `.github/workflows/release.yml` | Builds and publishes a release for every push to `main` |
