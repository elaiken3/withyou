# Contributing to WithYou

Thank you for your interest in contributing.
Before writing code, please read this carefully.

WithYou is not a typical productivity app.
Its philosophy matters as much as its features.

---

## 🧠 Design Philosophy

WithYou is built for people with ADHD and executive-function challenges.
That means:

- Emotional safety is a feature
- Reducing cognitive load matters more than speed
- “Helpful” is more important than “powerful”

If a contribution increases pressure, guilt, or noise — it will be rejected.

---

## 🚦 Contribution Guidelines

### What We Welcome
- Accessibility improvements
- Focus and initiation support
- Calm UI enhancements
- Thoughtful copy changes
- Bug fixes that reduce friction
- Performance improvements that don’t add complexity

---

### What We Do Not Accept
- Streaks, scores, or gamification
- “Overdue” mechanics
- Shame-based language
- Infinite task lists
- Features that punish inconsistency
- Productivity metrics exposed to users

---

## 🗣 Language & Tone

UI copy should be:
- Calm
- Reassuring
- Direct but kind
- Non-judgmental

Avoid:
- “You should…”
- “Don’t forget…”
- “Overdue”
- “Failed”
- “Missed”

Preferred language:
- “Still relevant?”
- “Want help starting?”
- “That counted.”

---

## 🎨 Visual Language

- No red/green for normal outcomes. Finishing, skipping, rescheduling and letting go are all normal; none of them get success-green or warning-red styling.
- No `role: .destructive` for letting go. "Not needed" and "Let go" are neutral choices, not dangerous deletions; offer Undo instead of a red button or a scary confirmation.
- Use the shared design system (`.cardStyle()`, `SectionHeader`, `.toast`, the Formatting helpers) instead of one-off styles. See ARCHITECTURE.md.

---

## 🛠 Technical Notes

- SwiftUI + SwiftData
- iOS 17.6+, built with Xcode 26 (newer APIs behind `#available`)
- Create `WithYou/Config/Secrets.swift` before building (see README → Development). Never commit it.
- Create, reschedule and start things through `ReminderStore` / `FocusSessionStore` so notifications stay in sync
- Voice-first friendly where possible
- Accessibility labels are expected
- Favor clarity over cleverness

When in doubt:
> Choose the implementation that requires fewer decisions from the user.

---

## 🧪 Testing Expectations

### Automated tests and CI

- Unit tests live in `WithYouTests/` and run with ⌘U on the shared **WithYou** scheme (or `xcodebuild … test`, see README).
- CI (`.github/workflows/ios-ci.yml`) runs them on every pull request. PRs should be green before review.
- New logic that can be tested without UI (parsing, time math, copy choices, store behavior) should come with tests.
- Tests that use SwiftData create an in-memory `ModelContainer` before creating any model objects.
- Fix a failing test or explain why its expectation changed; don't delete it to get green.

### Emotional checks

When adding or modifying features, consider:
- What happens if the user ignores this?
- What happens if they fall behind?
- Does this feel safe to return to after a bad week?

If the answer is “this might stress someone out” — rethink it.

---

## 📦 Pull Requests

Please include:
1. What problem this solves
2. Why it helps ADHD users specifically
3. Any UX or emotional tradeoffs considered
4. How you tested it (unit tests added or updated, and what you checked by hand)

Large features should be discussed before implementation.

---

## 🧭 Final Rule

If a feature makes users feel:
- rushed
- guilty
- watched
- judged

It does not belong in WithYou.

Thank you for helping build something humane.
