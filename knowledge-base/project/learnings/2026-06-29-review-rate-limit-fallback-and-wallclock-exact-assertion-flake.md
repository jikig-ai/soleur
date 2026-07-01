---
title: Review-agent session-limit empties need inline fallback + rerun; exact-equality on a wall-clock-derived value is flaky
date: 2026-06-29
category: workflow-patterns
module: review, test-design, ci-deploy
tags: [code-review, rate-limit, subagent, test-flake, wall-clock, assertion, one-shot]
issue: 5669
pr: 5686
---

# Learning: two review-phase traps — session-limit empties and exact-equality on a timing-derived value

Captured from the `/soleur:go 5669` one-shot (graceful cron drain before container swap, ADR-076).

## Problem

Two distinct traps surfaced during the review phase:

1. **Review subagents hit the Anthropic session API limit mid-batch and returned empty.** Of 5 spawned review agents, 4 came back with only `You've hit your session limit · resets 5:20pm` and a ~70-token body — no findings. Treating an empty/limit result as "this dimension is clean" would have shipped the change with security, architecture, pattern, and test-design **unreviewed**, while looking green.

2. **Applying a test reviewer's "tighten the assertion" suggestion verbatim introduced a timing-flaky test.** `test-design-reviewer` (correctly, in spirit) flagged that T3's no-cron fast-path assertion `[[ "$T3_WAIT" =~ ^[0-9]+$ ]]` was weak and suggested pinning it to `== 0`. Applied literally, the very next suite run failed: `FAIL: T3 (rc=0 timed_out=false wait=1)`. The drained wait is `$(date +%s) - drain_start`; a single `docker exec … pgrep` probe can cross a 1-second boundary, so the no-cron path legitimately records **0 *or* 1**.

## Root cause

1. A subagent that dies on a terminal rate-limit returns a *successful-looking* tool result whose text is the limit notice, not an error the orchestrator auto-detects. "Agent completed" ≠ "agent reviewed."

2. The reviewer's suggestion conflated two properties. The original `^[0-9]+$` **already** excluded the never-reached `-1` sentinel (no minus sign matches), which was the reviewer's actual concern. Pinning to `== 0` added nothing on the sentinel axis and instead asserted an exact value on a wall-clock-derived quantity with ±1s natural variance — converting a sound test into a flaky one.

## Solution

1. **Inline fallback + rerun, never trust the empty.** Per the review skill's Rate-Limit Fallback gate: when agents return empty/limit output, (a) perform the uncovered-dimension review **inline in the main context** using deterministic gates (shellcheck, semgrep, anti-slop) plus first-principles analysis, and (b) **re-spawn the limited-out agents** once the window resets, then reconcile. Here the rerun surfaced two real findings the inline pass had under-weighted (a symlink-follow-as-root truncation; an un-guarded `4200↔4800` wall-clock cross-group link).

2. **Bound timing-derived assertions; don't pin them.** Keep the sentinel-excluding regex and add a small upper bound that pins the fast path without asserting an exact tick:
   ```bash
   # ^[0-9]+$ already excludes the -1 sentinel (no minus); -le 2 pins the
   # no-cron FAST path and excludes any real multi-second drain — without a
   # brittle exact 0 (a single docker-exec probe can cross a 1s boundary).
   if [[ "$T3_WAIT" =~ ^[0-9]+$ && "$T3_WAIT" -le 2 ]]; then ...
   ```

## Key insight

- **An empty review-agent result is an *absence of review*, not a clean bill.** Reconcile the spawned-agent set against the returned-with-findings set; rerun the gap.
- **When a reviewer says "tighten an assertion," check what variance the asserted value actually has before applying it.** An exact-equality on a wall-clock / counter / measured-size value is a flake generator; bound it (`-le N`, `expect.poll`) instead. The reviewer's underlying concern (exclude the failure sentinel) was already met by the regex — verify the suggestion adds discrimination, not just strictness.

## Session Errors

- **4/5 review agents returned session-limit empties** — Recovery: inline fallback for uncovered dimensions + re-ran the agents after the limit reset; the rerun found 2 real findings. — Prevention: review skill's Rate-Limit Fallback gate (already exists); reinforced here. Reconcile spawned-vs-returned every batch.
- **`== 0` on a wall-clock-derived wait flaked the suite (`wait=1`)** — Recovery: reverted to `^[0-9]+$ && -le 2`. — Prevention: never assert exact-equality on a timing/counter/measured value; bound it.
- **`set -euo pipefail` SIGPIPE aborted a `grep | head` test section** — Recovery: wrapped the section in `set +e +o pipefail` … restore. — Prevention: known bash trap; one-off here.
- **awk source-order assertion exited early on a literal inside a top-of-file comment** — Recovery: added an `f &&` start-anchor guard so the exit rule only fires inside the target block. — Prevention: anchor source-order awk scans to the block, not the whole file.
- **`reportSilentFallback` called with the wrong arg shape** — Recovery: fixed to `(null, {feature, op, message})`. — Prevention: one-off.
- **2 pre-existing doppler env-only ci-deploy.test.sh failures** — Recovery: confirmed on `origin/main`, carried as `pre-existing-unrelated`. — Prevention: env-only (real `doppler` on PATH on this dev box); pass in clean CI.

## Tags
category: workflow-patterns
module: review
