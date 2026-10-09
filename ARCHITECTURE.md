# WithYou — Architecture Overview

This document explains the structure of the WithYou app so humans and AI assistants can make changes safely.

For product constraints, see: WITHYOU_PRINCIPLES.md


## At a Glance

- SwiftUI app, iOS 17.6+, built with Xcode 26. Newer APIs (Foundation Models on iOS 26) sit behind `#available` checks, and `FoundationModels` is weak-linked so the app still launches on older iOS.
- SwiftData for all user content, stored only on the device.
- Local notifications for reminders and focus endings. An optional backend only stores what it needs to send push notifications.
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


## Folder Layout

```
WithYou/
  WithYouApp.swift      App entry; injects AppModelContainer.shared
  Models/               @Model types (see "Data Model")
  Services/             Stores, notifications, parsing, backend, router
  Stores/               FocusPresetStore
  Support/              StuckChooser (suggestions for "I'm stuck")
  DesignSystem/         Card/toast styles, Formatting, Haptics, AppScreen
  Components/           Small shared inputs
  Intents/              App Intents and Siri / Shortcuts phrases
  Views/                Today, Focus, Inbox, Schedule, Capture (Today/QuickAddView),
                        Profiles (Settings), Stuck, Onboarding, Shared (RootView, tabs, sheets)
  Config/               WithYou.xcconfig (tracked), Secrets.swift (gitignored)
WithYouTests/           XCTest unit tests (hosted in the app)
Config/                 Secrets.swift.example (template, outside the app folder)
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

`AppRouter.shared` is how code outside the view hierarchy (notification taps and actions, App Intents, backend deep links like `withyou://today`) asks the UI to go somewhere. Routes: `today`, `focus`, `inbox`, `schedule`, `capture`, `refocus`, `stuck(reminderId:)`, `reminder(UUID)`, `startFocus(reminderId:)`.

- `RootView` observes `pendingRoute`. It handles the tab routes, `.refocus` and `.startFocus`, then calls `consume()`.
- For `.stuck` and `.reminder`, `RootView` only switches to Today and leaves the route pending. `TodayView` presents the sheet and calls `consume()`.
- Views also check `pendingRoute` in `onAppear`, because a cold launch from a notification sets the route before any view exists.

### NotificationManager

Owns local notifications:

- Becomes the `UNUserNotificationCenter` delegate and registers the action categories at launch (`configure()`), without prompting.
- **Contextual permission:** `ensureAuthorization()` asks for permission the first time something is scheduled, not at launch. At launch it only refreshes the push token if permission was already given.
- Categories: reminders offer *I'm starting*, *Help me start*, *In 10 minutes*, *Tomorrow morning*. Focus endings offer *Wrap up*.
- Handles taps and actions: snoozing and rescheduling go through `ReminderStore`; everything that needs UI goes through `AppRouter`.

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

Powers "Make it smaller". On iOS 26+ with Apple Intelligence available, it asks Apple's on-device Foundation Model for one tiny first step. Otherwise, or if the model is unavailable or fails, it uses `ruleBasedStep`, which never returns the step you already have. Nothing is sent off the device.

### Other services

- `ProfileStore`: active profile and default-profile setup
- `DeviceRegistration`, `BackendClient`, `InstallID`, `KeychainStore`: optional push registration. Only runs when notifications are allowed and the Privacy toggle is on. Turning the toggle off deletes the server record. The per-install secret the server issues is kept in the Keychain.
- `AppConfig`: backend URL (from the xcconfig) and API key (from `Secrets.swift`; empty means none)


## Design System

Use the shared pieces instead of one-off styling:

- `.cardStyle()`: the standard card background
- `SectionHeader`: section titles
- `.toast($toast)` with `Toast(text:actionTitle:action:)`: calm confirmations, usually with **Undo** instead of a confirmation dialog
- Formatting helpers: `Date.timeText`, `.friendlyDayTime`, `.relativeDayText`, `.dayHeaderText`, `hourLabel(_:)`. They follow the user's locale and 12/24-hour setting.
- `Haptics` for light feedback
- Colors come from the asset catalog as generated symbols (`.appAccent`, `.appSecondaryText`, `.appSurface`, …). Don't hard-code colors.


## View Layer

Primary tabs: **Today / Focus / Inbox / Schedule / Capture**. Settings (profiles, tone, defaults, appearance, notifications, privacy) open from the gear on Today. First launch shows the welcome screens.

- Today: "right now", an optional energy check-in, "Still relevant?" cards, Refocus / I'm stuck / Let today rest. No backlog pressure, no "overdue" framing.
- Focus: brain dump → timer (pause, extend, keep screen awake) → wrap-up review
- Inbox: parked thoughts. Actions: schedule, make smaller, let go (with Undo).
- Schedule: upcoming reminders, grouped by day
- Capture: fast input with a live preview of where the thought will go, and Undo


## Tests and CI

- `WithYouTests/` holds XCTest unit tests for the pure logic: `CaptureParser`, `FocusSessionStore` timer math, `ReminderStore` copy and time helpers, `Formatting`, and `SmallStepSuggester`'s rules. Tests that need models create an in-memory `ModelContainer` **before** creating any `@Model` instance.
- Test classes are `@MainActor`, because the app module defaults to main-actor isolation.
- The shared **WithYou** scheme (`WithYou.xcodeproj/xcshareddata`) builds the app and runs `WithYouTests`.
- `.github/workflows/ios-ci.yml` runs the tests on every pull request and push to `main`, with a stub `Secrets.swift`.

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
