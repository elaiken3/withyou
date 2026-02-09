# WithYou — Product Principles & Development Constraints

This document defines the non-negotiable principles of the WithYou app.
All development decisions — human or AI-assisted — must respect these rules.

If a feature violates these principles, it does not ship.

This is not a productivity optimizer.
This is an executive-function support system designed for emotional safety.


## Purpose

WithYou exists to help people with ADHD complete tasks by:

- capturing thoughts so they stop competing for attention
- protecting focus long enough for meaningful progress
- making starting small and safe so finishing becomes possible

The goal is not to do more.
The goal is to reduce cognitive load so one thing can get done.


## Core Design Philosophy (Non-Negotiable)

These rules override all other considerations:

- One thing at a time
- Thoughts are not obligations
- Missed tasks are neutral
- Short focus windows are valid
- Emotional safety is more important than optimization
- The app never shames, nags, or pressures the user

If a proposed change introduces urgency pressure, guilt, punishment, or comparison, it must be rejected.


## Explicitly Forbidden Mechanics

The following must never exist in WithYou:

- Streaks of any kind
- Scores, points, or productivity “grades”
- Red or alarmist overdue states
- Punitive reminders or escalating notifications
- Analytics dashboards focused on output or efficiency
- Language that implies failure, laziness, or discipline

Completion is acknowledged gently.
Progress is quiet.
Absence is neutral.


## Language Rules

All user-facing language must be:

- calm
- neutral
- non-judgmental
- minimal

Preferred patterns:

- “Saved.”
- “I’ve got it.”
- “Nice.”
- “That counted.”

Avoid:

- exclamation pressure
- motivational clichés
- time guilt (“you should”, “overdue”, “behind”)
- language that turns thoughts into demands


## Feature Intent by Area

### Capture
Capture is a relief valve, not a commitment.
Saving a thought must reduce mental load immediately.

A captured item is not a promise.
It is a parked thought.

### Inbox
The Inbox is a mental parking lot.
Nothing in the Inbox is overdue.
Nothing nags.

The Inbox must feel safe to ignore temporarily.

### Reminders
Reminders exist to help users start, not to enforce memory.

Every reminder should:
- clarify the task
- suggest a gentle first step
- offer forgiveness if missed

Missed reminders must:
- not repeat endlessly
- not escalate
- ask once if they are still relevant
- then let go

### Focus Sessions
Focus Sessions exist to protect attention, not maximize output.

During a Focus Session:
- nothing else matters
- interruptions are handled without penalty
- brain dumps are welcomed

Ending a session should feel like completion, even if the task is not finished.

### Refocus
Refocus is a micro-reset for moments of overwhelm.
It should feel grounding, not corrective.


## Profiles
Profiles exist to personalize tone and defaults without adding complexity.

Profiles must not:
- introduce performance comparison
- create identity pressure
- imply that one way of working is better than another


## Development Guidance for AI Assistants (Codex)

When modifying or adding code:

- Prefer simplicity over cleverness
- Prefer clarity over abstraction
- Match existing architectural patterns
- Avoid introducing state that implies judgment or urgency
- When unsure, choose the gentler option

If a requirement conflicts with emotional safety, emotional safety wins.


## Decision Rule

If you have to ask:
“Does this add pressure?”
“Does this punish absence?”
“Would this make a bad day feel worse?”

The answer is:
Do not ship it.
