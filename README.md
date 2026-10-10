# WithYou

**An achievement app for ADHD brains.**

### Audience
--------

A person with ADHD or a guardian with an ADHD child

### Description
-----------

WithYou is an **executive-function support system** that helps people with ADHD **complete tasks** by **capturing thoughts, protecting focus, and prioritizing completing over starting tasks.**

It reduces mental overload so people can focus on **one thing at a time** --- with pride, focus, and confidence.

This is not a traditional to-do app.

The goal is getting things done.

For many people with ADHD, that starts with clearing the mind and protecting attention long enough to make **rewardable progress**.

* * * * *

## 🌱 Why WithYou Exists

People with ADHD struggle with executive function that help them:

-   decide what to work on

-   start a task

-   hold steps in working memory

-   manage time and attention

-   resist distractions

-   stop or switch tasks intentionally

and experience:

-   task paralysis (wanting to act but feeling stuck)

-   mental overload from holding too many thoughts at once

-   losing focus shortly after starting

-   difficulty returning to a task once interrupted

In these moments, the problem isn't a lack of goals or desire to finish --- it's that the mind is too cluttered or distracted to begin and sustain focus. .

WithYou addresses this by:

-   capturing thoughts so they don't compete for attention

-   protecting focus so one task can actually progress

-   making starting small and safe, so finishing becomes possible

Most productivity apps make this worse by:

-   piling up overdue tasks

-   punishing missed reminders

-   demanding streaks and consistency

-   overwhelming users with lists

WithYou does the opposite.

It lowers the cognitive load required to start and stay focused --- so tasks can actually get done.

* * * * *

## 🧠 Core Principles (Non-Negotiable)
-----------------------------------

Every feature must respect these rules:

1.  One thing at a time

2.  Thoughts are not obligations

3.  Missed tasks are neutral

4.  Short focus windows are valid

5.  Emotional safety > optimization

6.  The app never shames or nags

If a feature violates these, it does not ship.

* * * * *

## ✨ What WithYou Does
-------------------

### Capture (External Brain)

-   Instantly capture thoughts via text or voice

-   Siri / Shortcuts supported

-   Time-aware parsing:

    -   If a time is detected → scheduled

    -   If not → Inbox

    -   During Focus Sessions → routed to Focus Dump

-   A live preview shows where a thought will go before you save it, and every save can be undone

Language is minimal:

"Saved."\
"I've got it."

* * * * *

### Inbox (Mental Parking Lot)

-   Holds thoughts without forcing decisions

-   Nothing is overdue

-   Nothing nags

Actions:

-   Schedule

-   Break it down

-   Not needed

* * * * *

### Verbose Reminders

Reminders help users start, not just remember.

Each reminder includes:

-   What the task is

-   A suggested start step

-   Gentle notification actions: I'm starting / Help me start / In 10 minutes / Tomorrow morning

No red text. No overdue panic.

* * * * *

### Focus Sessions

Focus Sessions protect attention for short periods.

Flow:

1.  Choose one focus task

2.  Brain dump distracting thoughts

3.  Start a short timer (25--60 min)

4.  Pause / resume as needed

5.  Add thoughts without stopping

6.  Extend time if helpful

7.  End session

8.  Decide what to do with parked thoughts

During a Focus Session:

Nothing else matters.

* * * * *

### Refocus Button

A micro-reset for spirals and distraction:

-   30-second timer

-   Guided breathing, with optional breathing haptics you can follow with your eyes closed

-   A short mantra (profile-based)

Accessible anywhere in the app.

* * * * *

### Profiles

Profiles live in Settings (the gear on Today) and allow personalization without complexity:

-   Name

-   Reminder tone (gentle / firm)

-   Default focus length

-   Preferred mantra

-   Time-of-day defaults

Supports multiple users or work/personal modes.

* * * * *

## 🛟 Emotional Safety Features
----------------------------

### Forgiveness Logic

Missed reminders:

-   Do not repeat endlessly

-   Do not turn red

-   Ask once: "Still relevant?"

Options:

-   Today

-   Later

-   Not needed

Then the app lets go.

* * * * *

### No Shame Mechanics

Explicitly avoided:

-   Streaks - internal motivation 

-   Scores - it's not about getting the high score, it's about rewarding progress toward the goal.

-   "Overdue" labels - intentions are not time bound or fixed.  The focus is situational relevancy and and urgency of the current moment and experience.

-   Productivity dashboards - dashboards focus on the current experience, we are focused on the trend of progress, not the current statistics.

Completion feedback is gentle:

- "Nice."
- "That counted."

* * * * *

## 🚧 Current Status (TestFlight Build)
------------------------------------

WithYou is currently in early TestFlight testing.

What's implemented today:

-   Tab-based navigation: Today / Focus / Inbox / Schedule / Capture

-   Settings (profile, tone, default times, appearance, daily check-in, AI help, privacy) behind the gear on Today

-   Capture → Inbox → Reminder flow

-   Focus Sessions with:

    -   Brain dump

    -   Pause / resume

    -   Extend time

    -   Wrap-up review

-   Gentle focus-end notifications

-   Refocus (one-minute breathing reset)

-   "I'm stuck" mode

-   Profiles for personalization

### New in this build

-   **Gentle, contextual notification permission.** WithYou doesn't ask at launch. It asks the first time you schedule something, when the reason is obvious.

-   **Notification actions that work.** Reminders offer *I'm starting*, *Help me start*, *In 10 minutes* and *Tomorrow morning*. The focus-end notification offers *Wrap up*.

-   **Live capture preview + Undo.** While you type, Capture shows where the thought will go (Inbox, or a time). Every save can be undone.

-   **Smarter time parsing.** "Call mom at 3pm" said after 3pm means tomorrow. "Tonight", "tomorrow morning", "noon" and "in 20 minutes" all work. A day that already went by ("yesterday") goes to the Inbox instead of into the past.

-   **Energy check-in.** An optional "Energy today" choice on Today. On a low-energy day, Today suggests only the smallest thing. It quietly resets each morning.

-   **"Let today rest."** In the evening, one tap moves what's left today to tomorrow morning. Undo is right there.

-   **"Break it down."** A few tiny steps for a task, in Inbox, Today, "I'm stuck" and the edit sheets. Tap one to make it the first step, with Undo where it's saved straight away.

-   **Voice capture.** Tap the mic in Capture, say "Brain dump in WithYou", or bind the Voice capture shortcut to the Action Button. Your words appear as you speak, and WithYou sorts them into items you look over before anything is saved. "Capture in WithYou" with Siri saves right away and tells you what it saved.

-   **AI help that suggests, never acts.** "Sort it out for me" in Capture, "Break it down", a gentler "I'm stuck", "Help me pick" on Today, and tidying brain-dump thoughts after focus. Each shows one suggestion; you choose what to keep. On iPhones with Apple Intelligence (iOS 26+) it runs on the device. Cloud AI is off by default and can be turned on in Settings. Without either, simple built-in rules do the same jobs, more simply.

-   **Daily check-in (optional).** Off by default. Pick a time in Settings for one quiet notification a day. It's scheduled on your iPhone, and nothing piles up if you skip it.

-   **No more server registration.** WithYou no longer registers for push notifications or sends a device token anywhere. Reminders, focus endings and check-ins are all local notifications. Leftover registration data is removed from the iPhone on first launch.

-   **Siri / Shortcuts:** Capture, Voice capture, Start focus, Refocus, I'm stuck.

-   **Welcome screens** on first launch.

-   **Keep screen awake** during focus (a toggle in Settings).

-   **Breathing haptics** in Refocus.

What's intentionally not finished yet:

-   Daily planning UI

-   Session history

-   Analytics or insights

-   Advanced Siri / Shortcuts

-   Energy insights over time

If something feels incomplete, that's expected --- this phase is about: Does this feel emotionally safe? Does it reduce friction?

* * * * *

## 🧭 Roadmap Overview
-------------------

### v1 --- External Brain

Capture, Inbox, Verbose Reminders, Focus Sessions, Refocus, Profiles

### v2 --- When Motivation Fails

"I'm Stuck" mode, energy-aware scheduling, gentle celebration

### v3 --- Long-Term Support

Thoughts vs Tasks, end-of-day reset, context awareness, private insights

* * * * *

## 💰 Monetization Philosophy
--------------------------

Core relief features are never paywalled.

Free forever:

-   Capture

-   Inbox

-   Focus Sessions

-   Refocus

-   I'm Stuck mode

Paid tier (ethical):

-   Advanced personalization

-   Multiple profiles

-   Energy insights

-   Context-aware suggestions

No ads. No dark patterns.

* * * * *

## 🧡 One-Sentence Summary
-----------------------

WithYou is an executive-function support app for people with ADHD that holds thoughts, protects focus, and removes shame --- so users can do one thing at a time with pride, focus, and confidence.

* * * * *

## 🧪 How to Give Feedback
-----------------------

If you're testing WithYou via TestFlight:

-   Use the app normally --- there's no "right" way

-   If something feels stressful, confusing, or surprisingly calming, that's valuable feedback

-   Use TestFlight's "Send Feedback" feature for bugs or thoughts

Helpful feedback questions:

-   Where did you feel relief?

-   Where did friction remain?

-   Did anything feel unintentionally pressuring?

-   Did the language feel safe?

You're not testing productivity. You're testing emotional load.

* * * * *

## 🛠 Development
--------------

### Requirements

-   Xcode 26 (the app uses iOS 26 APIs behind `#available` checks)

-   Deployment target: iOS 17.6

Nothing needs to be set up to build and run: a fresh clone builds as is.

### Cloud AI setup (optional)

Cloud AI is opt-in: it's off by default, and when someone turns it on in Settings, each AI request goes to Claude through WithYou's Supabase project. A build without it works fully: Apple Intelligence (when the device has it) and the built-in rules handle every AI feature, and Settings says cloud AI isn't set up.

To build with it, create `WithYou/Config/WithYou.local.xcconfig`. It is gitignored, and `WithYou/Config/WithYou.xcconfig` includes it so its values win:

```
WITHYOU_SUPABASE_HOST = your-project-ref.supabase.co
WITHYOU_SUPABASE_ANON_KEY = your-publishable-key
```

-   Use the host only, without `https://`, because `//` starts a comment in xcconfig files.
-   The publishable (anon) key is designed to ship inside apps. It only allows an anonymous sign-in and calls to the `ai` function, which enforces its own daily limits.
-   Never put the Supabase service-role (secret) key or the Anthropic API key in the app. They live only in Supabase; see `docs/CUTOVER.md` in the `withyou-backend` repository.
-   If a change doesn't seem to take effect, clean the build folder (⇧⌘K) and build again.

### Secrets.swift (no longer used)

Earlier builds read a backend API key from `WithYou/Config/Secrets.swift`. The app doesn't use it any more: nothing references `Secrets`, so you don't need to create it. If you already have one, you can leave it as is (it still compiles, unused) or delete it. CI still creates a stub, which is harmless. `Config/Secrets.swift.example` is kept for now.

### Running tests

Unit tests live in `WithYouTests/` (XCTest, hosted in the app). In Xcode, choose the shared **WithYou** scheme and press ⌘U. From the command line:

```sh
xcodebuild -project WithYou.xcodeproj -scheme WithYou \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

(Use any iPhone simulator you have installed; `xcrun simctl list devices available` lists them.)

The tests cover capture parsing, focus timer math, reminder copy and time helpers, date formatting, the small-step rules, the AI layer (output checks, rules fallbacks, the cloud AI client against a stubbed network), saving captures, voice capture timing, and the daily check-in's date math.

### CI

`.github/workflows/ios-ci.yml` runs the tests on every pull request and on every push to `main`, on a GitHub-hosted macOS runner. It creates a stub `Secrets.swift` (a leftover; the app no longer reads it), picks an available iPhone simulator, and runs the WithYou scheme's tests. If they fail, the `.xcresult` bundle is uploaded as a build artifact. CI builds have no cloud AI settings, so cloud AI is simply not set up there.

For contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md). For how the code is organized, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Legal
- Privacy Policy: https://wearewithyou.app/privacy/
- Support: https://wearewithyou.app/support/
