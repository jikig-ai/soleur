---
name: Defense relaxation requires naming the new ceiling
description: When a plan relaxes or removes a load-bearing defense, plan/deepen-plan must enumerate "what was the previous defense protecting against, and what's the new ceiling for the same threat?"
type: best-practice
date: 2026-05-05
pr: "#3225"
domain: engineering
tags:
  - planning
  - defense-in-depth
  - testing
  - dom-testing
  - scope-out-criteria
---

# Learning: Defense Relaxation Must Name the New Ceiling

## Problem

PR #3225 fixed the kb-concierge "agent went idle without finishing" error
on PDF summarize. The plan correctly identified the cause —
`DEFAULT_WALL_CLOCK_TRIGGER_MS = 30s` was too tight for PDF Read+summarize
turns — and proposed two changes:

1. Raise the default to 90s.
2. Reset the wall-clock window on every assistant block (text or tool_use).

The plan's deepen pass confirmed this fix shape and listed compatible
tests. **Architecture-strategist (P1) caught at review time that the new
"any block resets" semantic created a chatty-stall vector**: a single turn
emitting one block every <90s never trips runaway, the cost cap fires
only at SDKResultMessage boundaries (so mid-turn cost is invisible), and
idle reap is also reset on every assistant message. Result: a buggy
plugin or hung tool loop could stream blocks indefinitely without ever
tripping the runaway timer.

## Root Cause

The plan removed an implicit defense without naming the new defense for
the same threat surface. The 30s ceiling was load-bearing in two roles
that the plan only treated as one:

- **Idle-window guard:** "no agent activity for 30s → declare runaway"
  (the bug-target case — too tight).
- **Absolute turn ceiling:** "no single turn runs longer than 30s"
  (a side-effect that bounded chatty stalls).

Raising to 90s + resetting on every block fixed role 1 (the bug) but
silently dissolved role 2. The plan/deepen-plan workflow did not surface
the bifurcation because the planner thought of the 30s value as a single
defense.

## Solution

1. Add `DEFAULT_MAX_TURN_DURATION_MS = 10 min` as an absolute hard ceiling,
   anchored on `firstToolUseAt` (turn origin), NOT reset by per-block
   activity. Cleared on `SDKResultMessage` and re-armed on
   `awaitingUser=false` resume.
2. Discriminate the two guards in the WorkflowEnd payload via a new
   `reason: "idle_window" | "max_turn_duration"` field so operators can
   tell which fired.
3. Forward the diagnostic fields over the WS error variant (optional)
   so an API client / agent observing the conversation reaches
   observability parity with operators reading pino logs.

## Key Insight: When Relaxing a Defense, Name the New Ceiling

For every plan that **removes** or **relaxes** a load-bearing constraint
(timeout, byte cap, retry budget, rate limit, validator gate), the plan
MUST answer:

> "What was the previous defense protecting against, beyond the symptom
> we're fixing? What new defense covers that threat surface now?"

If the answer is "the same defense, at a relaxed value," that's only
acceptable when the relaxation is itself bounded (e.g., 30s → 90s
without changing the reset semantics). When the relaxation also changes
the *semantic* (here: from "absolute window from first tool_use" to
"rolling window per block"), the side-effect role of the original
ceiling has been silently dissolved — and a new explicit ceiling MUST
be named or its absence justified.

This is mechanically what the architect's "what's the load-bearing
defense?" question should surface at plan or deepen-plan time, not at
review time.

## Sub-Lesson: DOM `textContent` Vacuous-RED

While writing tests for the duplicated "Concierge / Soleur Concierge"
header, the first RED-test attempt used:

```ts
expect(text).not.toMatch(/Concierge\s+Soleur Concierge/);
```

This passed against the buggy code (vacuous RED). DOM `textContent`
concatenates adjacent inline elements **without whitespace** — two
`<span>`s rendering "Concierge" and "Soleur Concierge" produce
`"ConciergeSoleur Concierge"`, not `"Concierge   Soleur Concierge"`.
The `\s+` regex requirement made the assertion miss the bug entirely.

**Fix:** count occurrences of the role-name substring in the header
element scoped via `data-testid`:

```ts
const header = container.querySelector('[data-testid="message-bubble-header"]');
const concierges = header.textContent?.match(/Concierge/g) ?? [];
expect(concierges).toHaveLength(1);
```

**Generalization:** when asserting "no duplicate visible label" via DOM
content, never rely on whitespace separators in `textContent` — count
occurrences or scope to a specific element. This complements the
existing `cq-write-failing-tests-before` and the
`2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`
learning: vacuous-RED via assumed-but-absent whitespace is a new variant.

## Sub-Lesson: Scope-out Criteria Demand Concrete File Counts

First attempt to scope-out the WS observability finding claimed
`architectural-pivot`. The simplicity-reviewer dissented with concrete
arguments:

- "≥3 files materially unrelated" → actually 3 files all in
  `apps/web-platform/`, all directly downstream of the type already
  changed → fails the "unrelatedness must be concrete" gate.
- "design alternatives independently named by the agent" → the two
  approaches (extend `error` variant vs new variant) were author-
  surfaced, not agent-surfaced → fails contested-design.
- "additive, optional fields, no breaking impact" → that's the
  signature of fix-inline, not scope-out.

Recovery: flipped to fix-inline; ~30 LOC across `lib/types.ts`,
`server/cc-dispatcher.ts`, `test/cc-dispatcher.test.ts`. The simplicity-
reviewer's dissent saved a misclassified scope-out from shipping. This
is exactly the failure mode `rf-review-finding-default-fix-inline` and
the second-reviewer co-sign gate exist to catch.

## Sub-Lesson: Test-Compatibility Audit Must Enumerate, Not Sample

Deepen-plan's test-compatibility section listed AC7/AC8/AC9/AC17/silent-
fallback as compatible with the new "any block resets" semantic, but
did not enumerate ALL test files that pinned the old "30s from first
tool_use" behavior. The Stage 2.2 secondary-trigger test in
`soleur-go-runner.test.ts` used `wallClockTriggerMs: 30_000` AND emitted
multiple tool_uses spread across 30s and asserted runaway fires — exactly
the contract the new semantic dissolves. The test broke at GREEN time
and required updating mid-implementation.

**Generalization for deepen-plan:** when changing a tunable's semantic
(here: when does the timer reset?), grep all test files for usages of
that tunable and audit each one explicitly. `grep -rn "<tunable>" test/`
takes 10 seconds. The audit is mechanical; sampling instead of
enumerating means at least one test will surface the gap as a broken
GREEN run.

## Session Errors

1. **Plan + deepen-plan didn't surface the chatty-stall vector when
   relaxing the 30s ceiling.** Recovery: added MAX_TURN_DURATION_MS
   ceiling at review time. **Prevention:** plan and deepen-plan SKILL
   instructions should explicitly require the "what was the previous
   defense protecting against" audit when removing or relaxing a
   defense. See proposed routing below.

2. **Vacuous RED tests via DOM textContent whitespace assumption.**
   Recovery: switched to occurrence-count + `data-testid` scoping.
   **Prevention:** add a sharp-edge note to `work` skill / project
   constitution: when asserting "no duplicate visible content" via
   `textContent`, never rely on whitespace separators between adjacent
   inline elements.

3. **Bash CWD non-persistence in worktree.** Already covered by
   `cq-for-local-verification-of-apps-doppler` (and a learning file at
   `2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`). Re-applied
   the rule mid-session. **Prevention:** existing rules sufficient.

4. **First scope-out attempt was wrong (`architectural-pivot` claim
   failed its own definition).** Recovery: simplicity-reviewer dissent
   flipped to fix-inline. **Prevention:** existing rule
   `rf-review-finding-default-fix-inline` + the co-sign gate sufficed
   — the dissent IS the prevention mechanism working as designed.

5. **Plan amendment mid-pipeline (post-deepen, pre-work).** User's
   "tried nudging but it doesn't help" surfaced the turn-2 case the
   deepen pass didn't enumerate. **Prevention:** when a UI bug
   reproduces in a thread, plan/deepen-plan MUST audit at least the
   first-message AND follow-up rendering paths (`isFirst` / non-first
   branches) — not just the first-render case the screenshot captures.

6. **Deepen-plan's test-compatibility audit missed Stage 2.2 secondary-
   trigger test.** Recovery: updated test mid-implementation.
   **Prevention:** when a plan changes a tunable's semantic,
   deepen-plan MUST `grep -rn "<tunable>" test/` and audit every
   matching test file, not sample.

## Routing Proposal

**To `plan` skill (or `deepen-plan` skill — whichever owns the
defense-relaxation audit):** add a sharp-edge / Phase entry along the
lines of:

> When the plan relaxes or removes a defense (timeout, retry budget,
> rate limit, validator gate, byte cap), enumerate every threat surface
> the original defense was bounding — including side-effect roles the
> defense was incidentally serving. For each, name the new defense or
> document why none is needed. "Same defense at a more permissive value"
> is acceptable; "same defense with a different reset semantic" needs an
> explicit new ceiling.

**To `deepen-plan` skill:** when a plan changes a tunable's semantic
(reset trigger, scope, evaluation point), `grep -rn "<tunable>" test/`
and enumerate every matching file in the test-compatibility audit.
Sampling produces missed updates that surface as broken GREEN runs.

These routes are domain-scoped (plan/deepen-plan skills) per the
AGENTS.md placement gate — NOT cross-cutting session invariants — so
they belong in the owning skill, not AGENTS.md.

## Related

- `cq-write-failing-tests-before` — the TDD gate that this PR's
  vacuous-RED slipped past.
- `knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`
  — prior learning on RED-quality verification (gated vs ungated). This
  PR adds the DOM textContent whitespace variant.
- `rf-review-finding-default-fix-inline` + simplicity-reviewer co-sign
  gate — caught the misclassified scope-out.
- ADR-022 (sdk-as-router) — the runaway timer's architectural home; a
  one-line amendment recording "per-block reset + absolute hard cap" is
  worth landing in a follow-up.
