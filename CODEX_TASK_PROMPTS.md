# Codex Task Prompts — WithYou

These prompt templates are designed to keep changes aligned with:
- WITHYOU_PRINCIPLES.md (product + emotional safety)
- ARCHITECTURE.md (structure + patterns)


## General Rules (include in most prompts)

- Read WITHYOU_PRINCIPLES.md and ARCHITECTURE.md before making changes.
- Do not add streaks, scores, overdue pressure, red badges, or punitive copy.
- Keep copy minimal and neutral.
- Prefer simple, explicit code over abstraction.


## Prompt: Implement a new feature (small)

“Implement [FEATURE] in the WithYou app.

Constraints:
- Must comply with WITHYOU_PRINCIPLES.md (emotional safety > optimization).
- Follow patterns described in ARCHITECTURE.md.
- Keep UI copy minimal and neutral.
- Provide a clear diff and list the files changed.

Definition of done:
- Feature works end-to-end
- No new pressure mechanics (overdue, streaks, escalation)
- No significant architectural drift”


## Prompt: Refactor safely

“Refactor [AREA] for clarity without changing user-visible behavior.

Constraints:
- Must preserve WithYou emotional-safety behavior.
- Do not introduce new state that implies urgency or failure.
- Keep changes minimal and diff-friendly.

Output:
- Explain what changed and why
- Provide any follow-up suggestions”


## Prompt: Fix a bug

“Fix bug: [DESCRIPTION].

Constraints:
- Preserve WithYou principles (no shame mechanics).
- Add guardrails / defensive checks if appropriate.
- If there are multiple options, choose the simplest safe fix.

Output:
- Root cause
- Fix summary
- Files changed
- Any test steps”


## Prompt: Add copy

“Update UI copy for [SCREEN/FEATURE].

Constraints:
- Follow language rules in WITHYOU_PRINCIPLES.md:
  - calm, neutral, minimal
  - avoid pressure and guilt
- Prefer short phrases like: ‘Saved.’ ‘Nice.’ ‘That counted.’

Output:
- Proposed strings
- Where they appear”


## Prompt: Add instrumentation (very limited)

“Add minimal logging for [AREA] intended only for debugging.

Constraints:
- No productivity analytics
- No user scoring
- Logs should not be user-facing
- Keep it behind DEBUG where possible”
