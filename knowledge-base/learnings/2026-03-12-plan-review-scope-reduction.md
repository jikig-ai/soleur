---
problem_type: workflow-patterns
module: plan-review
severity: medium
first_seen: 2026-03-12
last_seen: 2026-03-12
occurrences: 1
slug: plan-review-scope-reduction
---

# Learning: Plan review as scope reduction tool

## Problem

A knowledge-base restructuring plan grew from a ~12-file domain move to a 200+-file migration by bundling three independent concerns: domain moves, `features/` grouping (specs/plans/brainstorms/learnings), and `overview/` → `project/` rename. The `features/` grouping alone accounted for ~1,194 path references across hundreds of files and touched the most fragile infrastructure (archiving scripts, compound-capture, worktree-manager).

## Solution

Running `/soleur:plan-review` with three specialized reviewers (DHH, Kieran, code-simplicity) identified the overengineering unanimously. All three recommended cutting the `features/` grouping. Two recommended keeping `overview/` as-is. The scope was reduced to ~12 git mv operations and ~37 file updates — an 80% reduction.

The deferred work was tracked as separate GitHub issues (#568, #569) with smaller blast radius.

## Key Insight

Plan review is most valuable as a **scope reduction tool**, not just a quality check. When a refactoring plan bundles multiple independent changes, reviewers can identify which changes carry disproportionate risk relative to their value. The "thin router over migration" principle applies: solve the stated problem with minimum moves, then evaluate whether further restructuring is worth its churn cost separately.

## Tags

category: workflow-patterns
module: plan-review
