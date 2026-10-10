# WithYou — Architecture Overview

This document explains the structure of the WithYou app so humans and AI assistants can make changes safely.

For product constraints, see: WITHYOU_PRINCIPLES.md


## At a Glance

- SwiftUI app, iOS 17.6+, built with Xcode 26. Newer APIs (Foundation Models on iOS 26) sit behind `#available` checks, and `FoundationModels` is weak-linked so the app still launches on older iOS.
- SwiftData for all user content, stored only on the device.
- Local notifications for reminders, focus endings and the optional daily check-in. No push notifications and no server registration.
- AI is on-device first (Apple Intelligence, iOS 26+), then cloud AI only if the person turns it on (a Supabase Edge Function that calls Claude and stores no task text), then simple rules. Every AI feature works with rules alone.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are main-actor isolated unless marked otherwise.
- `WithYou/` is a synchronized folder group: every file in it is part of the app target. Don't put templates or scratch `.swift` files there.


## Core Concepts

WithYou is organized around a few concepts:

- Capture: quickly externalize a thought
- Inbox: park thoughts without obligation
- Reminders: help start (not enforce remembering)
- Focus Sessions: protect attention for a short window
- Refocus: quick grounding reset
- I'm Stuck: a smaller, safer way in
- Profiles: tone/default personalization
- AI help: suggestions the person reviews and confirms, never silent changes
- Daily check-in: an optional, quiet local notification at a chosen time


## Folder Layout

```
WithYou/
  WithYouApp.swift      App entry; injects AppModelContainer.shared
  Models/               @Model types (see "Data Model")
  Services/             Stores, notifications, daily check-in, parsing, router, CaptureSaver
    AI/                 AIService and its providers (on-device, cloud, rules), cloud AI settings
    Voice/              Live speech-to-text for voice capture
  Stores/               FocusPresetStore
  Support/              StuckChooser (suggestions for "I'm stuck")
  DesignSystem/         Card/toast styles, Formatting, Haptics, AppScreen
  Components/           Small shared inputs
  Intents/              App Intents and Siri / Shortcuts phrases
  Views/                Today, Focus, Inbox, Schedule, Capture (Today/QuickAddView; voice capture
                        and capture review in Capture/), AI (shared suggestion views),
                        Profiles (Settings), Stuck, Onboarding, Shared (RootView, tabs, sheets)
  Config/               WithYou.xcconfig (tracked, empty cloud AI values),
                        WithYou.local.xcconfig (gitignored, optional real values)
WithYouTests/           XCTest unit tests (hosted in the app)
Config/                 Secrets.swift.example (legacy template; the app no longer reads Secrets)
.github/                Issue/PR templates and the CI workflow
```


## Data Model

All models are registered in one place, `AppModelContainer`:

- `InboxItem`: a parked thought (not an obligation), with an optional start step and estimate
- `VerboseReminder`: a gentle nudge to start at a time, with a suggested first step. Forgiveness logic applies if it passes.
- `FocusSession`: a focus window. It may come from an Inbox item or a reminder (`sourceKindRaw` / `sourceId`). Pause time persists across launches (`pausedSeconds`, `pausedAt`).
- `FocusDumpItem`: a thought parked during a session (brain dump)
- `FocusBlock`: a planned focus block (in the schema, not shown in the UI yet)
- `FocusDurationPreset`: per-profile focus lengths
- `UserProfile`: tone, default hours (morning / afternoon / evening), focus length, mantra, appearance
- `AppState`: which profile is active

### AppModelContainer: one container, always

`AppModelContainer.shared` is the single `ModelContainer` for the app **and** its App Intents. Every entry point must use it.

Never open the store with a subset of the models (for example, an intent that only lists `InboxItem`). SwiftData treats that as a different schema and may migrate the store to it, which can drop data for the missing models.

### Schema changes

The schema is currently unversioned. **Before the next model change**, introduce a `VersionedSchema` that matches the shipping schema exactly, plus a `SchemaMigrationPlan`, and add the new version on top of it. Then pass the migration plan to `AppModelContainer`.


## Services

### AppRouter (routes contract)

`AppRouter.shared` is how code outside the view hierarchy (notification taps and actions, App Intents, deep links like `withyou://today` or `withyou://voice`) asks the UI to go somewhere. Routes: `today`, `focus`, `inbox`, `schedule`, `capture`, `refocus`, `stuck(reminderId:)`, `reminder(UUID)`, `startFocus(reminderId:)`, `voiceCapture`.

- `RootView` observes `pendingRoute`. It handles the tab routes, `.refocus`, `.startFocus` and `.voiceCapture` (a sheet), then calls `consume()`.
- For `.stuck` and `.reminder`, `RootView` only switches to Today and leaves the route pending. `TodayView` presents the sheet and calls `consume()`.
- Views also check `pendingRoute` in `onAppear`, because a cold launch from a notification sets the route before any view exists.
- Only one sheet can be up at a time, and each tab presents its own. A route that needs a sheet checks `isSheetUp`; if anything is up, it calls `closeAllSheets()` and presents a moment later. Every view that presents sheets observes `closeSheetsRequest` and closes them. An open voice capture is never closed for another voice capture or Refocus, and when it does close without saving, its words come back (into Capture's editor, or with Undo on a toast).

### NotificationManager

Owns local notifications:

- Becomes the `UNUserNotificationCenter` delegate and registers the action categories at launch (`configure()`), without prompting.
- **Contextual permission:** `ensureAuthorization()` asks for permission the first time something is scheduled, or when the daily check-in is turned on, never at launch. It returns whether notifications can be shown.
- **Local only:** the app doesn't register for remote notifications. There is no device token and no push server.
- Categories: reminders offer *I'm starting*, *Help me start*, *In 10 minutes*, *Tomorrow morning*. Focus endings offer *Wrap up*. The daily check-in (`DAILY_CHECKIN`) has no buttons; a tap opens Today.
- Handles taps and actions: snoozing and rescheduling go through `ReminderStore`; everything that needs UI goes through `AppRouter`.

### DailyCheckIn

An optional daily check-in, off by default (`@AppStorage` keys `dailyCheckInEnabled` and `dailyCheckInMinutes`, default 540 = 9:00 AM). Settings shows it in `DailyCheckInSection`.

- Schedules the next 7 check-ins as separate one-time local notifications with ids `checkin-YYYY-MM-DD` (`UNCalendarNotificationTrigger` with year, month, day, hour and minute, not repeating). Each refresh first removes every pending `checkin-*` request, and clears check-ins already shown, so nothing piles up.
- Refreshes at launch (`AppDelegate`), whenever the app becomes active (`WithYouApp`), and when the settings change. Refreshing never asks for permission; turning the check-in on does, once.
- `upcomingFireDates(after:minutes:restChosenAt:count:calendar:)` is the pure, `nonisolated` date math: it builds each date in the calendar's time zone (wall-clock time holds across daylight-saving changes) and skips today when today's time has passed or the person let today rest.
- `DailyCheckIn.letTodayRest()` records the "Let today rest" choice so today's check-in is skipped, and `undoLetTodayRest()` takes it back. Today's "Let today rest" action and its Undo call them.
- Copy rotates through a few calm lines, one per day.

### ReminderStore and FocusSessionStore: the only write paths

Creating, rescheduling, editing, letting go of and starting things must go through these two stores, so the pending notification always matches what is saved:

- `ReminderStore`: `createAndSchedule`, `reschedule`, `saveEdits`, `letGo`, `refreshNotification`. It also owns the notification copy (`notificationBody`, gentle vs firm) and time helpers (`nextMorning`, `thisEvening`, `roundedUp`).
- `FocusSessionStore`: `start` (ends any other active session), `begin` (after the brain dump), `scheduleEndNotification`, and the timer math `remainingSeconds` / `overtimeSeconds` (paused time, including a pause still running, never counts).

Don't set `scheduledAt` or `startedAt` directly from a view.

### CompletionStore

Finishing things: `completeFromSession` (clears the source Inbox item or marks the reminder done), `endWithoutCompleting` ("stopping for now" leaves the source alone), `completeInboxItem`, `completeReminder`. It also moves brain-dump thoughts to the Inbox after a session, including thoughts orphaned by a session that ended without a wrap-up, so nothing parked is lost.

### CaptureParser

Turns a captured thought into a title, a gentle first step, an estimate and, only when a time is clearly mentioned, a date. It is a pure function of `(text, profile, now)`, which keeps it testable:

- Explicit clock times win over part-of-day words. Part-of-day words use the profile's hours (9 / 13 / 19 by default).
- A time that already passed today rolls to tomorrow. A day that already went by ("yesterday") is not scheduled; the thought goes to the Inbox.
- Leading phrases ("remind me to…") and time words are stripped from the title.

### SmallStepSuggester

Simple, offline small steps: `ruleBasedStep` (one first step, never the one you already have) and `ruleBasedSteps` (the rules behind "Break it down"). `AIRules` builds on them; model-written steps come from `AIService`.

### AI layer (`Services/AI/`)

`AIService` is the only entry point features use: `capture`, `breakDown`, `stuckHelp`, `suggestNext` and `tidy`. It never throws and always returns something, with an `AISource` (`onDevice`, `cloud`, `rules`) for small attributions such as "Suggested on this iPhone".

- **Order:** Apple's on-device model (`OnDeviceAI`, FoundationModels, iOS 26+, behind `#if canImport(FoundationModels)` and `#available`) → cloud AI, only when the person turned it on and the build is configured → rules (`AIRules`, built on `CaptureParser` and `SmallStepSuggester`). Each attempt has a deadline (10 s on device, 15 s cloud); anything slow, failing or unusable falls through to the next.
- **Checks:** `AIOutput` validates and clamps every model answer (non-empty titles, estimates 1–240 minutes, at most 12 items).
- **Suggest, then confirm:** features show suggestions in review sheets or cards; nothing is applied until the person taps. The one exception is Siri capture, which saves because the person asked Siri to, and says what it saved.
- **Cloud AI:** `CloudAIClient` calls the Supabase Edge Function `ai` (`POST /functions/v1/ai` with `{"task", "input"}`). `SupabaseAuth` signs in anonymously (a random ID, no email or name) and keeps the session in the Keychain via `KeychainStore`. A "try later" from the server pauses cloud AI for a while. `deleteCloudData()` asks the server to delete the anonymous account and its usage counts, then forgets the session.
- **Settings:** `CloudAISettings` (UserDefaults `cloudAIEnabled`, off by default) and `CloudAISettingsSection`, which shows the toggle, what is sent, and "Delete my cloud AI data".
- **Configuration:** `AppConfig.supabaseBaseURL` and `AppConfig.supabaseAnonKey` come from the Info.plist keys `WITHYOU_SUPABASE_HOST` and `WITHYOU_SUPABASE_ANON_KEY`, which the xcconfig fills in. Empty or unresolved values mean cloud AI isn't set up.

### Voice capture

- `SpeechTranscriber` (`Services/Voice/`): live speech-to-text with `SFSpeechRecognizer` and `AVAudioEngine`, on device whenever the iPhone supports it for the language. Stops after a short silence or 60 seconds and releases the audio session.
- `VoiceCaptureView` and `CaptureReviewView` (`Views/Capture/`): speak, then review the sorted items before saving. During a focus session (with "Send captures to Brain Dump during focus" on), Done parks the words in the session's brain dump instead, like Siri and Save. Undo after saving, and Close, give the words back.
- `CaptureSaver`: saves reviewed suggestions (timed ones through `ReminderStore.createAndSchedule`, the rest as Inbox items) and can undo exactly that save.

### Other services

- `ProfileStore`: active profile and default-profile setup
- `KeychainStore`: small Keychain wrapper. Holds the anonymous cloud AI session.
- `LegacyServerCleanup` (in `AppDelegate.swift`): runs once and removes what the retired push server left on the device (cached push token, registration bookkeeping, the old sharing choice, the install ID and its Keychain secret). It sends nothing.
- `AppConfig`: cloud AI host and publishable key from the xcconfig. `Secrets.swift` is no longer read.


## Design System

Use the shared pieces instead of one-off styling:

- `.cardStyle()`: the standard card background
- `SectionHeader`: section titles
- `.toast($toast)` with `Toast(text:actionTitle:action:)`: calm confirmations, usually with **Undo** instead of a confirmation dialog
- Formatting helpers: `Date.timeText`, `.friendlyDayTime`, `.relativeDayText`, `.dayHeaderText`, `hourLabel(_:)`. They follow the user's locale and 12/24-hour setting.
- `Haptics` for light feedback
- Colors come from the asset catalog as generated symbols (`.appAccent`, `.appSecondaryText`, `.appSurface`, …). Don't hard-code colors.


## View Layer

Primary tabs: **Today / Focus / Inbox / Schedule / Capture**. Settings (profiles, tone, defaults, appearance, daily check-in, AI help, privacy) open from the gear on Today. First launch shows the welcome screens.

- Today: "right now", an optional energy check-in, "Still relevant?" cards, Refocus / I'm stuck / Let today rest. No backlog pressure, no "overdue" framing.
- Focus: brain dump → timer (pause, extend, keep screen awake) → wrap-up review
- Inbox: parked thoughts. Actions: schedule, break it down, let go (with Undo).
- Schedule: upcoming reminders, grouped by day
- Capture: fast input with a live preview of where the thought will go, and Undo. A mic button opens voice capture; "Sort it out for me" asks `AIService` to split and tidy the text for review.


## Tests and CI

- `WithYouTests/` holds XCTest unit tests for the pure logic: `CaptureParser`, `FocusSessionStore` timer math, `ReminderStore` copy and time helpers, `Formatting`, `SmallStepSuggester`'s rules, the AI layer (output checks, rules, provider fall-through, the cloud client against a stubbed network), `CaptureSaver`, voice capture timing, and `DailyCheckIn`'s date math. Tests that need models create an in-memory `ModelContainer` **before** creating any `@Model` instance.
- Test classes are `@MainActor`, because the app module defaults to main-actor isolation.
- The shared **WithYou** scheme (`WithYou.xcodeproj/xcshareddata`) builds the app and runs `WithYouTests`.
- `.github/workflows/ios-ci.yml` runs the tests on every pull request and push to `main`. It still writes a stub `Secrets.swift`, which the app no longer reads. CI builds have no cloud AI settings.

When you add logic that can be tested without UI, add a test next to the existing ones.


## Patterns to Follow

- Prefer small, composable SwiftUI views
- Keep copy minimal and non-judgmental
- Use explicit, readable names over clever abstractions
- Keep "forgiveness logic" and "completion logging" centralized (ReminderStore, CompletionStore) so they stay consistent
- Write through the stores, never around them
- Avoid visual states that imply failure (red badges, overdue counts, "backlog")


## "Emotional Safety" Architectural Rules

The UI should not create pressure by:

- showing accumulating overdue items
- showing productivity metrics, streaks, grades
- escalating reminders or repeating endlessly
- using red error-like styling for normal life outcomes
- using `role: .destructive` (red) for letting something go. Letting go is a neutral choice, not a deletion to warn about.

If a proposed change adds pressure, it must be rejected (see WITHYOU_PRINCIPLES.md).


## How to Work in This Repo

When implementing a change:

1. Read WITHYOU_PRINCIPLES.md first.
2. Identify which models/views are impacted.
3. Make minimal changes that fit existing patterns.
4. Prefer diff-friendly edits.
5. If unsure, add a brief comment explaining the choice in code.
6. Run the tests (⌘U, or see README → Development).

When adding a new feature, add:
- a small section to WITHYOU_PRINCIPLES.md if it introduces a new kind of behavior
- a small section here if it introduces a new architectural pattern
