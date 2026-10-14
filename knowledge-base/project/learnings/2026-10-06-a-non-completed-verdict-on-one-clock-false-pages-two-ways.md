---
title: A non-completed verdict judged on one clock false-pages two ways
date: 2026-10-06
category: workflow-issues
tags: [ci-observability, alerting, workflow-runs-api, test-design, stubs]
module: scripts
component: cron-merge-queue-stall-dispatch
problem_type: logic_error
severity: medium
---

# A Non-Completed Verdict Judged on One Clock False-Pages Two Ways

## Problem

While implementing the #9513 executor-visibility check (the dispatcher reads
the previous `merge-queue-stall-check.yml` run before dispatching the next and
posts an error-status Sentry check-in when that run is red or stuck), the first
design judged every non-completed run by one clock: `created_at` older than
~11 min → `stuck` → page. Two independent false-positive surfaces fell out of
that single basis at review:

1. **The wrong clock for `in_progress`.** A run that queued 9 min and started
   2 min ago is legitimately mid-flight — its *job* has used 2 of its 10
   `timeout-minutes`, but its `created_at` age reads 11 min → `stuck` → a page
   for a healthy run. Queue wait and job runtime are different clocks;
   `created_at` conflates them.
2. **The missing floor for interlopers.** The newest listed run is assumed to
   be the previous tick's (~10 min old at check time). But the schedule
   fallback (or a manual `gh workflow run`) can land seconds before the check
   fires — a just-created `queued` run at any positive age threshold would
   page on an interloper that is probably seconds from a runner.

A stub-fidelity defect surfaced in the same review pass: the `gh` stub's
`issue close` arm recorded `CLOSE:` *before* honoring `GH_STUB_CLOSE_FAIL`, so
a failed close would have claimed an effect that never happened.

## Solution

Split the `stuck` basis per status class
(`cron-merge-queue-stall-dispatch.ts`):

- `in_progress` → `stuck` only when `run_started_at` (not `created_at`) is
  older than 11 min — strictly above the job's own `timeout-minutes: 10`.
  Missing/unparseable `run_started_at` reads `pending`, never `stuck`.
- `queued` / `waiting` / `requested` / `pending` → `stuck` only when
  `created_at` is older than 5 min — a floor well below the expected
  ~10-min age of the previous tick's run and well above a just-landed
  interloper.

Vitest arms cover both directions: queue-20min + job-3min = `pending`,
job-20min = `stuck`, queued-2min = `pending`, queued-20min = `stuck`,
missing `run_started_at` = `pending`. The gh stub now checks the failure
flag before writing the `CLOSE:` record.

## Key Insight

"Non-completed" is a *category* over several different clocks — queue wait,
approval wait, and job runtime each have their own baseline and their own
normal range. A verdict that joins them under one threshold inherits the
worst false-positive surface of each member. Judge each status class on the
clock that bounds *its* normal behavior, and put a floor tuned to the
expected age of the object the check was written for so an interloper
landing moments before the check can never page. Companion: a stub's record
of an effect IS a claim — it must be written after the failure check, or the
failing arm testifies to an effect that never ran.

## Session Errors

1. Single-clock `stuck` model shipped into review with two false-page
   surfaces (queue-waited `in_progress`; just-landed interloper runs).
   **Prevention:** when a verdict reads an API time field, enumerate the
   status classes it covers and ask which clock bounds each one's *normal*
   duration before picking a threshold.
2. `gh` stub `issue close` recorded the close before honoring the failure
   flag. **Prevention:** in any stub, order is `parse → fail → record` —
   never record an effect the real command did not produce.
3. Dead mock helpers (`getRejects`/`getReturns`/`runsResponses`) left behind
   when the GET arms moved to flag-based errors. **Prevention:** after
   landing a test refactor, grep the helper's name; zero call sites = delete.
4. Scratch M7-dump verification twice failed before verifying: an
   unquoted nested heredoc let bash expand `${EPOCHSECONDS}` inside the
   Python payload, and running a copy of the suite from `/tmp` broke its
   `BASH_SOURCE`-relative `REPO_ROOT` derivation. **Prevention:** copy the
   suite *inside* `scripts/` and force the failure arm by editing the
   expected count, not by re-implementing the splice in a scratch harness.
5. `scripts/lint-infra-no-human-steps.py --help` unexpectedly invoked
   `terraform` (its arg parsing passes through). **Prevention:** read the
   script's entry point before probing with `--help`.
6. A prior `sed` checkbox sweep made the `edit` tool's `old_string` for a
   tasks.md bullet stale. **Prevention:** grep the live file before
   composing an `edit` after any scripted sweep.

## Prevention

- For verdict designs over external API status/timestamp fields: table
  `status class → the clock that bounds its normal duration → threshold`
  in the plan before implementing.
- For stubs: assert the order `failure-check precedes effect-record` by
  reading the stub case arm, and add one arm that exercises each failure
  flag.
- Covered-by-existing: the general class ("every defect was in my
  verification") is already recorded in
  `learnings/2026-09-18-every-defect-was-in-my-verification-not-the-feature.md`;
  this file adds the API-clock and stub-ordering instances.

## Tags
category: workflow-issues
module: scripts
