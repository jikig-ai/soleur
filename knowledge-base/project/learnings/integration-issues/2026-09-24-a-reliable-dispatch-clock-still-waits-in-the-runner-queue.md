---
title: "A reliable dispatch clock still waits in the runner queue — measure latency on the jobs you are budgeting"
date: 2026-09-24
category: integration-issues
module: apps/web-platform/server/watchdog-dispatch-clock.ts
tags: [github-actions, sentry-crons, watchdog, measurement, redundancy]
issue: 8495
pr: 8691
---

# Learning: a reliable dispatch clock still waits in the runner queue

## Problem

GitHub Actions `schedule:` delivered the external Inngest watchdog (`*/15`) and the zot alarm
(hourly) only once every 2–7 h, so their Sentry cron monitors sat permanently `missed` and a
~59-min Inngest outage (2026-09-22) filed nothing. #8495 moved the trigger to an in-process
`workflow_dispatch` clock on both web hosts (ADR-248).

The plan then sized the Sentry margins for "a reliable clock": inngest 15 min, zot 30 min, with
~3 min left for "runner queue (measured 0 s in 39/40 runs, 157 s worst)". That sample was taken
from OTHER workflows. On the watchdogs' own jobs (job `started_at − created_at`, last 40 runs)
the queue was median ~30 s, p75 ~11 min, **p90 ~20 min, max ~38–40 min**. A 15-min margin would
have missed ~40% of slots — recreating the exact noisy-alarm defect the PR existed to remove.

## Solution

- `workflow_dispatch` fixes RUN creation (seconds, every time) — it does nothing for the JOB's
  wait in the org runner queue (#8450's concurrency budget). Budget the monitor margin as
  clock delay (poll + jitter + tick deadline) + a MEASURED queue allowance + runtime: inngest 45,
  zot 60. `sentry-monitor-iac-parity.test.ts` pins the budget and names the re-measure command.
- The margin bounds only dead-trigger detection; a real outage pages as soon as a run executes
  and posts `?status=error`, independent of the margin — say which one a number governs.
- "The other host covers a failed slot" is false for correlated failures: a GitHub API blip hits
  both hosts in the same minute. Retry inside the slot (3 attempts, 2 min apart) and re-read
  runs before each retry so a timed-out POST that actually landed is not dispatched twice.
- A second run per slot becomes routine (host collisions, late fallback ticks), so the workflows
  themselves must be idempotent: tracker lookups LIST by label (issue search lags a just-created
  issue) and the restart arm skips when a dispatched restart is queued/running/<12 min old.

## Key Insight

A latency number is a property of a POPULATION. Before a measured latency enters a budget,
name the population the budget is about (these workflows' jobs, on this org's runners, this
week) and measure THAT — a sample from sibling workflows is a different population that can
differ by two orders of magnitude at the tail. And redundancy only covers independent
failures: for every "the other replica covers it", name a failure both replicas share.

## Session Errors

1. **Plan margin budget used a queue sample from other workflows** (review P1). Recovery:
   re-measured on the watchdogs' own jobs via `gh api …/runs/<id>/jobs`, re-derived margins 45/60,
   pinned the budget in the parity test. **Prevention:** plan-sharp-edges bullet (routed in this
   PR): measure latency on the exact population the budget governs; cite the command.
2. **Unmeasured claims in first-draft prose** ("start within seconds, every time", "rare
   collision", "NTP skew far below 30 s"). Recovery: code-quality seat ran the falsifying
   commands; prose corrected to run-vs-job, ~5–10%, and "not provisioned; only duplicates".
   **Prevention:** for every causal/universal sentence a diff adds, name and run its falsifier
   before writing it (existing compound/work rule — applied late here).
3. **Redundancy assumed independent failures** ("the other host covers a failed slot"). Recovery:
   bounded in-slot retry with re-read. **Prevention:** captured in Key Insight; review's coverage
   consult caught it — keep running that consult at ≥6 findings.
4. **Plan named a guard that was never built** (dependency-cruiser `watchdog-clock-not-via-inngest`;
   the config is generated + non-blocking, so a TS-AST walker test replaced it). Recovery: QA's
   "ls every control the plan names" pass → plan addendum. **Prevention:** existing QA note; record
   a deviation in the plan the moment the work phase replaces a named control, not at QA.
5. **Provisional ADR-246 collided with open PR #8626.** Recovery: swept to ADR-248 before the
   ADR was written. **Prevention:** existing rule — check open PRs' ADR files before picking an
   ordinal (`gh pr list --json files`).
6. **Equivalent mutant** (`eligibility: "" || "…"` evaluates to the non-empty string) scored
   SURVIVED. Recovery: re-ran with a real empty string → RED. **Prevention:** a mutation that
   leaves the expression's VALUE unchanged is equivalent; prefer replacing the whole value.
7. **Mutations W1/W2 did not land** (anchor matched multiple sites; battery required exactly one).
   Recovery: re-ran single-site. **Prevention:** the battery's did-not-land guard worked as
   designed — keep `count == 1` and re-anchor rather than loosen it.
8. **Touched-shard gate queued behind three sibling worktrees' runs** (LOCK_WAITING, up to 1 h).
   Recovery: killed my queued run with `proc.sh kill_mine`, ran consumer-derived suites + the
   lint ratchet. **Prevention:** run `test-all.sh --capacity` first (done) and go straight to the
   substitute when siblings > 0.
9. **`git ls-files` over the whole repo hit ENOBUFS in a vitest test.** Recovery: pathspec-scoped
   listing + `maxBuffer`. **Prevention:** scope `git ls-files` in tests to the paths the
   assertion is about.
10. **tsc errors in new tests** (implicit `any` on a mock-calls callback; `ProcessEnv` typing on
    `execFileSync` env). Recovery: typed the param; cast the env. **Prevention:** run
    `./node_modules/.bin/tsc --noEmit` before committing new test files (vitest type-checks lazily).
11. **Issue-filing gate blocked three times** (no User-Impact line; command chained after a
    `printf`; `Fix-Size` inside the inline threshold). Recovery: `Mandated-By:
    wg-when-an-audit-identifies-pre-existing` on its own line, `gh issue create` alone in its call
    → #8707. **Prevention:** existing review/SKILL.md guidance (own call, absolute body file);
    for a pre-existing audit finding reach for the Mandated-By exit first.
12. **Site count written from memory** (14 vs 15 converted lookups). Recovery: the test's own
    anti-vacuity equality caught it. **Prevention:** derive counts from the artifact, as the
    work skill already prescribes.
13. **Forwarded from planning:** the deepen-plan PAT gate false-positived on the Cloudflare
    `cf_api_token` variable name (reworded); one sharp-edges page was first read from the
    bare-repo mirror. **Prevention:** existing rules (PAT gate wording; never read from the bare
    root in a worktree).

## Tags

category: integration-issues
module: watchdog-dispatch-clock
