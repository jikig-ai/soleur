---
title: "A mutation anchor can match inside your own comment, and a contended box can masquerade as five failing guards"
date: 2026-09-23
category: test-failures
tags: [mutation-testing, anchors, ci-paths, shard-assignment]
issue: 8006
pr: 8585
related:
  - knowledge-base/project/learnings/2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md
---

# A mutation anchor can match inside your own comment, and a contended box can masquerade as five failing guards

## Problem

`feat-ci-test-shard-speedup` (PR #8585) extended the shard-totality mutation battery with
rows anchoring on `if want_scripts_heavy; then`. The anchor string also appeared inside a
nearby comment quoting the guard's regex — the battery's occurrence-count check read 2
matches where the author meant 1, and a second row anchored on prose that existed in the
*light* job but not the heavy one. Both rows red-lit in CI only.

## Solution

Extend anchors to multi-line blocks that include the target's first comment line, and grep
the SUT for the anchor's occurrence count *as the matcher counts it* — comments and
documentation quoting the pattern are matches too. Verify the anchor before committing the
row, not after CI reports it missing.

## Key Insight

An anchor's uniqueness is a property of the file's *entire* byte content — including your
own comments about the anchor — not of the code region you were looking at. In the same
session a foreign full-battery in a sibling worktree made a control invocation report five
red rows that a quiet box later proved green: under heavy contention, distrust guard
verdicts that smell like timeouts before distrusting the guard.

## Tags
category: test-failures
module: ci/test-all-sharding
