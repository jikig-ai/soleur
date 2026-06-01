---
title: "Classifying a claude-eval cron as always-create-producer vs best-effort must read the ENTIRE prompt, including the no-op / heartbeat branch"
date: 2026-06-01
category: best-practices
tags: [cron, inngest, observability, sentry, heartbeat, plan-classification, multi-agent-review]
related_prs: [4732, 4727, 4714]
related_issues: [4730]
related_learnings:
  - knowledge-base/project/learnings/bug-fixes/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md
---

# Cron producer-classification must read the full prompt, not just the primary issue-create branch

## Problem

Issue #4730 asked to decouple 8 Inngest `claude-eval` cron heartbeats from the
`claude --print` spawn exit code, applying one of two established patterns
**per cron**:

- **Pattern A (best-effort):** non-zero exit is NORMAL → heartbeat `ok:true` +
  non-paging `warnSilentFallback`. (Mirrors `cron-bug-fixer.ts`, PR #4727.)
- **Pattern B (always-create producer):** the cron files a `[Scheduled] …`
  issue every run → a clean exit with no artifact must turn the monitor RED via
  `resolveOutputAwareOk` + a replay-stable `runStartedAt`. (Mirrors the 3
  producers wired by PR #4714.)

The whole point of #4730 is that this is a per-cron *decision*, not a sweep —
and the dangerous failure mode is misclassifying a producer as best-effort,
which false-greens the exact silent-no-op the output-aware path exists to catch.

The plan (and `/work`) classified `cron-campaign-calendar` as **Pattern A**,
reasoning "the prompt files issues only per-overdue-item, so a zero-overdue run
legitimately creates nothing." That read the prompt's STEP 2 (per-overdue
issue) but **missed STEP 2.5**:

```
STEP 2.5 — Heartbeat audit issue (runs when NEW == 0):
If no new issues were created, create and immediately close a heartbeat audit
issue ...  Title: "[Scheduled] Campaign Calendar - <today> (heartbeat)"
          Label: scheduled-campaign-calendar
```

So the cron actually files a `scheduled-campaign-calendar`-labelled artifact on
EVERY run (per-overdue issue when NEW>0, heartbeat issue when NEW==0). It is an
always-create producer → **Pattern B**. The plan classified it on the
*conditional* branch and never read the *unconditional fallback* branch.

## Solution

Multi-agent review (`security-sentinel` + `architecture-strategist`,
independent concurrence) both flagged the misclassification with `STEP 2.5` as
the cited evidence. The finding was `pr-introduced` (this PR makes the
classification call) → fixed inline: reclassified campaign-calendar to Pattern B
(thread `runStartedAt`, call `resolveOutputAwareOk`, drop the
`warnSilentFallback` import), moved it from `BEST_EFFORT_CRONS` to
`WIRED_PRODUCERS` in `cron-producer-output-wiring.test.ts`, and added a test
guarding the STEP 2.5 prompt invariant the classification now depends on. Final
split: 5 Pattern-B + 3 Pattern-A.

## Key Insight

When classifying a claude-eval cron (or any agent-driven producer) as
**always-create vs best-effort**, the determining question is *"does a labelled
artifact land in the run window on EVERY path through the prompt?"* — which
requires reading the prompt to its terminal/no-op branch, not stopping at the
primary create branch. Prompts commonly add a "if nothing to do, file a
heartbeat/no-op issue so the watchdog sees activity" fallback (STEP 2.5 here),
which flips a seemingly-conditional cron into an unconditional producer. The
`verifyScheduledIssueCreated` helper counts both creates AND comment-bumps
(filters on `updated_at`), so a dedup-comment path also satisfies the producer
contract.

Cheapest gate at plan/classification time: grep the prompt constant for the
`SENTRY_MONITOR_SLUG` label and confirm whether ANY branch creates/comments an
issue with that label unconditionally — `grep -n "<slug>\|heartbeat\|If no\|NEW == 0\|create.*issue"`.

## Session Errors

1. **CWD-drift on first RED test run** — ran `vitest` from the bare-repo mirror
   path (`/soleur/apps/web-platform`) instead of the worktree; the
   producer-wiring test reported the stale pre-edit 4-test count, masking the
   real RED state. **Recovery:** re-ran from
   `<worktree>/apps/web-platform`. **Prevention:** always
   `cd <worktree-abs>/apps/web-platform && ./node_modules/.bin/vitest …` in a
   single Bash call; the Bash tool does not persist CWD and the bare root holds
   stale synced copies (existing rule: "chain `cd <worktree-abs> && <cmd>`").
2. **Edit-before-Read rejections (×6)** — inspected 6 cron sources via Bash
   (`sed`/`grep`) then attempted Edit; the harness requires a Read-tool read
   first, so the edits failed "File has not been read yet." **Recovery:** Read
   each edit region, then re-applied. **Prevention:** a Bash `sed`/`grep`
   inspection does NOT satisfy the Read-before-Edit gate — Read (the tool) every
   file before editing it.
3. **`set -uo pipefail` aborted the review classification script** — the host
   shell snapshot references `ZSH_VERSION` unbound, so `set -u` exited 127
   mid-script. **Recovery:** classified the diff manually (obvious: 8 `.ts`
   sources → `code` class). **Prevention:** the review SKILL already says drop
   the `e` from `set -euo`; also avoid `-u` in classification bash run against
   the host snapshot.
4. **2 `signature-verify*.test.ts` failed in the 60-file inngest batch** —
   slow (~15s) env-mutating tests that flake under parallel batching; pass
   standalone (6/6) and passed in the 634-file full run. **Recovery:** confirmed
   pre-existing flake, not a regression (touch no code this PR changed).
   **Prevention:** matches the documented env-leak/cold-start flake class; re-run
   suspect files in isolation before treating a batch failure as a regression.
5. *(forwarded from session-state.md)* Task-based parallel research/review
   agents unavailable in the planning-subagent environment. **Recovery:** ran
   research/precedent-diff inline (skills permit this). No action.

## Prevention

- At plan time, classification of a producer-vs-best-effort cron MUST cite the
  prompt branch that proves the contract — and read to the terminal/no-op branch
  before concluding "files nothing on a clean run."
- The `cron-producer-output-wiring.test.ts` `WIRED_PRODUCERS` / `BEST_EFFORT_CRONS`
  split is the durable guard; add a per-cron prompt-invariant test (e.g. assert
  `STEP 2.5` is present) when a classification depends on a specific prompt
  branch, so a future prompt edit that removes the unconditional path trips a test.
