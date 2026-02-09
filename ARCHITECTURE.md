# WithYou — Architecture Overview

This document explains the structure of the WithYou app so humans and AI assistants (Codex) can make changes safely.

For product constraints, see: WITHYOU_PRINCIPLES.md


## Tech Stack

- SwiftUI UI layer
- SwiftData for persistence (models + @Query + ModelContext)
- Lightweight, local-first flows
- Notifications: gentle reminders (no punitive escalation)
- Navigation: tab-based primary navigation


## Core Concepts

WithYou is organized around a few concepts:

- Capture: quickly externalize a thought
- Inbox: park thoughts without obligation
- Reminders: help start (not enforce remembering)
- Focus Sessions: protect attention for a short window
- Refocus: quick grounding reset
- Profiles: tone/default personalization


## Data Model (Conceptual)

Common model types you will see:

- InboxItem
  - Represents a parked thought (not an obligation)
  - Optional “start step” to make starting safe

- VerboseReminder
  - Represents a gentle nudge to start
  - Includes a suggested first step
  - Forgiveness logic applies if missed

- FocusSession
  - Represents a focused work window
  - May originate from an InboxItem or a Reminder (“source”)
  - Captures brain dump items during the session
  - Session completion should feel valid even if task not done

- UserProfile / AppState (or similar)
  - Stores personalization and active profile selection


## View Layer (Conceptual)

Primary tabs typically include:

- Today
  - Shows “right now” and lightweight, safe choices
  - Avoids backlog pressure and “overdue” framing

- Focus
  - Create/continue focus sessions
  - Brain dump flows live here or are accessible from here

- Inbox
  - List of parked thoughts
  - Actions: schedule, make smaller, not needed (no shame)

- Capture
  - Fast input, minimal friction
  - Should reduce mental load immediately

- Profiles
  - Manage tone and defaults
  - Must not introduce comparison or performance pressure


## Patterns to Follow

- Prefer small, composable SwiftUI views
- Keep copy minimal and non-judgmental
- Use explicit, readable names over clever abstractions
- Centralize “forgiveness logic” and “completion logging” so it stays consistent
- Avoid visual states that imply failure (red badges, overdue counts, “backlog”)


## “Emotional Safety” Architectural Rules

The UI should not create pressure by:

- showing accumulating overdue items
- showing productivity metrics, streaks, grades
- escalating reminders or repeating endlessly
- using red error-like styling for normal life outcomes

If a proposed change adds pressure, it must be rejected (see WITHYOU_PRINCIPLES.md).


## How to Work in This Repo (for Codex)

When implementing a change:

1. Read WITHYOU_PRINCIPLES.md first.
2. Identify which models/views are impacted.
3. Make minimal changes that fit existing patterns.
4. Prefer diff-friendly edits.
5. If unsure, add a brief comment explaining the choice in code.

When adding a new feature, add:
- a small section to WITHYOU_PRINCIPLES.md if it introduces a new kind of behavior
- a small section here if it introduces a new architectural pattern
