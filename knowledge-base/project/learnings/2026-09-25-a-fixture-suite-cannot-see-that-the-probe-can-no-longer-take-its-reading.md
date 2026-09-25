---
title: A fixture suite cannot see that a follow-through probe can no longer take its reading
date: 2026-09-25
category: integration-issues
module: scripts/followthroughs
tags: [follow-through, soak, inngest, sweeper, dry-run, 6178]
issue: 6178
pr: 8835
---

# Learning: a fixture suite cannot see that a follow-through probe can no longer take its reading

## Problem

#6178's soak probe closed NOT CLEAN on three groups. The groups were attributed read-only: host
run index == `routine_runs.run_id` == Better Stack manual-trigger events. Two are manual-trigger
groups and one is a catch-up after a no-scheduler window. The fix was data: pin each group as an
exact run-id set. The suite went 117 → 144 green.

The plan's evidence item E2 then dispatched the real sweeper against the branch
(`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`). It read
**CANNOT ESTABLISH**: host slice 1 (11 ids, `total_count=1023`) failed with
`FATAL empty/truncated runs response on page 8 (last_curl_exit=28)` on three consecutive GETs. That
was deterministic at about 34 s. `main`'s probe was just as blind. The pins would have merged green
and the sweeper would still never have read clean.

## Solution

1. Split the failing slice to measure it. The minter alone was 713 runs, 8 pages, 19 s, HTTP 200.
   The other ten ids were 310 runs in 4 s, HTTP 200. Only the combined 11-page slice failed.
2. Re-dealt the population with `SLICE_MAX` 11 → 8 (7 slices). The harness now uses
   `SLICES=7`, the stub uses `% 7` and a cap of 8, and a literal pin reds on drift.
3. Re-ran the probe live (read-only): rc=5 SOAK CLEAN, 2312 runs, explained=5, UNEXPLAINED=0.
4. Recorded the horizon. Slice 1 is almost all the `*/20` minter (~72 runs/day), and round-robin
   cannot thin it further. At that rate it passes 1023 again around 2026-09-28. The date is in the
   probe header, the population-file header and ADR-100.

## Key Insight

A follow-through probe's fixture suite certifies its **logic**. It cannot certify that the
**host can still answer** the query at today's data volume, because the volume grows every day the
window stays open-topped. The only instrument that measures reading-feasibility is the real sweeper
dry run against the branch, and it is cheap: read-only, one dispatch, no comment posted. Run it
before calling a follow-through PR done. When it fails, measure the halves of the failing slice
before changing anything.

## Session Errors

1. **E2 found the reading untakeable. The plan had assumed the 5-slice design still fit.**
   Recovery: split-measure, re-deal to 7 slices, re-run live. **Prevention:** a bullet routed into the follow-through
   convention runbook in this PR: dry-run the sweeper on the branch for any follow-through probe PR.
2. **The first E1 sandbox run (suite on the tree merged with #8626) read 38/106.** The probe
   resolves `REPO_ROOT` from its own path, so a copied file lost the population file. Recovery:
   ran in a detached scratch worktree. **Prevention:** existing rule. Sandbox a repo-relative
   script as a git worktree, never as a copied file.
3. **Committed while the affected gate was running.** The gate was invalidated (rc 143) and had to
   be relaunched on the clean HEAD. **Prevention:** existing rule (do not edit under a running
   gate). This was a one-off lapse, and the rule already covers it.
4. **Mutant M4 was garbled by `sed`-in-python escaping (114 failures).** Recovery: re-ran it as a
   clean semantic mutant (9 failures, all attributable). **Prevention:** existing rule. A mutant
   whose failure count is wildly out of line is an instrument failure, not a kill.
5. **A markdownlint MD012 error was committed, and the first fix targeted the wrong location.**
   Recovery: trimmed the trailing blank lines at EOF. **Prevention:** run markdownlint on each
   changed `.md` before `git add`, not after.
6. **`git add` of a `.log` evidence file failed (it is gitignored).** Recovery: kept the RED log in
   `/var/tmp` and quoted it in the PR. **Prevention:** keep evidence out of the tree.
7. **The git-history review seat asserted #8626 does not touch the soak files, which is false.**
   Recovery: the E1 merge check had already measured it. **Prevention:** reconcile a seat's
   factual claims against a measured artifact before relaying them.
8. **`--print-affected-set` exceeded the 120 s tool timeout.** Recovery: backgrounded it.
   **Prevention:** run it detached.
9. **A naive per-row bucketing of the raw host response showed 5 spurious ">1" buckets.** They
   were one run id listed twice with different startedAt, which the probe's `unique_by(.id)`
   collapses. Recovery: dedupe by id before reading. **Prevention:** mirror the probe's own
   bucketing (dedupe by id first) when re-deriving its groups by hand.

## Tags

category: integration-issues
module: scripts/followthroughs
