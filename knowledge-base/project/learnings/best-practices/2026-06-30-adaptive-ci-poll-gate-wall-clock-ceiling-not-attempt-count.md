---
date: 2026-06-30
category: best-practices
module: ci-cd
tags: [github-actions, ci-gate, fail-closed, deploy, polling, timeout]
issue: 5795
pr: 5798
---

# Learning: a fail-closed CI-poll deploy gate must wait on the workflow RUN, and cap on WALL-CLOCK, not attempt count

## Problem

`web-platform-release.yml`'s `await-ci` job gates the prod deploy on CI's synthetic
`test` aggregator check-run for the pushed SHA, polling a **fixed** 900s window. Under
GitHub runner contention this fail-closed on **every** squash-merge: prod stalled ~2.5h
on an old build (#5795). Two distinct mechanisms compounded:

1. **The check-run does not exist yet.** The `test` aggregator is `needs:[shards] +
   if:always()`. GitHub does **not create** the `test` check-run until those shards reach
   a terminal state. Under contention the shards sit `queued`, so
   `commits/<sha>/check-runs` returns `status=missing` for the full fixed window — the gate
   times out on a healthy-but-queued build. "Next release self-heals" never fires because
   each consecutive merge loses the **same** race.

2. **An attempt-count ceiling can be out-raced by API latency.** The first fix used
   `attempt >= MAX_ATTEMPTS` as the in-bash ceiling, sized so the in-bash `::error::` fires
   before the GHA `timeout-minutes` hard-kill. But that arithmetic budgeted only the
   `sleep INTERVAL_S` per iteration — NOT the 1–2 `gh api` round-trips each iteration also
   makes. Under the exact API-under-contention this gate targets, ~600 API calls at ~0.8s
   each consume the margin, so `timeout-minutes` hard-kills the job *before* the attempt
   ceiling is reached → a bare red job with **no `::error::`** = the silent-skip symptom
   the gate exists to eliminate.

## Solution

**Wait on the real CI signal, adaptively, and cap on wall-clock.**

- **Poll the workflow RUN liveness, not the missing check-run.** The ci.yml *run* object
  for the SHA exists at trigger time (`status=queued`) even while the `test` check-run does
  not. Keep waiting while `run.status != "completed"` — a **blocklist** over the full
  run-status enum (`queued|in_progress|waiting|requested|pending`), never an allowlist of
  two states (which dead-ends on `waiting`/`requested`/`pending`).
- **Key the in-bash ceiling on `elapsed >= CEILING_S` (wall-clock), not `attempt` count.**
  Since the loop computes `elapsed=$(( $(date +%s) - start_epoch ))` each iteration, the
  diagnostic fires on real time regardless of how API latency stretches each iteration.
  Size `timeout-minutes` with ≥20% headroom over `CEILING_S` (here 3600s vs 3000s).
- **Fail-OPEN invariant:** only the `test` check-run `conclusion == "success"` may authorize
  `exit 0`. The ci.yml RUN `.conclusion` is **liveness-only** — never an `exit 0` authorizer
  (a `run.conclusion==success` shortcut fails-OPEN on a mis-selected run or a green run whose
  `test` aggregation was non-success).
- **Bounded reconciliation grace** absorbs run-completed→check-run eventual-consistency lag:
  re-poll a small `RECONCILE_ATTEMPTS` as ordinary loop iterations, proceeding ONLY on a
  re-observed `test=success`, never an unbounded inner loop.
- **Gate `migrate` on `await-ci` with a leading `always() &&`** so migrations apply only for
  a CI-green SHA; without `always()` a `workflow_dispatch`-skipped `await-ci` auto-skips
  migrate (a skipped `needs` skips the job before `if` evaluates) and ships new code on an
  un-migrated schema.

## Key Insight

For any **fail-closed polling CI gate**: (a) wait on the most-upstream object that exists
early (the workflow *run*), not a derived artifact created late (a synthetic aggregator's
check-run); and (b) make the in-bash timeout ceiling **wall-clock-based**, because an
attempt-count ceiling silently under-budgets per-iteration API latency and lets the harness
hard-kill fire first — reproducing the very silent-skip the gate was built to prevent. The
diagnostic `::error::` only helps if it is *guaranteed* to fire before the job is killed.

## Session Errors

- **Planning subagent hit the Anthropic account usage limit and produced no artifacts.**
  Recovery: confirmed the reset window had passed, re-spawned the planning subagent (clean).
  Prevention: on a `task-notification` whose `result` is a usage-limit message, check the
  reset time vs. now before assuming logic failure — re-spawn after reset rather than
  flailing or aborting the pipeline.
- **`gh issue create` denied for a missing `--milestone`.** Recovery: re-ran with
  `--milestone "Post-MVP / Later"`. Prevention: already covered — default operational
  follow-up issues to that milestone; write the body via the Write tool first (done here),
  never heredoc it into the same denied command.
- **`actionlint` SC2016 fired on the `printf` format string's backticks, not the `jq` line.**
  The Slack mrkdwn code-span backticks in a single-quoted `printf` format trip SC2016
  ("expressions don't expand in single quotes"). Recovery: the `# shellcheck disable=SC2016`
  must precede the `MESSAGE=$(printf '...`...`...')` line, not (only) the `jq -n '{...$x...}'`
  line. Prevention: when a single-quoted shell string carries backticks OR `$var`, put the
  disable on *that* line; SC2016's reported `line:col` points at the real offender.
- **A review agent transiently rate-limited mid-run.** Recovery: proceeded with 4/5
  substantive agents per the Rate-Limit Fallback gate. Prevention: the gate already permits
  partial coverage when ANY agent returns substantive output.
- **Verification grep captured `0` from `P0`** in a comment, breaking a verification-script
  arithmetic (not the workflow). Prevention: anchor extraction greps to the literal
  (`MAX_ATTEMPTS: "[0-9]+"`), not a bare `[0-9]+` over a whole comment-bearing line.
