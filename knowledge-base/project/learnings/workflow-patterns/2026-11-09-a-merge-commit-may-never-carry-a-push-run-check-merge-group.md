---
title: A merged PR's merge commit may never carry a push run — merge_group is the queue's evidence
date: 2026-11-09
category: ci-cd
tags: [workflow-patterns, merge-queue, soak-probe, followthrough]
issue: '#12478'
---

# Learning: merge_commit_sha does not imply a `push` ci.yml run — check `merge_group`

## Problem

The #9323 soak probe's escape arm looked for the ci.yml `push` run on each merged
PR's `merge_commit_sha`. It pended forever (NOT YET, exit 2) because three recent
PRs (#12445, #12376, #12330) landed via the **merge queue**: queue-merged merge
commits carry `merge_group` workflow runs and **never** a `push`-event run. The
pending bucket was an absorbing state — identical shape to the open-PR
convergence defect #12360 fixed.

## Diagnosis signature

`gh api "repos/<repo>/actions/workflows/ci.yml/runs?event=push&head_sha=<full-40-char-sha>"`
returns `workflow_runs:[]` while `event=merge_group` returns a completed run on
the same sha. Caution: `head_sha` needs the **full 40-char sha** — abbreviated
10-char prefixes return `No commit found` / empty results.

## Fix pattern

1. Fallback ordering: conclusive push arm → classify; inconclusive/absent →
   exactly one `event=merge_group&head_sha=$sha` read → **same** classifier
   (parameterize on event name — never duplicate the gated `test-scripts*`
   enumeration; two copies drift).
2. Provenance: an `ok` sourced from merge_group is a distinct row detail
   (`ok via_mg`) counted on a note line — never silently folded into `ok`.
3. API-budget model: bump the worst-case bound by +1 read/qualifying PR
   (3→4 * MAX_RUNS); the fallback fires only on the inconclusive arm but at
   queue-merge volume that IS the typical arm.
4. ADR-276 already names `merge_group` the full-battery authority — queue runs
   ran the complete battery on the exact sha that landed; a red gated mg job is
   equivalent escape evidence.

## Residuals (recorded, safe direction)

- Grouped merge-queue batches: mid-batch members' `merge_commit_sha` ≠ the
  group's `head_sha` → mg read returns empty → `pending` (NOT YET, retried;
  never a false-PASS).
- Dual-evidence ordering: a conclusive push run suppresses the mg read
  entirely — push-first by ruling; the premise (queue merges carry zero push
  runs) is measured, not guaranteed.

## Proof

PR #12483 (85/85 fixture assertions + live `PBG_UNBOUNDED=1` verdict: PASS,
2 verified via merge_group, 1 unrelated red mg run on non-gated
`lint-bot-statuses`, 0 escapes).
