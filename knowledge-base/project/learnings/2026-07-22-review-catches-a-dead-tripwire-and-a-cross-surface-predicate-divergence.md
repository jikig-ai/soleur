# Learning: review on the implemented diff catches a dead alert-tripwire and a cross-surface predicate divergence

## Problem

The `action-required` staleness contract (#6836) shipped a fail-safe auto-close cron whose design
was already reviewed twice at plan time (architecture-strategist + data-integrity-guardian at
deepen-plan, which caught the two FATAL findings D1/D3). Yet multi-agent review on the **implemented
diff** found two genuine bugs the plan-time reviews structurally could not see — both in code that
existed only after implementation:

1. **A dead alert-tripwire.** The Sentry "veto-bypass" alert filtered on `sla_action=expire AND
   human_engaged=true`, but the worker set the `human_engaged` tag from `decision.humanEngaged` —
   and `decideAction` returns `expire` **only when `!humanEngaged`**. So on every expire the tag
   was tautologically `"false"`; the alert could never fire. It was a self-report backstop for the
   brand-survival failure case that was structurally inert.

2. **A cross-surface predicate divergence.** The digest §4 render de-polluted by excluding the broad
   `content` label, but the cron's `classifyIssue` **deliberately refused** to key on `content` (the
   D1 fix — a human can attach `content` to a genuine ops emergency). So a live ops emergency tagged
   `content` was **escalated to p0 by the cron yet dropped from the operator's only comprehension
   surface** — the exact "surfaced-but-buried" failure the whole feature exists to end.

## Solution

1. **Dead tripwire → independent re-derivation.** In the destructive `expire` step, RE-FETCH the
   issue and re-compute the veto **independently** of the memoized decision. If the independent check
   now says a human is engaged (a late-engagement race, or a future `decideAction` veto regression),
   abort the close AND emit `human_engaged=true` — so the alert becomes a live tripwire that fires on
   a genuine veto bypass. This one restructure also closed a TOCTOU window on the close and let the
   close-before-label reorder happen.

2. **Predicate divergence → single source of truth.** Both surfaces now key the exclusion on the
   agent-owned `content-publisher` (not the human-attachable `content`), so the digest shows exactly
   what the cron treats as an ops ask. The read side and the write side must use the SAME predicate.

## Key Insight

- **An alert whose filter tag is derived from the same predicate that gates the alerted action is a
  DEAD tripwire — it can never fire.** The fix is to compute the tag via an INDEPENDENT re-derivation
  at the action site (a fresh re-check decoupled from the decision), so a disagreement between "we
  did X" and "the invariant says we shouldn't have" is what trips it. Ask, of any alert on a
  fail-safe action: "can the tag it filters on ever be true when the action fires under CORRECT
  code?" If no, either the alert is a pure regression tripwire (fine, if the tag is derived
  independently so a regression flips it) or it is inert (a bug).

- **When two surfaces de-pollute/gate on a label set — a READ surface (a render/digest/filter) and a
  WRITE surface (a classifier/close-authority) — they MUST key on the same predicate.** A divergence
  where the read surface hides what the write surface keeps (or vice-versa) silently drops the exact
  edge case one of them was carefully designed to preserve. Grep both surfaces' label sets and assert
  equality.

- **Plan-time review and implemented-diff review catch DIFFERENT bug classes.** The plan reviews
  caught the fatal *design* findings (the non-bot clock, the fan-out); only review on the actual code
  caught the *wiring* bugs (the tautological tag, the divergent constant). Both passes are load-bearing
  at a `single-user incident` threshold.

## Session Errors

- **First full-suite run RED — 2 parity gaps from adding an Inngest cron** (missing
  `sentry_cron_monitor`, stale `function-registry-count`). Recovery: added the monitor + bumped the
  count. **Prevention:** already mechanically enforced by `sentry-monitor-iac-parity.test.ts` +
  `function-registry-count.test.ts` — the LESSON is that adding a cron is a 4-artifact change
  (route.ts + cron-manifest + routine-metadata + a sentry_cron_monitor); the touched-file test loop
  does not see these, only the full-suite exit gate does. Run `test-all.sh` before shipping any new
  Inngest function. One-off (caught + fixed).

- **A background `test-all` completion notification read "exit code 0" while the real
  `TESTALL_EXIT=1`.** The notification reports the trailing command (`tail`), not the runner.
  Recovery: grepped the explicit `TESTALL_EXIT=` line + the runner's own summary. **Prevention:**
  already documented in `work/SKILL.md` (the background-wrapper-exit-code trap); always verify the
  explicit rc file, never trust the "completed (exit code 0)" notification for a `cmd > log; echo`
  shape. One-off.

- **Event-worker initially declared a `SENTRY_MONITOR_SLUG` + `postSentryHeartbeat`** — but a
  `sentry_cron_monitor` pages MISSED forever for an event-fired (non-scheduled) function. Recovery:
  dropped the heartbeat/slug; the worker's failures surface via `reportSilentFallback` instead.
  **Prevention:** enforced by `sentry-monitor-iac-parity.test.ts` (every declared slug needs a
  monitor). Event-only Inngest functions declare NO monitor slug. One-off.

## Tags
category: workflow-patterns
module: review, inngest, sentry-alerts, operator-digest
issue: 6836
