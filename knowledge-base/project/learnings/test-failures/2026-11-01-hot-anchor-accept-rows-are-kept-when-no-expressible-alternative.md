---
title: "drain-rubric hot-file test measures the anchor host, not the accepted path — and repair-PR accept rows stand when every alternative is mechanism-false"
date: 2026-11-01
category: test-failures
tags: [ci-pr-affected, accept-rows, drain-rubric, cto-ruling]
---

# Learning

## Problem

A plan asserted "no accept row anchors on a >8-commits/90d hot file" — a checked
fact that was false (the two `betterstack-emitter-read` rows anchor on
`lint-betterstack-emitter-read.sh:133`, at 13 commits/90d; the ADR-068 accepted
*path* itself is at 17). The drain rubric's hot-file hold (`held-hot` in
PR4b/PR4c) was quoted without resolving which file it measures, leaving a
review fork: keep the rows, convert to declared edges, or hold the PR.

## Solution

Ruled by CTO agent (PR #11814, 2026-11-01), now recorded in
`specs/feat-one-shot-11796-ratchet-pairs/decision-challenges.md` R7 and the
plan's edge-cost section:

1. The rubric's hot-file test is evaluated on **the file holding the mention
   line** (the accept row's anchor host), per the runbook's own parenthetical
   at `ci-pr-affected-activation.md` › the >8-commits/90d limit — not on the
   accepted path. A path-hot reading contradicts both that text and PR4c's
   `commits_90d_F` column.
2. The hold's remedy — withhold a not-yet-declared edge — has no analogue for
   a repair PR covering a *pre-existing* read: nothing can be withheld, and
   baselining is mechanically barred (`--print-baseline` is prune-only).
3. Converting the row to a declared edge is affirmatively mechanism-false
   (ALLOW-table data consumed as `ALLOW[$rel]`/`${!ALLOW[@]}` lookup strings
   is not a read loop) and, for a hot doc path, self-defeating — declaring an
   ADR at 17 commits/90d manufactures the spurious-selection cost the limit
   exists to prevent.
4. A stale anchor on a hot host is the ratchet's designed fail-safe: it flags
   the editing PR for re-triage and never silently misses.

Narrow precedent only: pre-existing read + conversion mechanism-false +
identical same-day disposition (#11734 accepted an emitter-read row on the
same file at 13/90d). It is NOT a general hot-host exemption.

## Key Insight

When a rubric's limit and the mechanism's truth table collide, the limit loses
— you cannot cure a limit breach by committing a declare-rule breach. Verify
commit-count claims per-path before writing "no hot file" into a plan: the
plan's table was wrong on nearly every row and concealed the very question
the review existed to answer.

## Evidence

- Session: one-shot on #11796 (PR #11814), 2026-11-01. git-history seat P2;
  post-review CTO spawn ruled keep-all-seven; fix-round seat verified the
  corrected table against live `git log --since=90.days` counts.
- Sibling precedent: `accept.tsv` › the #11734 `betterstack-emitter-read`
  rows anchored on the same 13-commits/90d host file.
