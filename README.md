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

**Read and unread are the notch's own.** Gmail itself is never changed; the notch keeps its own tally, saved on this Mac, so it holds through restarts and every update.

- **Open an email** in the notch and it greys out and the unread count drops at once.
- **Mark it unread again** with the envelope button above the email, **U**, or a right-click on it in any list. That works for mail you read in Gmail too.
- **Mark all as read:** the tick beside an inbox's name, or the open-envelope button when the inbox is expanded. The count goes to zero, including unread mail too old for Gmail to list (Gmail's feed only lists the newest 20 or so). New mail still arrives unread.
- **Mark all as unread:** the envelope-with-a-dot button when the inbox is expanded, or right-click the inbox's name. Every email the notch holds for that inbox becomes unread.
- **Undo** appears after either one and puts the inbox back as it was.

Mail you read in Gmail counts as read in the notch as well. (Earlier builds tried to mark mail read in Gmail too, out of sight; Gmail doesn't offer a dependable way to do that from a browser add-on, so it was taken out.)

**It goes back a long way.** Gmail's feed only shares unread mail, so an email first shows in the notch while it's unread. From then on the notch keeps it, greyed once it's read: up to 10,000 emails an account, which is years of mail for most inboxes. Scroll back through an inbox, or **search** every inbox at once with the magnifier (or **/**): type words from the sender, subject or preview. Mail that was already read before the notch first saw it doesn't show.

**Whole emails.** Click an email in the notch to read all of it there, laid out the way its sender designed it: a Classroom assignment with its class, due date and **Open** button, a newsletter, a receipt. Links open in the browser. To reply, forward or archive, click **Reply in Gmail** (or press **O**).

Gmail always opens in **Google Chrome**, where your accounts are signed in, even if another browser is your default. Without Chrome it uses Arc, Brave or Edge.

**How it works.** Every minute, within seconds when an open Gmail tab shows new or read mail, and within 30 seconds of the app starting, the add-on reads each signed-in account's unread-mail feeds from `mail.google.com`, using the browser's existing sign-in. It also opens the new emails through Gmail's **Show original** and decodes them. It passes all this to the app over `127.0.0.1`. The app only listens on this Mac and only accepts uploads from this add-on. Your mail isn't sent anywhere else and never goes to GitHub. Emails are shown with scripts turned off; pictures in them load from the sender's servers, as in any mail app.

If opening emails that way would count as reading them in Gmail, the add-on notices on its first try and from then on only fetches emails you open in the notch.

The app keeps the notch's mail in `~/Library/Application Support/Notch Inbox`, readable only by you, so it's there the moment the app starts, after an update say: the lists (who from, subject, preview, read or unread) in `Mailbox.json`, and whole emails one file each in `Emails`, so an email from months ago still opens in full, offline too. **Settings → Mail accounts** shows how much is kept and lets you choose how many emails stay in full (500, 2,000 to start with, 10,000 or all); beyond that the oldest go back to their preview.

**After an app update.** The add-on comes with the app and updates itself: it reloads in the browser when the app brings a new version. The one exception is going from the first version (1.0) to a newer one: click the reload arrow on **Notch Inbox Link** in `chrome://extensions` once, or quit and reopen Chrome.

## Updates

Every change pushed to this repository is built on GitHub's Macs and published as a numbered build (see [Releases](../../releases)). The app looks for a new build when it starts and every 2 minutes, by checking where github.com's "latest release" link leads. (Not GitHub's API, which allows apps that aren't signed in 60 questions an hour per network, shared by every app on it; it's only asked for a new build's notes, or when github.com doesn't answer. If a check you ask for fails, **Settings → Updates** says why.) When one is ready:

- an **Update** button appears at the top right of the open notch, and
- **Settings → Updates** shows the new build, its notes and an **Install** button.

Click either one to download the new build, swap it in and restart. Nothing installs without your click. **Settings → Updates** also has **Check for Updates** and shows which build you're running.

## Settings

Click the gear at the top right of the open notch. Settings open inside the notch, with a section per topic down the left:

- **General:** Notch at the top or Mail tab (below), and resetting panel sizes.
- **Mail accounts:** per account, Primary or Whole inbox, and whether it shows in the notch; how much mail is kept on this Mac, and how many emails to keep in full.
- **Assistant:** who answers (below), which Claude model, whether it may see and change your timetable and your planner, and whether it may see your newest emails and notes.
- **Timetable:** school as one block or periods, hour blocks before and after school, weekends, Week A and Week B, and clearing every lesson for a new term.
- **Extras:** switches for now playing, the focus timer (and its lengths), clipboard history and the shelf.
- **Planner:** whether Google Classroom emails add homework, whether the assistant looks for due dates in your other emails (off to start with for Claude), planning study time, and clearing finished homework.
- **Gmail link:** whether the browser add-on is working, set it up, show its folder, and **Copy Debug Info** (counts and addresses only, never what your emails say).
- **Updates:** your build, checking and installing.
- **Quit Notch Inbox**, at the bottom.

An envelope in the menu bar has a short menu too (Open, Settings…, Quit), as does right-clicking the mail tab. On a MacBook, macOS hides menu-bar icons that don't fit beside the notch, so the gear is the reliable way in.

## The assistant

Ask about your day, your email or anything else. In **Settings → Assistant**, pick who answers:

- **Claude, with your Claude plan** (the default): answers through [Claude Code](https://claude.com/claude-code) on your Mac, signed in to your Claude account, so it counts toward your plan's usage and needs no API key. Install it once in Terminal with `curl -fsSL https://claude.ai/install.sh | bash`, then type `claude` and sign in. Each question runs Claude Code with no tools, skills or MCP servers, in a folder of its own, and nothing is saved to your Claude Code history.
- **Claude, with an API key:** paste a key from [console.anthropic.com](https://console.anthropic.com); you pay Anthropic per question. The key is kept in `~/Library/Application Support/Notch Inbox`, readable only by you.
- **Qwen, on this Mac:** runs locally through [Ollama](https://ollama.com); free and private, but slower and less capable. Settings shows the one Terminal command to download the right Qwen model for your Mac's memory (several GB).

For Claude, pick **Haiku 5.5** (fastest), **Sonnet 5.5** (the default) or **Opus 5.5** (smartest). **See and change my timetable** and **See and change my planner** (both on to start with) let it read your timetable, homework and exams, and change them when you ask. **Share my newest emails and notes** lets it see the senders, subjects and times of your 20 newest emails and your latest notes. With Claude they're sent to Anthropic with your question, so it starts off; with Qwen they stay on your Mac, so it starts on.

## Using it

It shows on every screen: in the MacBook's notch, and as a notch-shaped tab at the top of any external display. It appears on every desktop (Space) too, including full-screen apps. Only one notch opens at a time.

- **Glance:** unread counts for each account sit beside the notch, in full (3992, not 4k; only 10,000 and up are shortened). Accounts with nothing unread are left out.
- **Phone plugged in:** a red dot appears on the left of the notch while your phone (an iPhone, or an Android phone) is connected to the Mac by USB cable, and the primary menu names it. In Mail tab mode the dot sits on the tab. Wireless connections don't count. The app hears about it from macOS the moment a USB device comes or goes. Click its name for its maker and how fast the cable is. An iPhone's battery level shows too if you've installed [libimobiledevice](https://libimobiledevice.org) (`brew install libimobiledevice`) and the phone trusts this Mac; macOS doesn't tell apps that by itself. Otherwise nothing is read from the phone.
- **Hover the notch:** the primary menu drops down, with one tile per tool: **Mail** (total unread, the newest email, each inbox's count), **Planner** (what's due next and your next exam), **Timetable** (the class you're in now and the next one), **Notes** (how many, and the latest) and **Assistant**. Your next exam counts down beside the date once it's within three weeks. Click anywhere on it to keep it open.
- **Planner:** homework, exam countdowns and a study plan. See [Planner](#planner).
- **Extras:** a row under the tiles with what's playing, a focus timer, clipboard history and a shelf for files. See [Extras](#extras).
- **Assistant:** chat with Claude (or Qwen, on your Mac) for everyday help: planning your day, summarising email, what's due, writing replies. See [The assistant](#the-assistant).
- **Timetable:** your school week, Monday to Friday, with every class in its subject's colour. See [Timetable](#timetable).
- **Notes:** a list on the left, the note on the right; it saves as you type, and the first line is the title. The expand button makes it bigger. Notes are kept in `~/Library/Application Support/Notch Inbox/Notes.json`, readable only by you.
- **Make it bigger:** drag the bottom edge of the open panel, or the grip in its bottom-right corner (it grows on both sides, staying centred on the notch). Double-click the grip for the standard size. Sizes are remembered.
- **Click the Mail tile:** it opens into three lanes, one per inbox. The grid button at the top left goes back to the primary menu.
- **Click a lane's header, or any email in it:** that inbox expands, with the list on the left and the full email plus a reply box on the right. The other two inboxes shrink to slim tabs at the sides; click one to switch.
- **Click outside, or press Esc** to close. Esc steps back one level: email → inboxes → primary menu → closed.
- **Two modes:** **Settings → General** picks between **Notch at the top**, which opens when you hover, and **Mail tab**: everything at the notch is hidden, numbers included, leaving a small black tab with a mail icon hanging from the top of the screen. Drag it along the top, even onto another screen; it stays where you leave it and steps around a camera notch. Click it to open the primary menu (the tab steps aside while it's open) and right-click it for a short menu.

After you've clicked into the panel: **1 / 2 / 3** switch inbox, **/** searches, **U** marks the open email unread (or read), **O** opens it in Gmail; with sample mail, **E** archives and **Return** sends a reply. Replies start out from the account the email arrived in (marked "auto"); click another account to change it.

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

## Planner

Click the Planner tile on the primary menu. Homework to do is on the left, grouped by when it's due (overdue in red, today in amber); when to do it is in the middle; exams are on the right, each with the days to go.

- **Add homework:** type it in one line at the top and press Return: "Maths worksheet fri 4pm 45m" is the worksheet, due Friday at 4 pm, taking 45 minutes. Dates can be "tomorrow", "fri", "20 Nov", "20/11" or "2026-11-20", with a time if there is one; "45m" or "1.5h" is how long it takes. A line under the box shows how it was read. A subject from your timetable named in it becomes its subject, and gives it that subject's colour. If you don't say how long it takes, the notch guesses from its name (a form is 10 minutes, an essay 90); change it in the side panel.
- **Tick it off** with the circle on its left. The tick button at the top shows finished homework again; it clears itself after a month.
- **Click homework or an exam** to edit it in the side panel: what, subject, when (type the date), how long it takes, notes. Right-click for a short menu.
- **Exams:** the graduation cap at the top (or **+** in Exams) adds one. Say when and where it is and how much revision to plan. The soonest one counts down on the Planner tile and beside the date on the primary menu. **It's an Exam** in homework's side panel turns a "Unit 3 test" that arrived as homework into an exam.
- **The plan:** homework and revision are fitted into the free time on your [timetable](#timetable): after school on school days (around your activities), 9 to 6 at weekends, never past 9:30 pm. Whatever's due soonest goes first, up to two hours a day unless something due sooner needs more, and revision goes on the days just before each exam, an hour a day. Homework that can't fit before it's due gets a warning triangle. The plan also shows, faintly, in the empty slots of this week's timetable. **Settings → Planner** changes the two hours or turns planning off. Homework with no due date isn't planned.
- **Google Classroom:** when Classroom emails you about a new assignment or question, it's added as homework with its class, its due date and a link to its page. A "due tomorrow" reminder fills in a missing date, and work your teacher returns is ticked off. The emails are read on your Mac, with no AI, and nothing is sent anywhere (**Settings → Planner → Add homework from Google Classroom emails**, on to start with). It needs the account your school uses to be one of the Gmail accounts in the notch.
- **Due dates in other emails:** the assistant can look for them in the rest of your mail ("permission notes back by Friday", "the yearly exams start on the 23rd") and add what it finds, marked with a small envelope so you can check it against its email. **With Claude this is off until you turn it on** in **Settings → Planner**, because the emails it looks at are sent to Anthropic: only emails that mention something like a due date, an exam or a form to return, and of each only who it's from, the subject and the first 1,500 characters, starting with the last two weeks. It uses Claude Haiku, a few emails at a time. With Qwen the emails are read on your Mac, so it starts on. Anything you remove isn't added again from the same email.
- **Ask the assistant:** "what's due this week?", "add a Maths test on Friday at 9 in the hall", "I've finished the English essay", "move the History notes to Monday". It makes the change and says what it changed (**See and change my planner**, on to start with; with Claude, your homework and exams are sent to Anthropic with each question).
- **Esc** closes the side panel. The expand button makes the planner bigger.

The planner is kept in `~/Library/Application Support/Notch Inbox/Planner.json`, readable only by you.

## Extras

A row under the primary menu's tiles. Click any of them for the **Extras** panel, which has more room. Each can be switched off in **Settings → Extras**.

- **Now playing:** the song in Spotify or Music, with previous, play or pause, and next. What's playing comes from the notices those apps post when it changes, so it appears the next time the song changes or you press play. The first time you press a button, macOS asks whether Notch Inbox may control that app (say OK); because each update is a new build, it may ask again after one. It never starts a music app, and nothing is looked up online.
- **Focus timer:** press play for a round of focus (25 minutes, or 15, 45 or 50), then a break (5, 10 or 15). The minutes left show beside the closed notch; when time's up there's a chime and the notch opens. In the planner, point at a stretch in the Plan and click its timer to focus on that for as long as it's planned; afterwards one click ticks the homework off.
- **Clipboard history:** the last 30 things you copied; click one to copy it again. They're held in memory only: never saved to disk, never sent anywhere, never shown to the assistant, and gone when the app quits. Copies that password managers mark as private are skipped, and **Clear** forgets the lot.
- **Shelf:** drag files to the notch (it opens as you get there) and drop them to park them. Later, drag them out to wherever they're going: an email, a folder, a chat. **AirDrop** sends everything on the shelf. The shelf keeps a pointer to each file, not a copy, and forgets files that have since been moved or deleted.

## Sample mail

Until the browser link is set up, the accounts (Personal, Work, Studio) and emails are made up, marked **Sample mail**, and archiving and replying only happen inside the app. Snooze is a placeholder for now.

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
| `TimetableAgent.swift`, `PlannerAgent.swift`, `AgentBlock.swift` | What the assistant is told about the timetable and the planner, and making the changes it asks for |
| `Planner.swift`, `DueDate.swift`, `Views/PlannerView.swift` | The planner: homework, exams, reading dates as people type them |
| `StudyPlan.swift` | Fits homework and revision into the free time on the timetable |
| `ClassroomMail.swift`, `PlannerMail.swift` | Reads Google Classroom's emails into the planner, on this Mac |
| `DueDateFinder.swift`, `PlannerMailReader.swift` | Finding due dates in other emails with the assistant (only when turned on) |
| `PhoneCable.swift`, `PhoneCableWatcher.swift` | The red dot while a phone is plugged in by USB, and what's known about it |
| `NowPlaying.swift`, `NowPlayingWatcher.swift` | What Spotify or Music is playing, and the buttons |
| `FocusTimer.swift` | The focus timer |
| `ClipboardHistory.swift`, `ClipboardWatcher.swift` | The last things you copied, in memory only |
| `Shelf.swift`, `Views/ExtrasView.swift` | The shelf for parked files; the extras row and panel |
| `Assistant.swift`, `AssistantEngines.swift`, `AssistantPrompt.swift`, `ClaudeCode.swift` | The assistant: Claude through Claude Code or the API, or Qwen through Ollama |
| `BrowserOpener.swift` | Opens Gmail and links in Chrome rather than the default browser |
| `NotchPanel.swift` | The window at the notch; hover, click and keyboard handling |
| `NotchPlacement.swift`, `Layout.swift` | Finds the notch and sizes each level |
| `NotchModel.swift` | State and actions: open, search, mark read and unread, reply |
| `Mail.swift`, `SampleMail.swift` | Account and message types, sample data. A real mail source plugs in by implementing `MailProvider` |
| `Updater.swift`, `ReleaseFeed.swift` | Checks this repo's releases and installs newer builds |
| `BrowserExtension/` | The **Notch Inbox Link** browser add-on |
| `BrowserLink.swift`, `HTTPRequest.swift` | Receives the add-on's feeds on 127.0.0.1 |
| `GmailFeed.swift`, `LiveMailbox.swift` | Reads Gmail's feeds, picks Primary or the whole inbox per account, keeps every email it has seen, and keeps the notch's own tally of read and unread |
| `WholeEmailStore.swift` | Whole emails on disk, one file each, up to the limit in Settings |
| `EmailContent.swift`, `Views/EmailWebView.swift` | Tidies whole emails and shows them (no scripts; links go to the browser) |
| `MailboxFile.swift` | The notch's mail lists, kept between launches |
| `BrowserExtension/mime.js` | Decodes whole emails in the add-on (MIME, base64, quoted-printable, charsets) |
| `BrowserExtensionInstaller.swift` | Puts the add-on where the browser can load it |
| `Views/` | The SwiftUI screens: resting notch, primary menu, lanes, expanded inbox, planner, timetable, notes, assistant, settings |
| `Theme.swift` | Colours from the design |
| `.github/workflows/release.yml` | Builds and publishes a release for every push to `main` |
| `.github/workflows/check.yml` | Builds a `check/…` branch without publishing, to try a change first |
