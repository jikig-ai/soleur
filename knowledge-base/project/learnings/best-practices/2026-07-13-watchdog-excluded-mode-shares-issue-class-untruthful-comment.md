---
title: 'A new watchdog failure-mode that shares a downstream issue class but is excluded from the gate''s if: makes the gate output empty — and any else that claims the gated action happened lies'
date: 2026-07-13
category: best-practices
tags: [watchdog, state-machine, github-actions, observability, operator-truthfulness, gate-if, orthogonal-review]
issue: 6374
pr: 6384
status: solved
synced_to: [observability-coverage-reviewer]
---

# Watchdog excluded-mode-shares-issue-class → empty gate output → untruthful downstream comment

## Context

`feat-one-shot-inngest-watchdog-observability-6374` (#6374, PR #6384) hardened the
Inngest liveness watchdog. A review pass on the P2 fixes surfaced an
operator-truthfulness bug that no mechanical gate (tsc, tests, semgrep) catches,
because it lives in the *prose* the watchdog posts back to the operator.

The whole PR is about operator-truthfulness (a watchdog that pages must not lie
about what it did), which is exactly why two orthogonal review lenses —
architecture flow-tracer and observability-coverage — independently converged on
the two truthfulness findings below.

## The generalizable trap

When a watchdog / state-machine adds a **new failure-mode** that:

1. shares a downstream **issue class** (or shared comment branch) with an
   already-gated path, but
2. is **excluded from that gate's `if:`**,

then the gate's output variable is **empty** (`''`) for that mode — not
`'true'`/`'false'`. Any downstream branch that assumes the variable is a boolean
— an `else` that claims "the gated action happened" — emits **untruthful text**
for the excluded mode.

Concretely: `secret_unset` fell through to the `[ci/inngest-down]` issue class,
but the restart age-gate step's `if:` only fired for `inngest_down` /
`inngest_unhealthy`. So `steps.agegate.outputs.restart_ok == ''` for
`secret_unset`, and the down-branch comment's `else` posted **"Restart
re-dispatched"** even though **no restart was dispatched**.

## The fix (two orthogonal moves)

1. **Route the excluded mode to its own soft class** so it stops borrowing the
   gated path's comment branch (`secret_unset` → its own soft class, not
   `[ci/inngest-down]`).
2. **Flip the comment to positive-truth**: assert the action only when the
   evidence is present.
   - `if RESTART_OK == 'true'` → claims a dispatch happened (evidence-backed)
   - `elif RESTART_OK == 'false'` → escalates (gate ran, declined)
   - `else` (empty) → truthful **no-verdict** comment (never claims the action)

Positive-truth ordering (assert-on-`true`, escalate-on-`false`, no-claim-on-empty)
is the shape that stays honest when a third mode is later added: an unhandled mode
falls into the truthful `else`, not into a false claim.

## Sub-insight (GitHub Actions `if:` semantics)

A plain-expression step `if:` with **no** `always()` / `success()` / `failure()`
wrapper gets an implicit `success() &&` injected. So if a **prior** step
**errors**, the step is **skipped** (not run-with-empty-inputs).

This distinction matters when reasoning about empty step outputs:

- "age-gate step itself errors → empty `restart_ok` → untruthful comment" is
  **NOT reachable** — the downstream file-issue/comment step also carries the
  implicit `success()` and is itself skipped when a prior step errored.
- "mode **excluded** from the gate's `if:` → empty `restart_ok`" **IS reachable**
  — the gate is *skipped by its own `if:` predicate* (a normal, non-error skip),
  the workflow keeps running, and the downstream comment step executes with the
  empty output.

So when you see an empty step output feeding a downstream branch, first classify
**why** it is empty: *gate skipped by its own `if:`* (reachable — must handle) vs
*prior step errored* (implicit-`success()` skips the consumer — not reachable).
Only the first needs a truthful empty-branch.

## Prevention

- When adding a failure-mode to a watchdog/state-machine, grep every downstream
  **issue class** and **comment branch** the mode can reach, and confirm each
  gate whose output those branches read actually **includes** the new mode in
  its `if:`. If not, the gate output is empty for that mode — give it its own
  branch or a truthful no-verdict path.
- Never write an `else` that asserts a gated action happened. Use positive-truth
  ordering: assert on the evidence value, escalate on the negative value, emit a
  no-claim comment on empty/unknown.
- On observability/watchdog PRs, spawn **orthogonal** review lenses (architecture
  flow-tracer + observability-coverage-reviewer). The two truthfulness findings
  here came from independent lenses — a single lens would likely have caught one.

## Session Errors

**CWD-drift: a later repo-relative `git add` failed pathspec-not-match after an
earlier `cd apps/web-platform &&` in a prior Bash call.**
- Recovery: re-ran with an absolute-worktree `cd` chained into the same call.
- Prevention: chain `cd <worktree-abs> && <git cmd>` in a single Bash call — the
  Bash tool persists CWD across calls. (Already documented in work/SKILL.md —
  recurring-but-already-covered.)

**Two review agents stalled on the 600s stream watchdog; re-spawned.**
- Recovery: re-spawned the stalled agents and proceeded with the returned set.
- Prevention: review/SKILL.md already documents parallel-review stalls +
  proceed-with-returned-agents. (Recurring-but-already-covered.)

**`function-registry-count.test.ts` reverse-parity guard failed on the new
GHA-fired monitor.**
- Recovery: exempted the `scheduled-inngest-health` monitor inline via the
  `NON_INNGEST_MONITORS` allowlist.
- Prevention: one-off TDD fallout — new GHA-fired monitors that are not Inngest
  functions must be added to the reverse-parity exemption when introduced.

## Related Issues

- See also: [multi-agent-review-catches-feature-wiring-bugs.md](./2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md) — orthogonal review lenses each catch a distinct bug class the mechanical gates miss.
- See also: [../2026-06-01-silence-detector-needs-out-of-band-liveness-signal.md](../2026-06-01-silence-detector-needs-out-of-band-liveness-signal.md) — same Inngest watchdog surface.
