# Channels: where our users discover tools

Researched 2026-10-15. Nothing here has been posted or submitted. "Needs owner
account" means a human with a real, aged account must act; agents must not
create accounts or post.

Start state (from GitHub, 2026-10-15): 7 stars, created 2026-09-02, MIT, about
34 unique visitors per 2 weeks, 6 to 38 downloads per release.

## How to read the numbers

- Reddit member counts come from a Redlib mirror on 2026-10-15. Reddit itself
  blocks scripted reads, so I could not fetch each subreddit's official rules
  page. Where I quote a rule below, the source is named. Where I could not
  retrieve the rule text, it says so. **The owner must read the live rules
  page of a subreddit before posting.**
- Hacker News timing is my own calculation from the public Algolia HN API
  (24,701 Show HN posts, the last 30 weeks). It is a weak signal; see the HN
  entry.

## The honest picture

The category "control a coding agent from your phone" is crowded. On Hacker
News, Show HN posts for Paseo got 14, 6 and 5 points; Happy Coder 30; CC Pocket
2; CC Remote 3; MobileCode 7. A Show HN will not by itself bring users.
What we have that the others do not (verify before claiming): the agent
**runs on the phone** (built-in Ubuntu, no computer, no Termux), and 1.4.0
adds home-screen widgets that act on agents. Lead with that. Subreddits where
people already run OpenCode or Claude Code are better odds than general
developer boards.

## Ranked list

Rank is by expected users per hour of owner effort, given the rules below.

### 1. r/opencodeCLI

- URL: https://www.reddit.com/r/opencodeCLI/
- Audience: 61.2k members (Redlib, 2026-10-15). Third-party snapshot from
  GummySearch said 33k earlier, so it is growing.
- Rules: could not retrieve the rules page or sidebar rules (Redlib shows only
  the description). Sidebar text: "r/opencodeCLI is a community-driven
  subreddit for sharing resources, discussions, and tips around OpenCode".
  Evidence of what is tolerated: the current feed carries project posts such as
  "I built a desktop and phone app for OpenCode v2 that runs your sessions on a
  cloud machine", "I built a quota sidebar for OpenCode V2", and "Built a small
  OpenCode v2 plugin". Project posts are normal here.
- Best format: a text post, "I built X" with what it does, the one unusual
  thing (runs on the phone), 2 to 4 real screenshots, link in the body, a
  plain note that it is independent and unofficial, and an offer to answer
  questions. No video autoplay needed.
- Best time: the feed is mostly US/EU hours; post Tue to Thu 14:00 to 17:00 UTC.
  (Judgement, not measured.)
- Owner account: yes.
- Risk: our app also runs OpenCode 2 on-phone, which is a plus here. Mention
  that OpenCode 1 support is being retired, because people will ask.

### 2. r/ClaudeCode Weekly Showcase thread

- URL: https://www.reddit.com/r/ClaudeCode/ (the AutoModerator "Weekly
  Showcase Thread; What are you building with Claude Code?" is posted weekly;
  the one I read was https://www.reddit.com/r/ClaudeCode/comments/1x3zfol/weekly_showcase_thread_what_are_you_building_with/ ).
- Audience: 449.2k members. The thread I read had 163 comments after about 3
  days.
- Rule, quoted from that thread: "Quick project drops and simple
  self-promotion belong in this thread. If you've got a project with enough
  substance for a proper write-up; how it works, how Claude Code was involved,
  technical details, lessons learned, etc. feel free to make a standalone post
  using the Built with Claude Code flair instead. Please don't spam the same
  project repeatedly, and no referral or affiliate links." It asks for: what
  you built, how you used Claude Code, a link/repo/demo/screenshot, anything
  interesting you learned.
- Best format: a comment in the weekly thread (short), then, a week later, one
  standalone "Built with Claude Code" post with the technical story: how Claude
  Code runs inside proot on a phone, what broke. Do not do both on the same day.
- Best time: the thread resets weekly; comment within the first 2 days.
- Owner account: yes.
- Note: the app was built with substantial AI assistance (README says so);
  say it, as this audience values it.

### 3. OpenCode ecosystem page and awesome-opencode (permanent listings)

- Official docs page: https://opencode.ai/docs/ecosystem . Source file
  `packages/web/src/content/docs/ecosystem.mdx` in https://github.com/anomalyco/opencode
  (the repo `sst/opencode` redirects there; 213.8k stars). The page says: "Want to
  add your OpenCode related project to this list? Submit a PR." Its Projects
  table already has OpenChamber, CodeNomad ("Desktop, Web, Mobile and Remote
  Client App") and portal ("Mobile-first web UI"), but no Android app.
  CONTRIBUTING.md there: documentation PRs are exempt from the linked-issue
  check; "Keep PRs small and focused"; commit style `docs: ...`; "Long,
  AI-generated PR descriptions and issues may be ignored. Write a short
  explanation in your own words."
- awesome-opencode: https://github.com/awesome-opencode/awesome-opencode
  (10.6k stars). PR with one YAML file under `data/projects/`. Requirements:
  Relevant, Public, "Maintained - Active commits within the last 6 months",
  Unique, Complete. Caveat: the repo's last push was 2026-07-03, so review may
  be slow. It lists dzianisv/opencode-mobile and P4OC already, so we must say
  what differs.
- Format: see OUTREACH.md for exact diffs.
- Owner account: yes (a GitHub account opens the PRs; the owner's own GitHub
  is fine).

### 4. r/ClaudeAI "Built with Claude" Project Showcase megathread

- URL: https://www.reddit.com/r/ClaudeAI/comments/1sly3jm/built_with_claude_project_showcase_megathread/
- Audience: 1.2m members; the megathread had 1.9k comments.
- Rule, quoted from the megathread (mod u/sixbillionthsheep, 2026-04-15):
  "Anyone is welcome to submit a project to this Megathread provided you
  follow the Showcase requirements in Rule 7." And: "We now require the OP of
  a Project Showcase on the subreddit feed to have total karma>=50 ... So this
  Megathread is your best place to be seen by readers and other creators if
  you're relatively new to Reddit." I could not retrieve the text of Rule 7;
  the owner must read it. The feed carries a "Built with Claude" flair.
- Best format: one comment with the Claude-Code-on-phone hook, one screenshot
  (comments allow images), the repo link. Claude's role in the build is the
  hook for this audience: say what Claude Code did.
- Best time: any day; the megathread is sorted by New, so earlier in a US day
  gets more reads.
- Owner account: yes; owner must have total karma of 50 for a feed post.

### 5. Hacker News, Show HN

- URL: https://news.ycombinator.com/submit
- Audience: the front page; Show HN gets about 820 posts per week (my count:
  24,701 in 30 weeks).
- Rules (https://news.ycombinator.com/showhn.html, paraphrased from a fetch; I
  could not get a verbatim copy): Show HN is for things people can run or
  hold; "Don't post quickly-generated one-offs; anybody can do that now.";
  make it easy to try, ideally without signup; title begins "Show HN";
  routine version updates usually do not qualify; "Please don't ask friends
  to upvote or comment."; the author should be available to discuss it. An APK
  that needs a model key is a barrier: say what the free option is.
- Timing (my calculation, 30 weeks): share of Show HN posts that reached 20+
  points, by UTC hour: 16:00 7.3%, 17:00 7.0%, 23:00 7.2%, 00:00 7.5%, 15:00
  6.1%; worst hours 03:00 to 08:00 UTC (3.3 to 4.5%). By weekday the spread is
  small (Wed 4.7% to Sun 6.3%); Sat and Sun have the fewest posts (2.3k and 2.5k
  vs Tue 4.7k). So: Sunday 16:00 UTC is a defensible slot; the signal is weak.
- Format: title plus first comment; see POSTS.md.
- Owner account: yes (an HN account with some history; a brand-new account
  posting its own project is treated with suspicion by readers).
- Expect: a small result. Prior art in this category scored 2 to 30 points. Do it
  once, after the Reddit posts have produced real feedback and a fixed
  first-run experience.

### 6. awesome-claude-code (hesreallyhim)

- URL: https://github.com/hesreallyhim/awesome-claude-code (55,750 stars,
  pushed today). Categories that fit: "Alternative Clients" and "Remote Control,
  Notifications & Voice I/O".
- Rules, quoted from CONTRIBUTING.md: "Any resource that is recommended must
  either: (i) Be at least 14 days old (14 days since first commit on default
  branch) AND show signs of active development ... OR (ii) Have at least 100
  stars." "You may not recommend more than one resource at a time." "ALL
  RECOMMENDATIONS MUST BE MADE USING THE WEB UI ISSUE FORM TEMPLATE" and "Do not
  open a PR." "It is **not** possible to submit a resource recommendation
  using the `gh` CLI." "resource recommendations must be created by human
  beings." Style: "Resource descriptions should be written as _descriptions_ -
  not a sales pitch. Don't address the reader ... Keep it formatted to one
  line. Don't use any emojis." The maintainer also warns that listing is more
  likely after you have users.
- We pass rule (i): repo created 2026-09-02, 43 days old, commits daily.
- The checklist includes "This resource is specific to Claude Code". Ours
  also supports OpenCode; the honest framing is "runs Claude Code on the phone".
- Owner account: yes; must be a human submission through the web form.
- Existing neighbour entries: Happy Coder, CloudCLI, claude-code-android
  (a Termux/proot guide).

### 7. r/androiddev monthly showcase

- URL: https://www.reddit.com/r/androiddev/ . Monthly thread titled
  "Interesting Android Apps: <Month> <Year> Showcase" (I saw November 2025,
  December 2025, January 2026, February 2026 posted around the 9th by u/3dom;
  I did not verify an October 2026 thread).
- Audience: 295.7k members.
- Rule, quoted from the February 2026 thread: "This month, although we
  typically do not allow self promotion, we wanted to create a space where you
  can share your latest Android-native projects with the community, get
  feedback, and maybe even gain a few new users. This thread will be lightly
  moderated, but please keep Rule 1 in mind: Be Respectful and Professional.
  Also we recommend to describe if your app is free, paid, subscription-based."
  The subreddit's wiki rules page now says the rules moved to Reddit's own
  rules UI, which I could not read.
- Fit: moderate. We are a Flutter app with a lot of Kotlin (proot, widgets,
  foreground services). The honest hook for this audience is the engineering:
  running proot-Ubuntu from `jniLibs`, Android 15 foreground-service limits,
  RemoteViews widgets that act without opening the app.
- Best format: a comment in the next monthly thread (November, around Nov 9).
- Owner account: yes.

### 8. r/selfhosted New Project Megathread

- URL: https://www.reddit.com/r/selfhosted/ (856.4k members).
- Rules, quoted from the subreddit wiki (https://www.reddit.com/r/selfhosted/wiki/rules/,
  read via a mirror 2026-10-15): "Mobile apps are allowed only as companions to
  a self-hosted backend." "Do not spam or promote your own projects too much."
  "Promoted apps must be production ready and have docs." "Only in the current
  'New Project Megathread,' you may post projects that are younger than 3 months
  (measured by first public presence, e.g. git commit, social media post,
  etc.)." The April 2026 mod post adds an AI-compliance bot: "The OP will be
  required to reply to the bot stating how AI is involved".
- Fit: weak. Our repo is 43 days old, so we may only use the megathread, and
  we are a public alpha, which clashes with "production ready". The app is a
  companion to a self-hosted OpenCode server, which does fit. Low priority;
  revisit when stable.
- Owner account: yes.

### 9. X / Twitter

- URL: https://x.com . Audience is the OpenCode and Claude Code builders who
  post demos. No account exists for the project; I did not look up handles of
  third parties I might tag, so the thread in POSTS.md tags nobody.
- Rules: platform rules only. Honest label for an AI-built independent project.
- Best format: a vertical screen recording (15 s cut in VIDEO.md) as the first
  post, 5 follow-ups, one link in the last post only (reduces reach loss).
- Best time: weekdays 14:00 to 16:00 UTC (judgement).
- Owner account: yes.
- Expect: near zero reach from a new account with no followers; useful as
  a link target for the other channels and for replying to relevant threads.

### 10. Product Hunt

- URL: https://www.producthunt.com/posts/new
- Official rules: I could not retrieve Product Hunt's own guidelines. Third-party
  playbooks (2026) say anti-spam is stricter, direct requests for upvotes can
  hurt, and a dev-tools category such as AI Coding Assistants beats a broad one.
  Treat that as secondhand.
- Fit: poor for an Android APK on GitHub with no web signup. Product Hunt
  audiences want a website and a one-click try. Do this only after there is a
  landing page or a store listing. Needs owner account (and typically a
  hunter or own launch).
- Best time: 00:01 Pacific (07:01 UTC), a standard launch convention.

### 11. OpenCode Discord

- URL: https://discord.gg/opencode (linked from the OpenCode repo's
  CONTRIBUTING.md: "ask support and how-to questions in the Discord community";
  also https://opencode.ai/discord ).
- Rules: not retrieved; Discord rules are visible only after joining. Read
  the server rules and look for a showcase channel before posting. Do not
  post in support channels.
- Audience: not public.
- Format: one short message and one image, see POSTS.md.
- Owner account: yes.

### 12. Other places worth a look (unverified rules)

- r/ChatGPTCoding, r/LLMDevs, r/vibecoding, r/Termux, r/tailscale: I did not
  read their rules. A search snippet says r/LLMDevs allows free open-source
  projects without prior approval but prohibits commercial promotion; r/vibecoding
  tightened its self-promotion rules in August 2025. Verify before use.
- r/LocalLLaMA (850.0k): **skip.** Its description is "Subreddit to discuss
  locally hostable AI" and its wiki rules say "No Off-topic posts: Content should
  be related to local AI" and "Limit Self Promotion: The 1/10th rule is a good
  guideline". We use hosted models by default; it is off-topic unless a post
  is specifically about running a local model with the app, which we have not
  verified.
- r/AndroidApps (566k): **skip.** LeadsRover's survey lists its promotion
  policy as "Banned" (third-party; verify).
- r/Android: not researched; broad consumer audience, poor fit.

## Distribution channels (where the APK itself can be found)

| Channel | Verdict | Details |
| --- | --- | --- |
| GitHub releases | live | 6 to 38 downloads per release, APK about 100 MB |
| IzzyOnDroid | blocked by policy | AI policy; see IZZYONDROID.md |
| F-Droid (main repo) | blocked | see below |
| Own F-Droid repo | feasible | dzianisv/opencode-mobile does this; no gatekeeper, but no discovery either |
| Google Play | possible but risky | see below |
| Obtainium / direct | works today | GitHub release APKs, signed, tag per version |

### F-Droid main repo: what blocks it

Source: https://f-droid.org/docs/Inclusion_Policy/ (fetched 2026-10-15).

- Quote: "Apps must be 'Free, Libre and Open Source Software (FLOSS).'" We are
  MIT, which is fine for our own code.
- Quote: Google Play Services, Firebase and Crashlytics "are strictly forbidden
  in all applications". We have none of those. But `mobile_scanner` bundles the
  ML Kit barcode model (`com.google.mlkit:barcode-scanning`, noted in
  `pubspec.yaml`), a proprietary Google binary. F-Droid's scanner flags ML Kit.
  Fix: drop QR pairing, or swap to a FLOSS scanner (e.g. ZXing-based).
- Quote: "Dependencies must be built from source or come from a trusted Maven
  repository." proot, its loader and the phone engine (`libaiteam_*.so`) ship as prebuilt
  native libraries (see the `jniLibs` comments in `android/app/build.gradle.kts`);
  F-Droid would need to build them from source.
- Build: F-Droid "compiles applications from publicly accessible source code".
  We build with Shorebird's fork of Flutter (3.47.1) and release through the
  proprietary Shorebird service. F-Droid builds Flutter apps with stock
  Flutter; the Shorebird updater would have to be a build flavour that is left
  out. We keep a separate "update via Shorebird" path in the About screen.
- Quote: apps "must not download additional executable binary files" such as
  add-ons or auto-updates "without explicit user consent. Consent must be
  opt-in". The guided setup downloads Ubuntu Base from cdimage.ubuntu.com and
  installs packages; the user starts it, but this is exactly the kind of
  download the reviewers will question. Shorebird patches are Dart code.
- Maintenance size: the APK is about 100 MB (F-Droid has no hard cap, but
  IzzyOnDroid caps at 30 MB).
- Verdict: not feasible without a separate F-Droid flavour (no ML Kit, no
  Shorebird, native libs built from source). That is a multi-week
  engineering project. Skip for now.

### Google Play: policy risk

Source: https://support.google.com/googleplay/android-developer/answer/9888379
("Device and Network Abuse", fetched 2026-10-15).

- Quote: "An app distributed via Google Play may not modify, replace, or update
  itself using any method other than" Google Play's update mechanism. Shorebird
  patches are the case at issue. Shorebird's FAQ says it complies because the
  patch runs in the Dart VM (Play's exception: "This restriction does not apply
  to code that runs in a virtual machine or an interpreter" where either
  provides indirect access to Android APIs). Many Flutter apps ship this way.
- Quote: "an app may not download executable code (such as dex, JAR, .so
  files) from a source other than Google Play." The Ubuntu rootfs is not dex, JAR
  or `.so` loaded into the app process, but it contains ELF binaries that run
  under proot, and `npm`/`apt` fetch more. This is a grey area: the
  exception covers "a virtual machine or an interpreter" with "indirect access
  to Android APIs"; proot is neither a VM nor an interpreter by name. I found no
  Play decision on this exact case. (Guides we found say the Play Store build of Termux is outdated; I did
  not verify why.)
- Quote: "Apps or third-party code, like SDKs, with interpreted languages
  (JavaScript, Python, Lua, etc.) loaded at run time ... must not allow
  potential violations of Google Play policies." Python and Node in the
  rootfs are interpreted languages loaded at run time.
- Other Play flags: the manifest declares `MANAGE_EXTERNAL_STORAGE` (all-files
  access) and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, both of which Play
  restricts to declared core uses; foreground service types `dataSync` and
  `specialUse` need declarations.
- Proof that clients can be on Play: P4OC (theblazehen), dzianisv/opencode-mobile,
  bmpenuelas/opencode-mobile-client and alvarolorentedev/opencode-mobile are on
  Google Play, but they connect to a server and do not run one. Cosyra is on
  Play and runs agents in a cloud VM, not on the phone.
- Verdict: a "server-only" build (no on-phone Linux) would pass easily;
  the on-phone Linux build carries real rejection risk, and an account
  suspension would be costly. If the owner wants Play, ask Play support
  before submitting, and ship a flavour without the on-phone engine first.

## Roundups and newsletters

Contact routes and exact text are in OUTREACH.md. The roundups that already
list mobile coding tools:

| Page | Notes |
| --- | --- |
| https://codepick.dev/en/guides/mobile-ai-coding-tools-2026/ | "Personal project", data errors via https://github.com/WhiteWorld/codepick/issues ; dated 2026-06-05; no AgentPhone |
| https://nimbalyst.com/blog/best-mobile-apps-for-claude-code-2026/ | vendor blog (competitor), unlikely |
| https://sealos.io/blog/claude-code-on-phone/ | company blog; contact page on the site; X @Sealos_io |
| https://zilliz.com/blog/3-easiest-ways-to-use-claude-code-on-your-mobile-phone | company blog; weak fit |
| https://www.explainx.ai/blog/claude-code-mobile-remote-control-phone-guide-2026 | X @explainx_ai |
| https://felloai.com/how-to-use-claude-code-on-your-phone/ | X @fello_ai |
| https://sotaaz.com/post/mobile-claude-code-en | X @sotaaz_lab |
| https://cosyra.com/guides/claude-code-on-android.html | competitor, mentions proot 7 times; contact https://cosyra.com/contact.html |

Newsletters:

| Newsletter | Fit | Route |
| --- | --- | --- |
| Console.dev | Pre-1.0 or beta tools only; "GA or stable releases are not eligible". Our versions are 1.x but we call ourselves public alpha; borderline. Self-service signup is a plus (no signup at all). | hello@console.dev (from https://console.dev/selection-criteria) |
| Android Weekly | Articles and libraries; "Links in each issue will be chosen by us" | Submit form at https://androidweekly.net/#submit-stuff ; best with an engineering article, not an app launch |
| TLDR | No link-submission route found; the site offers sponsorship | https://sponsorships.tldr.tech/ (paid) |

## Order of work

1. Fix the first-run and the README first screen (one screenshot above the fold
   with the on-phone Claude Code hook).
2. r/opencodeCLI post. 3. r/ClaudeCode weekly comment. 4. Both OpenCode PRs.
5. r/ClaudeAI megathread. 6. One engineering write-up (dev.to or own blog)
   that can be sent to Android Weekly and Console.dev. 7. Show HN once.
