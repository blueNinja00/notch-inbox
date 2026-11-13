# Notch Inbox

A menu-bar app that turns the MacBook notch into an inbox for up to three email accounts, with a planner, a timetable, notes, an assistant and a room of AI agents beside it. Hover to peek, click to see your inboxes side by side, click an inbox to expand it.

It shows sample mail until you link your Gmail through the browser (below). **Settings** open inside the notch from the gear at its top right.

**New here?** The first time the app runs, the notch opens by itself with a **tour**: what the notch is, then a page each for Mail, the Planner, Assignments, the Timetable, Notes, the Assistant, Agents, the Extras, the themes, and what does and doesn't leave your Mac. It takes about a minute. See [The tour](#the-tour).

## Install

Paste this into Terminal (macOS 13 Ventura or later):

```sh
pkill -x NotchInbox; curl -fL --retry 4 --retry-delay 3 -o /tmp/NotchInbox.zip https://github.com/blueNinja00/notch-inbox/releases/latest/download/NotchInbox.zip && rm -rf "/Applications/Notch Inbox.app" && ditto -x -k /tmp/NotchInbox.zip /Applications && open "/Applications/Notch Inbox.app"
```

It downloads the newest build that has been released to everyone, puts **Notch Inbox** in your Applications folder (replacing any copy already there, after quitting it) and starts it. GitHub sometimes answers a download with a server error; it tries again a few times. To have it start when you log in, add it under **System Settings → General → Login Items**.

## Link your Gmail

Notch Inbox reads your mail through the browser where your Gmail accounts are already signed in (Chrome, Arc, Brave or Edge). No passwords, nothing to sign in to again.

1. Open the notch, click the gear at its top right, choose **Gmail link** and click **Set Up Browser Link…**. Finder opens with the **Notch Inbox Link** folder selected.
2. In the browser, open `chrome://extensions` (Arc: `arc://extensions`) and turn on **Developer mode**.
3. Drag the **Notch Inbox Link** folder onto that page.

Within a minute, the notch shows the unread mail of the first Gmail account signed in to that browser, with Gmail's unread count. Signed in to more than one? The others wait under **Add an inbox** in Mail; the notch shows up to three side by side (see [Choosing your inboxes](#choosing-your-inboxes)). Each inbox shows:

- **Primary tab, plus Google mail** for everyday accounts: Google Classroom, Docs, Drive and Calendar notices are included even when Gmail files them under Updates.
- **Whole inbox** (every tab) for an address made for receipts or sign-ups (a catch-all, say), since Gmail files that mail outside Primary.

Change either per account in **Settings → Mail accounts**.

### Choosing your inboxes

The notch starts with **one inbox**, and you choose the rest:

- **Add one:** while there's room, Mail has an **Add an inbox** column on the right listing the accounts that are linked but not showing. Click one and it appears beside the others. Up to three show side by side.
- **Take one out:** point at an inbox's name and click the **minus** that appears, or right-click the name and choose **Take Out of the Notch**. Its mail is kept, read and unread included, and it goes back under **Add an inbox**. The last inbox always stays.
- **Reorder:** right-click an inbox's name and choose **Move Left** or **Move Right**. The keys **1**, **2** and **3** and the counts beside the notch follow the new order.
- **Settings → Mail accounts** has the same choices in one list: a switch per account, and arrows to move it up or down.

An inbox that isn't in the notch isn't counted beside the notch, searched, read for homework or shown to the assistant. If you updated from a build that showed every account, the inboxes you had stay as they were; only accounts you link from now on wait to be added.

### Links open where that inbox is signed in

If you keep your accounts in separate Chrome profiles (Home and School, say), a link you click in an email opens in the profile that email's inbox is signed in to. A GitHub email that came to your home address opens in your Home profile, where you're signed in to GitHub; a Classroom link from your school inbox opens in School. **Open in Gmail**, a new message, and a planner task's link to its email or its Classroom page go the same way.

- **How it finds the profile:** Chrome keeps a list of its profiles and the account each is signed in with. The notch reads that list (`Local State` in Chrome's own folder) and, from each profile's settings (`Preferences`), only the addresses signed in there. An inbox goes with the profile signed in with its address; failing that, one where that address is signed in on the web; if two fit, the one you used last. Nothing in those files is changed, and none of it leaves your Mac.
- **Choosing it yourself:** **Settings → Mail accounts → Where links open** shows what was found for each inbox, and lets you pick a profile instead, or **Front window** for the old behaviour (whichever Chrome window is in front).
- **When nothing fits** (no profile has that address, or Chrome has only one profile), the link opens in the front window as before. Links that don't belong to an inbox (bookmarks, links in the assistant's answers and agents' reports) do too.
- It works with Google Chrome, and should with Brave and Edge, which keep profiles the same way. Chrome is asked by starting it with the profile and the page; a Chrome that's already running takes that over, so for a moment you may see a second Chrome icon in the Dock.

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

Every change pushed to this repository is built on GitHub's Macs and published as a numbered build (see [Releases](../../releases)), first as a test build and then, when it's ready, released to everyone (below). The app looks for a new build when it starts and every 2 minutes, by checking where github.com's "latest release" link leads. (Not GitHub's API, which allows apps that aren't signed in 60 questions an hour per network, shared by every app on it; it's only asked for a new build's notes, or when github.com doesn't answer. If a check you ask for fails, **Settings → Updates** says why.) When one is ready:

- an **Update** button appears at the top right of the open notch, and
- **Settings → Updates** shows the new build, its notes and an **Install** button.

Click either one to download the new build, swap it in and restart. Nothing installs without your click. **Settings → Updates** also has **Check for Updates** and shows which build you're running.

### Test builds, and releasing to everyone

A new build starts out as a **test build**. It's on the Releases page marked *Pre-release*, and only a copy with **Settings → Updates → Get test builds** switched on is offered it. Every other copy stays on the newest build that has been **released to everyone**, and the install command above installs that one. So a build can be tried on one Mac before anyone else gets it.

- **Get test builds** is off on a copy installed fresh. (On a copy that was already in use when Build 43 brought the switch in, it starts on.) Test builds are newer and sometimes broken. Switch it off and the copy goes back to being offered released builds only; it keeps the build it has until a newer one is released.
- **Releasing a build** is done by the repository's owner, once the test build has been tried. In the app: **Settings → Updates → Release Build N to Everyone…**, which opens the page on GitHub. Or go there yourself: the repository's **Actions** tab, **Release to everyone**, **Run workflow**, type the build's number, **Run workflow**. Within a couple of minutes every copy is offered that build. Builds in between that were never released are skipped.
- With test builds on, Settings says which build everyone is offered and whether this Mac is ahead of it.

How the app finds a test build: GitHub's "latest release" link never points at one, so with test builds on the app also asks github.com whether the next few builds after its own have a page yet (stopping after three in a row that don't), and, as a backstop, asks GitHub's API at most every half hour for the number of the newest build made (in case several builds in a row failed to publish).

## Settings

Click the gear at the top right of the open notch. Settings open inside the notch, with a section per topic down the left:

- **General:** the theme (below), which tools are on the primary menu and in what order, Notch at the top or Mail tab, resetting panel sizes, and **Show the Tour**.
- **Mail accounts:** which inboxes show in the notch and in what order; per account, Primary or Whole inbox, and which browser profile its [links open in](#links-open-where-that-inbox-is-signed-in); how much mail is kept on this Mac, and how many emails to keep in full.
- **Assistant:** who answers (below), which Claude model, and a switch for each thing it may see and do: look things up on the web, your timetable, your planner, your assignments and marks, your bookmarks, handing jobs to agents, and your newest emails and notes. Then your saved [chats](#your-chats), the [usage](#usage) count and the daily cap for agents, [typing into your documents](#typing-into-your-documents) and the permission macOS wants for it, and the [agents](#agents): how many work at once, whether they use the web, the chime, and the folders they may read.
- **Timetable:** school as one block or periods, hour blocks before and after school, weekends, Week A and Week B, and clearing every lesson for a new term.
- **Extras:** switches for now playing, the focus timer (and its lengths), clipboard history, the shelf, and volume and brightness at the notch (with **Keep them beside the notch** and **Hide macOS's own pop-up**).
- **Shortcuts:** the keys for the Agents room and for getting around the notch, each one yours to [change](#shortcuts).
- **Planner:** whether Google Classroom emails add homework, whether the assistant looks for due dates in your other emails (off to start with for Claude), planning study time, and clearing finished homework.
- **Gmail link:** whether the browser add-on is working, set it up, show its folder, and **Copy Debug Info** (counts and addresses only, never what your emails say).
- **Updates:** your build, checking and installing, whether this Mac gets test builds, and releasing a build to everyone.
- **Quit Notch Inbox**, at the bottom.

**Themes:** **Settings → General** has eight to pick from: **Midnight** (black and grey with white buttons, the one it starts with), **Graphite** (softer greys), **Ocean**, **Forest**, **Sunset**, **Grape** and **Rose** (each washes the tiles and panels with its colour and uses it for buttons, whatever's selected, today and unread dots), and **High contrast** (brighter text, yellow buttons). The notch itself stays black in all of them, like the camera housing it hangs from. Every theme's text is checked to read clearly on its backgrounds.

**Your own theme:** the ninth swatch, **Your own**, is one you make. Pick the **colour** that washes the tiles and panels (sixteen to click, or type any hex code such as `#5E9EFF` and press Return), **how much** of it (subtle, medium or strong), whether the **tiles** are darker or lighter than standard, and the **accent** for buttons, today and whatever's selected (the colour itself, or another). Whatever you choose, the app keeps the text readable and the tiles dark enough to sit on the black notch: a colour too dark to see is brightened for buttons, and very bright choices are toned down. That's also why there's no light theme: the notch is black, so what's written on it has to be light.

An envelope in the menu bar has a short menu too (Open, Settings…, Quit), as does right-clicking the mail tab. On a MacBook, macOS hides menu-bar icons that don't fit beside the notch, so the gear is the reliable way in.

## The assistant

Your chief of staff: ask it anything, not only about your day. It answers questions, explains things, drafts and checks writing, keeps your planner, timetable, assignments and bookmarks in order when you ask, and hands bigger jobs to [agents](#agents). In **Settings → Assistant**, pick who answers:

- **Claude, with your Claude plan** (the default): answers through [Claude Code](https://claude.com/claude-code) on your Mac, signed in to your Claude account, so it counts toward your plan's usage and needs no API key. Install it once in Terminal with `curl -fsSL https://claude.ai/install.sh | bash`, then type `claude` and sign in. Each question runs Claude Code in a folder of its own with no skills or MCP servers, and nothing is saved to your Claude Code history. The only tools it has are searching the web and reading pages (**Look things up on the web**, on to start with); it can't run commands or touch files. While it's looking something up, the chat says what it's searching for or reading.
- **Claude, with an API key:** paste a key from [console.anthropic.com](https://console.anthropic.com); you pay Anthropic per question. The key is kept in `~/Library/Application Support/Notch Inbox`, readable only by you.
- **Qwen, on this Mac:** runs locally through [Ollama](https://ollama.com); free and private, but slower and less capable. Settings shows the one Terminal command to download the right Qwen model for your Mac's memory (several GB).

For Claude, pick **Haiku 5.5** (fastest), **Sonnet 5.5** (the default) or **Opus 5.5** (smartest). **See and change my timetable** and **See and change my planner** (both on to start with) let it read your timetable, homework and exams, and change them when you ask. **Share my newest emails and notes** lets it see the last 30 days of email the notch holds (sender, subject and time of up to 120 emails, and the opening words of the newest 25) and your latest notes. The notch only holds mail it has seen since Gmail was linked; **Settings → Mail → Fetch the Last 30 Days** fills in the month before, once: the add-on opens Gmail in a background tab for each inbox, searches the last 30 days, reads the list off the page (sender, subject, preview; read mail too) and closes the tab. Nothing in Gmail is clicked or changed, and the list goes only to the app. It reads Gmail's page as it's laid out today, so a change at Google's end can stop it working; Settings says how it went. Agents never see your mail: the assistant writes what matters into their jobs. With Claude they're sent to Anthropic with your question, so it starts off; with Qwen they stay on your Mac, so it starts on.

It can also see and change your **assignments and marks** ("I got 17 out of 20 on the Chemistry prac", "add an English essay due the 20th, worth 25%") and your **bookmarks** ("bookmark Desmos under Maths"), and **hand jobs to agents** ("get an agent to find sources on the Cold War"). Each has a switch in **Settings → Assistant**, on to start with. It only changes anything when you ask, and its answer ends with a line saying what it changed. Links in its answers open only if they're web addresses.

**How answers look:** an answer is drawn from its formatting, so headings, bullet and numbered lists, tables (with their columns lined up), quotes and blocks of code show as what they are, not as the symbols they're written in. The same goes for agents' reports and the team chat. Maths written in LaTeX can't be drawn, so the assistant is asked to write it in ordinary characters (x², √2, a/b), and any LaTeX that slips through is put into them. Your own messages are shown exactly as you typed them.

**Reports come back by themselves:** when an agent the assistant started for you finishes, its report arrives in the chat you asked in, as a message of its own: you don't have to go to the Agents room for it. A [chain](#agents) reports once, when its last agent is done. If an agent can't finish, the chat says why and shows what it had written. The building button beside the message opens that agent in the Agents room, where its steps and files are. If you're in another chat when it arrives, the chat it belongs to gets a dot in the list, and the Assistant tile on the primary menu says a report is back. Your next message to the assistant takes the report along (its first 4,000 characters, marked as information), so you can say "make it shorter" straight away. An agent you start yourself in the Agents room doesn't report to a chat, and neither does one you stop. **Settings → Assistant → Send reports back to the chat** turns it off.

### Your chats

- **They're kept.** Chats are saved on your Mac, in `~/Library/Application Support/Notch Inbox/Chats.json` (readable only by you), so they're still there after you quit, restart or update. Opening the assistant puts you back in the chat you were in, at its newest message.
- **Several at once.** The list down the left of the assistant has every chat, the latest first, each named after its first question. **New chat** starts another (the one you were in stays in the list); click any chat to go back to it. Point at one and click the cross, or right-click it, to delete it.
- **How many.** The newest 30 chats are kept, and the newest 200 messages of each. The assistant is sent the last 20 turns of the chat you're in, not the others. **Settings → Assistant → Delete All Chats…** clears the lot.
- An answer that was still being written when the app quit is dropped; your question stays.

### Typing into your documents

The assistant can put its answer straight into what you're writing, and work on what you've written.

- **Type an answer in:** beside every finished answer there's a **keyboard** button. Click in your document first (Pages, Word, Google Docs, Notes, an email…), then open the notch and click it: the notch closes and the answer is typed where your cursor is, replacing anything selected. It goes in as plain text: no Markdown stars, bullets as dots, and a table as tab-separated rows, which paste into a table. The button's tip names the app it will type into. The copy button beside it just copies.
- **Work on what you've written:** select some text in your document, open the assistant and click **Use Selection** under the chat. It's attached to your next question ("make this more formal", "is this argument clear?", "shorten to 100 words"). Asked to rewrite, the assistant answers with only the new text, so the keyboard button swaps it in for what you selected. **Use Copied** attaches whatever you've copied instead, and needs no permission.
- **The permission:** typing and reading a selection mean pressing keys in another app (⌘V and ⌘C), which macOS only lets an app do if you allow it under **System Settings → Privacy & Security → Accessibility**. **Settings → Assistant → Allow…** asks for it. Without it, the keyboard button copies the answer and the chat tells you to paste it with ⌘V. Because Notch Inbox isn't signed by a registered developer, macOS treats each update as a new app and asks again after every one; **Allow…** clears the old entry and asks afresh.
- **How it's done:** to type, the answer is put on the clipboard (marked as momentary, so clipboard histories skip it), ⌘V is pressed in the app you were in, and your clipboard is put back as it was. To read a selection, the app is asked directly; if it can't say (Google Docs and most web pages can't), ⌘C is pressed, the clipboard is read, and your clipboard is put back. ⌘V and ⌘C are pressed by their place on a standard keyboard, so on a Dvorak layout use Use Copied and paste by hand.
- **What's read, and where it goes:** nothing in your documents is read unless you click Use Selection, and the clipboard only when you click Use Copied (a copy a password manager marked private is left alone). What you attach goes with that one question: to Anthropic with Claude, nowhere with Qwen. Up to 12,000 characters are attached.

### Usage

Everything the notch asks of Claude counts toward your Claude plan like any other use, so it keeps its own count.

- **Settings → Assistant → Usage** shows today, the last 7 days and the last 30, in tokens (a token is about three-quarters of a word), with where the week's went: questions, agents, the team chat, and planning and reading. Re-reading what's already been read, which is most of what an agent does, counts at a tenth, as it does for cost.
- The dollar figure beside it is Claude Code's own estimate of what the same use would cost at API prices. On a plan you aren't charged it; it's a yardstick for how big a run was.
- **Each task's page** shows what its agent has used so far while it works, and what the job came to when it's done. The agent room's top row shows today's total; click it for the rest.
- **Daily cap for agents** (off to start with): once the notch has used that many tokens in a day, new agents are held, saying so in their row, until tomorrow or until you raise the cap. Agents already working carry on, and you can still ask questions.
- It's the notch's count, not Anthropic's: it doesn't see your other use of Claude and can't know your plan's limits. Your plan's real meter is in Claude's own **Settings → Usage**. An agent you stop part-way is counted by what it had read, without the cost. With an API key, tokens are counted without a cost; Qwen runs on your Mac and isn't counted.
- The count is kept in `~/Library/Application Support/Notch Inbox/Usage.json`, readable only by you: totals for each of the last 120 days, and the last 60 runs.

## Agents

The **Agents** tile opens the agent room, where tasks are sorted into groups and each group shows how it's going. An agent is a separate AI that takes one task and works on it by itself, over many steps, while you do something else: finding and reading sources, writing study notes, comparing things, planning an essay.

- **Add tasks, then start them:** type a task in the box along the bottom and press Return. Say what you want back ("…summarise each in a paragraph, with links"). It joins the group that's showing as **Ready** and waits there. Press the play button on its row to start it, or **Start All** to start everything in the group that's ready, so you can line up a batch first. Until a task is started you can change its job on its page, and right-click → **Duplicate** adds a ready copy. Or ask the assistant, and it writes the jobs and starts the agents for you straight away; those have a small sparkle beside their name.
- **Groups:** the side of the room lists your groups of tasks. **General** is always there; the **+** beside Groups makes another (up to twelve), and typing over its name at the top renames it. Each group has a **status bar**: green for what's done, then what's working (it breathes), what's waiting its turn, red for what couldn't finish and amber for what was stopped; tasks not started yet are the empty rest of it. Beside the name is how many are done out of how many. Open a group and its top row has **Start All**, **Stop All** and **Clear Done**, and a line that counts its tasks by state and the tokens they've used. Right-click a task for **Move to Group**; right-click a group to rename or delete it (its tasks go to General). Ask the assistant to "put these in my Biology group" and it does; research started from an assignment goes in the group named after its subject, if you have one.
- **Chains:** switch on **Chain** beside the box and the job goes to three agents in turn, not one. A **researcher** finds the sources and saves its notes; a **writer** works from those notes and marks anything they don't support; a **checker** opens the links, corrects what's wrong, and ends its report with a "Checked" list: what it confirmed, what it changed, and what it couldn't verify. Each one is a task of its own in the same group, and starts by itself when the one before finishes, with that agent's report and the files it saved (to read, not change). The strip above an agent's report shows the whole chain; click a stage to see the agent that did it. If a stage can't finish, or you stop it, the chain ends there: **Again** does that stage again and the chain carries on from it, and **Carry On** starts the next agent on what was left. Agents a chain still needs stay in the room until it's done. A chain uses about three agents' worth of your plan, so Chain switches itself off after each one. The assistant can start a chain too, when you ask it for something that has to be right. The chime sounds once, at the end.
- **Watch them work:** a group's tasks are a table, newest on top, each numbered from the first task you ever gave. A row shows what its agent is doing right now ("Searching the web for…", "Reading bbc.co.uk", "Writing Notes.md") in the colour of its state, how long it has been going, and a line along the bottom that breathes while it works. The buttons at the end of the row start it, stop it or run it again, and remove it. Click a row for the task's own page: its job, every step it has taken, and what it's writing. The arrow at its top left, or Esc, goes back to the table.
- **The report:** when an agent finishes there's a chime (Settings can turn it off) and its report is on its page, with headings, lists and tables drawn properly. If the assistant started it, the report also arrives in the chat you asked in (see [The assistant](#the-assistant)). **Copy** copies it, the file chips open what it saved, **Again** gives the same job to a new agent, the folder button opens its folder, the book saves its job as a [recipe](#agents), and the bin takes it out of the room (its report stays in the Library, and its files in its folder).
- **The library:** every report an agent finishes is kept, so it's still there after the agent has left the room. **Library**, in the side of the room under your groups, lists them newest first; a chain's research notes, draft and checked version are kept together under the chain's name, each on its own tab. The search box looks through names, jobs and the reports themselves, and shows the words around what it found. Open a report to read it, copy it, open the files its agent saved, or type over its name to rename it. **Pin** files it under a subject (your timetable's classes, and your assignments' subjects) or onto an assignment, where it then shows under **Reports**; research started with **Research This** is pinned to its assignment by itself. Click a subject above the list to see only what's pinned to it. The newest 120 reports are kept, the unpinned ones going first, in `~/Library/Application Support/Notch Inbox/Reports.json` (readable only by you). Deleting a report from the library leaves its agent's files where they are. The button on a report the assistant put in your chat opens it here once its agent is gone.
- **Recipes:** a job you hand out often can be saved and run again. **Recipes**, under Library, has a few to start from (practice questions, finding sources, study notes, a comparison, an essay plan, a checked explainer); they're yours to change or delete. Write anything that changes each time in curly brackets, like `Write {number} practice questions on {topic} for {subject}`: each blank gets a box. **Add to General** (or whichever group is showing; Return in a box does the same) adds a run to that group, ready to start, and leaves you on the recipe with its boxes emptied, so you can line up one run after another; **Start Now** hands it out straight away. The agent is named after the recipe and what the run is about ("Practice questions: enzymes"). The **Chain** switch on a recipe sends it to a researcher, a writer and a checker. To keep a job as a recipe, type it in the box along the bottom and click the **book** beside it (it's saved, not started), or open an agent and click the book beside its name to save the job it was given (right-clicking its row offers the same). A recipe with no blanks has a **Run** button in the list. The assistant knows your recipes too: ask for one by name ("run my practice questions recipe on enzymes for Biology") and it can fill in the blanks and start it. Recipes are kept in `~/Library/Application Support/Notch Inbox/Recipes.json` (readable only by you); with Claude, their names and jobs go to Anthropic with your questions while **Hand jobs to agents** is on.
- **Team chat:** **Team chat**, in the side of the room, opens a chat that working agents share with the chief of staff and you. Agents read it before they start (it lists who's working on what, so they don't double up) and as they go, post what they find or need, and can ask the chief with `@chief`. Type in the box along the bottom to say something to everyone: the chief answers you, and can start or stop agents if you ask it to there. An agent may post eight times a job, the chief answers at most thirty times an hour, and only you (never an agent) can have agents started. In the chat the chief knows the jobs and your assignments, not your mail or notes. Agents read the chat as a file (`~/Notch Agents/Team Room/chat.md`) and post by writing `to-team.md` in their own folder; it needs Claude on your Claude plan. **Settings → Assistant → Team chat** turns it off.
- **A few at a time:** up to three work at once to start with (one to four, in Settings); the rest wait their turn. **Stop** stops one and keeps what it had written. An agent that's still going after 25 minutes is stopped. Quitting the app stops them all.
- **What an agent can do**, with Claude on your Claude plan: search the web, read pages, and read and write files in a folder of its own inside `~/Notch Agents`. That's all. It has no way to run commands, and it can't see your mail, your notes, your planner or any other file. It knows only the job it was given.
- **Folders agents may read:** for a job that needs your own files (notes to revise from, say), add a folder in **Settings → Assistant**. Agents can read it and can't change it. Whole disks, your home folder, your Library and hidden folders can't be added. An agent that reads a folder and also uses the web could be tricked by a web page into passing on what it read, so only share folders with nothing private in them. If the folder is in Documents, Desktop or Downloads, macOS asks whether Notch Inbox may use it, and asks again after an update.
- **With an API key, or Qwen**, an agent can only think and write: no web, no files. Its report is still kept in the room.
- **What goes online:** the job you type, what the agent reads and writes while it works, and what it searches for all go to Anthropic (with Qwen, nothing leaves your Mac). Each agent is its own run of Claude Code, so it counts toward your plan's usage like any other use of Claude.

Under the hood each agent is `claude -p` with only the web and file tools switched on, in Claude Code's **restricted mode**: Claude Code itself keeps the file tools to the agent's folder (and the folders you shared, which it's also told it may not edit) and loads none of your Claude Code settings. A Claude Code too old for restricted mode is run without it, with only your own settings loaded and writing to `.claude` in the agent's folder refused. Text from web pages is treated as information, never as instructions, and links in a report open only if they're web addresses. In a chain, what one agent hands the next is marked the same way: material to work from, not instructions. A file an agent saved opens with a click only if it's a plain document (text, Markdown, CSV, PDF, an image); anything else is shown in Finder for you to decide. The room is kept in `~/Library/Application Support/Notch Inbox/Agents.json`, readable only by you: the 30 newest finished agents, with their reports.

## Shortcuts

The Agents room has keys for everything in it, and **Settings → Shortcuts** lets you change every one. They work while the notch is open and you've clicked in it, even while you're typing a task. The keyboard button at the top right of the Agents room opens the list.

| Key | What it does |
|---|---|
| ⌘N | New task: the cursor goes to the box |
| ⌘↩ | Start all the ready tasks in the group |
| ⌘. | Stop everything in the group |
| ⌘↓ ⌘↑ | Select the next or the previous task |
| ⌘S | Start or stop the selected task |
| ⌘O | Open or close the selected task |
| ⌘D | Run the selected task again |
| ⌘⌫ | Remove the selected task |
| ⇧⌘⌫ | Clear finished tasks from the group |
| ⌘] ⌘[ | Next or previous group |
| ⇧⌘N | New group |
| ⌘K | Switch Chain on or off |
| ⌘L ⌘R ⌘T | Library, Recipes, Team chat |
| ⌘F | Search the library |

- **Change a key:** click it in Settings → Shortcuts and press the keys you want. It has to include ⌘, ⌃ or ⌥ (or be an F-key), so that it can't be typed by accident; the keys for cut, copy, paste, select all, undo and ⌘Q can't be used. Esc gives up, and Delete takes the key off. If another shortcut had those keys, it loses them, and Settings says so. The arrow beside a changed key puts it back; **Put Them All Back** resets the lot.
- **Going places:** the same page has shortcuts for the primary menu, each tool and Settings. They come with no key; give the ones you want a key and they work anywhere in the open notch.
- **Keys that also edit text:** ⌘⌫ and ⌘ or ⌥ with an arrow are left to the text while there's something typed in the box you're in, so ⌘⌫ still clears a line you're writing.
- Shortcuts are for the open notch only: nothing is listened for while the notch is closed or another app is in front.

## The tour

The first time Notch Inbox runs, and once after updating to the first build that has it, the notch opens with a tour of what everything does. Each page has a sentence on what a tool is for, a few things worth knowing, and the real thing beside it as it looks right now: Mail's tile with your mail, the Planner's with your homework, the themes to click and try.

- **Next** and **Back** (or the **←** and **→** keys, once you've clicked in the panel) turn the pages; the dots jump to any page.
- Most pages have a button that opens the real tool: **Open the Planner**, say. The tour waits, and a **Tour** button at the top left of every tool takes you back to the page you were on.
- **Skip the Tour** or **Done** closes it for good. Clicking away or pressing Esc only puts it aside: until it's finished or skipped, the primary menu has a **Take the Tour** button at its top right.
- **Settings → General → Show the Tour** opens it again whenever you like.

The tour is worded for how the app is set up: it says so if you're still on sample mail, names whichever assistant you've chosen, and lists what's left to set up on its last page.

## Using it

It shows on every screen: in the MacBook's notch, and as a notch-shaped tab at the top of any external display. It appears on every desktop (Space) too, including full-screen apps. Only one notch opens at a time.

- **Glance:** unread counts for each account sit beside the notch, in full (3992, not 4k; only 10,000 and up are shortened). Accounts with nothing unread are left out.
- **Phone plugged in:** a red dot appears on the left of the notch while your phone (an iPhone, or an Android phone) is connected to the Mac by USB cable, and the primary menu names it. In Mail tab mode the dot sits on the tab. Wireless connections don't count. The app hears about it from macOS the moment a USB device comes or goes. Click its name for its maker and how fast the cable is. An iPhone's battery level shows too if you've installed [libimobiledevice](https://libimobiledevice.org) (`brew install libimobiledevice`) and the phone trusts this Mac; macOS doesn't tell apps that by itself. Otherwise nothing is read from the phone.
- **Hover the notch:** the primary menu drops down, with one tile per tool: **Mail** (total unread, the newest email, each inbox's count), **Planner** (what's due next and your next exam), **Timetable** (the class you're in now and the next one), **Assignments** (what's due next and how many steps are done, or your average), **Notes** (how many, and the latest), **Assistant**, **Agents** (how many are working, and the latest one's news) and **Bookmarks** (your first few links, each a click away). With all eight showing they sit in two rows, Mail down the left with your newest emails. Your next exam counts down beside the date once it's within three weeks. Click anywhere on it to keep it open.
- **Arrange the primary menu:** right-click a tile for **Move Left**, **Move Right** and **Hide from the Primary Menu**, or open **Settings → General → Primary menu** for the whole list, with a switch and arrows for each tool. The last tile always stays. Up to five tiles sit in a row at the usual width, six in a slightly wider one, and more than six in two rows. If you'd dragged the menu to a size of your own, it goes back to standard when the number of tiles changes, so they aren't squashed.
- **Planner:** homework, exam countdowns and a study plan. See [Planner](#planner).
- **Extras:** a row under the tiles with what's playing, a focus timer, clipboard history and a shelf for files. See [Extras](#extras).
- **Assistant:** your chief of staff. Chat with Claude (or Qwen, on your Mac) about anything: it can look things up, keep your planner, timetable, assignments and bookmarks in order, and hand bigger jobs to agents. See [The assistant](#the-assistant).
- **Agents:** sort tasks into groups, start them, and watch each agent work. See [Agents](#agents).
- **Timetable:** your school week, Monday to Friday, with every class in its subject's colour. See [Timetable](#timetable).
- **Notes:** a list on the left, the note on the right; it saves as you type, and the first line is the title. The expand button makes it bigger. Notes are kept in `~/Library/Application Support/Notch Inbox/Notes.json`, readable only by you.
- **Make it bigger:** drag the bottom edge of the open panel, or the grip in its bottom-right corner (it grows on both sides, staying centred on the notch). Double-click the grip for the standard size. Sizes are remembered.
- **Click the Mail tile:** it opens into a lane per inbox: one to start with, and up to three once you [add more](#choosing-your-inboxes). The grid button at the top left goes back to the primary menu.
- **Click a lane's header, or any email in it:** that inbox expands, with the list on the left and the full email plus a reply box on the right. The other inboxes shrink to slim tabs at the sides; click one to switch.
- **Click outside, or press Esc** to close. Esc steps back one level: email → inboxes → primary menu → closed. (In the agent room it first goes back from a task's page to its group, or from an open report or recipe to its list.)
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

## Assignments and marks

Click the Assignments tile on the primary menu. It has two halves, switched at the top: **To Do** and **Marks**.

**To Do** is for the bigger pieces of work: an essay, a project, a prac report.

- The **+** at the top adds one. In the side panel, say what it is, its subject, when it's due and what it's **worth** (as a percentage of the subject's mark, if you know).
- **Or give it the task sheet.** Drag the sheet onto Assignments (or onto its tile on the primary menu), or click the page-with-a-plus button and choose it: a PDF, a Word or text file, or a photo or screenshot of the sheet. The words are got out on your Mac (photos and scanned PDFs with macOS's own text recognition), the assistant picks out the title, subject, due date, weighting, total marks and a first set of steps, and the new assignment opens for you to check. The brief holds a short version of what's asked, then the sheet's own words. Check the due date: a sheet that leaves out the year, or says "Week 6", is a guess. With Claude, the sheet's words are sent to Anthropic to be read; with Qwen they stay on your Mac. If the assistant can't be asked, the assignment is still made, named after the file, with the sheet's words in its brief. macOS may ask whether Notch Inbox can read your Downloads or Documents folder the first time.
- **Break into Steps** plans it. Paste the task sheet into **What the task asks** first and the assistant reads it and writes four to eight steps for this assignment, each with a time. It only plans: it doesn't write any of the work. With Claude, the assignment's name, subject, due date, task sheet and notes are sent to Anthropic when you click the button, and at no other time; with Qwen it stays on this Mac. If the assistant isn't set up, or can't answer, the usual steps for that kind of work go in (an essay, a talk, a prac, or anything else) and a note says so.
- **Research This**, under the task sheet, sets three agents on the assignment, one after another. A researcher finds sources you could cite, with the facts and quotes that matter and where each came from. A planner turns those and the task sheet into a plan to write from: what's really being asked and how it's marked, a structure with the point and the evidence for each part, and a checklist against the criteria. A checker goes back to the sources and corrects the plan. They plan it; they're told not to write any of it, because the writing is yours. The panel says how they're going, **See It** opens the agent room at them, and the checked plan is in the last agent's report and saved as a file in its folder. Their reports are kept in the [library](#agents), pinned to the assignment, and listed under **Reports** in its panel along with any other report you pin to it. Name the assignment first; with the task sheet filled in, the research fits what's being asked. With Claude, the assignment's name, subject, due date, task sheet and notes are sent to Anthropic, along with what the agents search for; with Qwen it stays on this Mac, and the agents work from what the model knows. Only Claude on your Claude plan lets the agents use the web. You can also just ask the assistant ("get my Macbeth essay ready"): it starts the same three agents, and they're given that assignment's task sheet as long as the assistant is allowed to see your assignments.
- The steps are yours to change: rename one by typing over it, click its time to change how long it takes, point at it for arrows to move it and a cross to remove it, and add your own underneath. **Plan Again** replaces the steps still to do and keeps the ones you've ticked off.
- **The planner fits the steps into your week.** Every step still to do shows in the Planner's plan and in the timetable's free slots, before the assignment is due, in order. An assignment with no steps yet gets an hour to make a start. Click a planned step to come back to its assignment.
- **Handed In** moves it to "waiting for a mark". When the mark comes back, type it in the same panel.

**Marks** is the marks tracker.

- Each subject shows its **average**. If you've said what results are worth, it's weighted by that; if not, it's a plain average. **Overall** at the top is the average of your subjects, each counting the same.
- The **+** adds a result that didn't come from an assignment: a test or an exam. Type the mark the way it's written: `17/20`, `85%` or `17 out of 20`. Exams in the planner that are over appear at the bottom of the list with **Sat it? Add your mark**.
- Set a **goal** for a subject with the − and + (in fives). Marks at or above it are green, a little under amber, well under red, and a sentence says what it takes: "You need an average of 82.7% on the remaining 55% to finish on 80%", or that you're already there, or that it's out of reach and where full marks would get you. That sum needs the weights: what's still to come is taken as 100% less what's been marked.

Assignments and marks are kept on this Mac, in a file only you can read.

## Bookmarks

Click the Bookmarks tile on the primary menu (anywhere but on a bookmark) for the links you use every day: the school portal, Classroom, a textbook, a past-papers page.

- **Add one:** type or paste it in the box at the top and press Return. A link by itself is named after its site; put a name before or after it ("Maths textbook https://…") to name it yourself. **Paste** adds the link on your clipboard. You can also **drag a link** from your browser onto the page, or onto the Bookmarks tile.
- **Open one:** click it, here or on the tile. It opens in your browser.
- **Edit one:** point at it and click the pencil, or right-click it. The side panel changes its name, its link and its **group** (Maths, say). Groups appear as chips above the bookmarks; click one to see only that group.
- **Reorder:** right-click → **Move Earlier** or **Move Later**. The tile shows the first few, so put the ones you use most first.
- Only web pages (http and https) can be bookmarked, and a link you already have isn't added twice.

Bookmarks are kept on this Mac, in a file only you can read. No page is fetched when you add one, which is why each gets a letter on its site's colour, not the site's icon.

## Extras

A row under the primary menu's tiles. Click any of them for the **Extras** panel, which has more room. Each can be switched off in **Settings → Extras**.

- **Now playing:** the song in Spotify or Music, with previous, play or pause, and next. What's playing comes from the notices those apps post when it changes, so it appears the next time the song changes or you press play. The first time you press a button, macOS asks whether Notch Inbox may control that app (say OK); because each update is a new build, it may ask again after one. It never starts a music app, and nothing is looked up online.
- **Focus timer:** press play for a round of focus (25 minutes, or 15, 45 or 50), then a break (5, 10 or 15). The minutes left show beside the closed notch; when time's up there's a chime and the notch opens. In the planner, point at a stretch in the Plan and click its timer to focus on that for as long as it's planned; afterwards one click ticks the homework off.
- **Clipboard history:** the last 30 things you copied; click one to copy it again. They're held in memory only: never saved to disk, never sent anywhere, never shown to the assistant, and gone when the app quits. Copies that password managers mark as private are skipped, and **Clear** forgets the lot.
- **Shelf:** drag files to the notch (it opens as you get there) and drop them to park them. Later, drag them out to wherever they're going: an email, a folder, a chat. **AirDrop** sends everything on the shelf. The shelf keeps a pointer to each file, not a copy, and forgets files that have since been moved or deleted.
- **Volume and brightness:** two small gauges sit beside the closed notch all the time: the volume on the left, the brightness on the right, each a symbol over a short bar (**Settings → Extras → Keep them beside the notch** turns that off). Change either one (with the keyboard's keys, Control Centre or anything else) and the notch shows it bigger for a moment: a speaker or a sun on the left, a bar on the right. The Extras panel has a slider for each, and clicking the speaker mutes. This needs no permission. Volume is whatever output you're using; an output with no volume of its own (some screens) says so. Brightness is this Mac's own screen, read and set through a framework of macOS's own that isn't part of its public kit, so if a future macOS changes it, brightness simply stops showing. To notice brightness changing, the app asks macOS for it about three times a second. Nothing shows while the notch is minimised to the mail tab.
- **Hide macOS's own pop-up** (off to start with): the notch takes over the volume, mute and brightness keys and changes them itself, in the same sixteen steps (quarter steps with Shift and Option), so macOS's pop-up doesn't appear as well. Only those keys are looked at; every other key passes untouched. It needs the same Accessibility permission as [typing into your documents](#typing-into-your-documents), and macOS asks again after each update; until it's allowed, the keys work as usual and both show. With a second screen plugged in, the brightness keys are left to macOS.

## Sample mail

Until the browser link is set up, the accounts and emails are made up, marked **Sample mail**, and archiving and replying only happen inside the app. Like your own mail, it starts with one inbox (Personal); Work and Studio are under **Add an inbox**, so you can try adding, taking out and reordering. Snooze is a placeholder for now.

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
| `Chats.swift` | Your chats with the assistant: several of them, kept between launches |
| `Usage.swift` | The count of what the notch has used: reading it from Claude Code, totals by day, and the daily cap |
| `AssignmentSheet.swift`, `SheetReader.swift` | Reading a task sheet into an assignment: getting the words out of the file, and turning the assistant's reading into its details |
| `TeamChat.swift` | The team chat: its messages, the file agents read, and what agents and the chief are told about it |
| `StaffAgent.swift` | What the assistant is told about its agents, your assignments and your bookmarks, and making the changes it asks for |
| `Typing.swift`, `DocumentTyper.swift` | Typing an answer into the app you were in, reading what's selected there, and turning an answer into plain text |
| `Levels.swift`, `SystemLevels.swift`, `MediaKeyTap.swift` | Volume and brightness: reading and setting them, deciding when to show them at the notch, and taking over their keys |
| `Agents.swift`, `AgentGroups.swift`, `AgentRunner.swift`, `Views/AgentsView.swift`, `Views/AgentGroupsView.swift` | Agents: their jobs and groups, running each one with Claude Code and reading what it does, drawing reports, and the agent room |
| `Keybinds.swift`, `Views/ShortcutsView.swift` | Shortcuts: what each key does, and changing them |
| `BrowserOpener.swift`, `BrowserProfiles.swift`, `Views/LinkPlacesView.swift` | Opens Gmail and links in Chrome rather than the default browser, in the profile the inbox is signed in to: reading Chrome's list of profiles, matching an inbox to one, and the choice in Settings |
| `NotchPanel.swift` | The window at the notch; hover, click and keyboard handling |
| `NotchPlacement.swift`, `Layout.swift` | Finds the notch and sizes each level |
| `NotchModel.swift` | State and actions: open, search, mark read and unread, reply; which inboxes show; where the tour is up to |
| `Tour.swift`, `Views/TourView.swift` | The tour: what each page says for how the app is set up, whether it has been seen, and how it's drawn |
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
| `Views/` | The SwiftUI screens: resting notch, primary menu, lanes, expanded inbox, planner, assignments, timetable, notes, bookmarks, assistant, agents, settings, tour |
| `Theme.swift`, `ThemePalette.swift` | The themes: each one's colours, the one you make yourself, and the sums that keep text reading clearly |
| `HomeMenu.swift` | Which tools have a tile on the primary menu, in what order, and how they're laid out |
| `Assignments.swift`, `Views/AssignmentsView.swift` | Assignments and their steps, planning one with the assistant, the marks tracker's sums, and their screens |
| `Bookmarks.swift`, `Views/BookmarksView.swift` | Bookmarks: reading a typed or dropped link, the saved list, the page and the tile |
| `.github/workflows/release.yml` | Builds and publishes a release for every push to `main` |
| `.github/workflows/check.yml` | Builds a `check/…` branch without publishing, to try a change first |
