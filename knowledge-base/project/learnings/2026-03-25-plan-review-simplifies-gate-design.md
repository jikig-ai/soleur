# Learning: Plan review catches over-engineered gate design before implementation

## Problem

When designing enforcement gates for UX and content review in plan/work skills (#1137), the initial brainstorm produced a four-part solution: (1) brainstorm carry-forward rejection, (2) dual-signal Content Review gate (auto-detect "copy-heavy" AND domain leader confirms), (3) new Specialist Status subsection with `ran | skipped | pending` state machine, (4) work skill hard-block on `pending` with legacy detection.

Three plan reviewers (DHH, Kieran, code-simplicity) independently identified the same overengineering patterns before any code was written.

## Solution

Applied all three reviewers' simplifications:

- **Dropped dual-signal trigger.** Domain leader recommendation alone is sufficient — the CMO already made the "copy-heavy" judgment. Auto-detect second-guesses the domain expert.
- **Dropped Specialist Status subsection.** Extended existing `**Agents invoked:**` and added `**Skipped specialists:**` field to the heading contract instead of creating a parallel tracking system with a parseable state machine.
- **Dropped legacy detection.** Existing check 7 already WARNs on missing Domain Review. Old plans self-resolve as new plans are created.
- **Fixed insertion point.** Brainstorm carry-forward check fires BEFORE ux-design-lead invocation (step 3), not after — Kieran caught that the rejection must intercept earlier than the implementation assumed.
- **Defined pipeline mode behavior.** Auto-invoke missing specialists in pipeline mode instead of hard-blocking (no user to respond in one-shot).
- **Added agent failure path.** Kieran identified that `pending` was unreachable — no code path wrote it. Resolved by using `Skipped specialists` with error note instead.

## Key Insight

Plan review before implementation catches structural overengineering that implementation-time review cannot. Once code exists, reviewers optimize the code — they rarely question the approach. The brainstorm-to-plan transition is where unnecessary complexity enters, and the plan review gate is the last opportunity to catch it before effort is sunk.

The specific anti-patterns caught: (1) dual-signal classification when a single authority already decides, (2) new structured formats when existing fields can be extended, (3) transition code for states that self-resolve.

## Session Errors

1. **Markdown lint failure (MD032)** on first commit — missing blank line before list in brainstorm document. Recovery: added blank line and recommitted. Prevention: write lists with surrounding blank lines by default (already a markdown convention, just missed).
2. **Markdown lint failure (MD032)** on second commit — same issue in plan document. Recovery: same fix. Prevention: same as above.

## Tags

category: engineering
module: plan, work, workflow-patterns
