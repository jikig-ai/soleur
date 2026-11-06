---
title: "a draft PR's skipped shard legs fail the `test` aggregate by design (`draft: full battery owed at ready`) — and a skill-body ceiling raise only passes as its own PR"
date: 2026-11-03
category: workflow-issues
tags: [draft-pr, ci-ratchets, skill-body-budget, pr-workflow]
synced_to: [soleur:ship]
---

# Learning

## Problem

A budget-only PR (#11965, ship ceiling 273955→276000 in
`plugins/soleur/test/skill-body-budget.json`) came back with a red `test`
check — failed at "Aggregate shard results" in ~2 seconds, before any shard
leg could have run. Two independent mechanics collided, and both look like a
broken pipeline if you don't know them.

## Root cause (two mechanisms)

**1. Ceiling raises must ship alone.** `scripts/lint-skill-body-budget.py`
lets a ceiling rise only in a diff whose *entire* changed-file set is the
ceiling file itself (`raise_only_diff`). A raise riding with the growth it
licenses is exactly what the ratchet exists to stop, so the error text
prescribes: "Land the raise as its own PR with no other file in it." (The
mechanism replaced an earlier prose remedy — "raising one is a separate PR" —
that compared the separate PR against the same base and reddened identically;
the only paths through were admin bypass or editing the lint. A gate whose
documented remedy cannot pass trains bypass.)

**2. Draft PRs are expected-red on `test`.** The draft-light cost lever runs
a reduced battery on `pull_request` events for draft PRs: heavy shard legs
are skipped, the skips set `fail=1`, and the aggregate then exits 1
unconditionally with `draft: full battery owed at ready`
(`.github/workflows/ci.yml` ~:2277). The `ready_for_review` run is never
light — so the *correct* sequence for a budget-only PR is: open → verify the
non-shard gates → **mark ready → the full battery runs and `test` goes
green**. Re-running the draft's `test` job just re-fails it the same way.

## Rule

- Raising any `skill-body-budget.json` ceiling: isolate it — the PR diff may
  touch ONLY that file, plus the PR-body/label ceremony. Any second file and
  the lint refuses, no matter how small the raise.
- Judging a draft PR's `test` check: expect red. `SKIPPED` shard legs +
  `draft: full battery owed at ready` is the design, not a flake — do not
  burn a rerun; mark the PR ready (or push a `ready_for_review` transition)
  and evaluate the full battery instead.
- Symmetric trap in the other direction: a green draft `test` check would
  mean the battery never ran — option R exists precisely so a "tolerate
  skipped" edit cannot turn a draft green.

## Session Errors

- **Budget-only PR #11965's `test` aggregate failed at ~2s and looked like
  infra breakage** — Recovery: identified the draft-light contract; the
  ready_for_review run runs the full battery. Prevention: on any draft PR,
  read `test` failures through the draft-light lens first — a seconds-fast
  aggregate failure with SKIPPED legs is the owed-battery signal, and the fix
  is `gh pr ready`, never a rerun.

## Evidence

PR #11965 (budget-only ceiling raise, this session); `ci.yml` draft-light
aggregate (:2270-2281, option R per ADR-276 S3 / #9728);
`lint-skill-body-budget.py` `raise_only_diff` arm (:186-212);
`scripts/ci-draft-light.test.sh` pins the contract end-to-end.

## Tags

category: workflow-issues
module: ci-pr-workflow
