# Learning: a green dispatch check-in is not an executed probe, and plan-time pilot numbers expire

## Problem

Following up ADR-270 (merge queue, status `adopting`) on #9482: route the stall-dispatch cron monitor to email (#9493),
measure the canary items the ADR leaves open, and triage follow-ups (b), (c), (d) against their own triggers.

## Solution

- Routing was a one-label move (`monitor_ids`) plus one appended id in `alert-reference.json`. The hand-derived JSON was
  exactly what CI generates: `plan_pr` and its alert-reference gate passed on the first push, so no artifact round-trip
  was needed.
- Measurements were taken with a frozen definition (sync merges per merged human PR = PR commits with two parents whose
  second parent is an ancestor of `origin/main`), the numbers recorded once on the issue, and the ADR got a short
  addendum linking to that comment rather than restating it.

## Key Insight

1. **A dispatcher's green Sentry check-in means "dispatched", never "probe executed".** The executor workflow had no
   `if: failure()`, no notify step and no secrets, and dispatched runs are authored by a bot, so a red run alerted
   nobody. Routing the monitor to email does not close that; it needed its own tracked follow-up (#9513). When a liveness
   signal comes from the trigger and not from the thing triggered, say which one it covers.
2. **`run_started_at == created_at` is structural for `workflow_dispatch` runs** and says nothing about runner wait. The
   job-level number (job `started_at` minus run `created_at`) is the measurement.
3. **A plan's pilot numbers expire the moment the frozen run exists.** The plan carried 2.13 before / 0.83 after
   ("at the margin"); the frozen run gave 2.50 / 0.83 (delta 1.67, above the 1.3 break-even). The reviewer who read the plan
   alone would have taken the older reading as current. Mark pilot figures superseded in the same commit that records the
   final ones.
4. **Check the window against the definition before reading a mean.** The first "before" window included the adoption PR
   itself (merged at the cutoff), which the definition excludes.

## Session Errors

1. **`gh issue create --body-file $VAR` denied** — Recovery: literal absolute path. Prevention: the guard's own deny text
   states it; pass literal paths and keep `gh issue create` as its own call.
2. **`gh issue create` denied for naming no user-visible consequence** — Recovery: `--label meta/machinery` (CI/gate
   findings qualify). Prevention: same deny text lists the three exits; pick one before filing.
3. **`pgrep -f` denied (self-match)** — Recovery: `source proc.sh; kill_mine`. Prevention: already hook-enforced.
4. **`Edit` with an invalid parameter name** — Recovery: retried. Prevention: none needed (one-off).
5. **Scripted patch aborted on an anchor mismatch (nothing written)** — Recovery: corrected the anchor and re-ran.
   Prevention: the assert-before-write form did its job; read the file back after a scripted edit.
6. **"Before" sync window included the cutoff PR** — Recovery: re-selected excluding it and re-ran. Prevention: assert the
   window membership against the definition before computing means.
7. **Plan left superseded pilot numbers unmarked** — Recovery: added a superseded note and updated session-state.
   Prevention: supersede pilot figures when the frozen run lands.
8. **Affected-test gate queued behind a sibling's run for 20+ min** — Recovery: cancelled its own run and ran the consumer
   suites directly; ship Phase 4 re-runs the gate on the final tree. Prevention: already documented (LOCK_WAIT heartbeat).
9. **Turn ended on a future-tense commitment** — Recovery: stated a BLOCKED stop; resumed on the seat's completion.
   Prevention: end a turn only after performing the action, or name the gate.

## Tags
category: integration-issues
module: merge-queue, sentry-cron-monitors
