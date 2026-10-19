---
title: "A sibling session shipped the same fix while I planned, and review found it three hours later"
date: 2026-10-13
category: workflow-patterns
tags: [one-shot, collision-gate, duplicate-work, review-panel, design-docs, supersede-marker]
issue: 8211
pr: 10153
---

# Learning: a sibling session shipped the same fix while I planned, and review found it three hours later

## Problem

A resume brief for the git-data LUKS cutover named four deliverables, one of them a code fix for #10137. The pipeline's Step 0a.5 collision check ran correctly at the start and found no sibling PR. A second session had, in the same hours, opened PR #10155 for the same issue (19:08Z), taken it through an 11-seat review and merged it (22:04Z). This branch built its own copy of the fix (a rotate-aware post-apply gate, 24 assertions), pushed it, and only learned of the duplicate when the history seat of the review panel ran `gh pr view` on the PR that touched the same three files. By then the duplicate had cost a plan, a work phase, two commits and most of a review round, and the branch had to revert its own code and keep only the documents.

## Solution

Reverted the three code files to `origin/main` (commit `fa58f3388e`, the implementation stays in history at `d2a1d0e766`), re-pointed every document that cited the reverted gate to the merged function, recorded the decision as a plan-default row in `decision-challenges.md`, and removed `Closes #10137`/`#10067` from the PR. The review notes that still applied went to the owner issue instead (#10166). The review itself paid for the detour: the merged sibling implementation had already hardened what this branch's panel then found (type-and-name volume matching, a single mode source, mode-aware operator text).

## Key Insight

The post-planning re-probe is not optional bookkeeping, and "the gate cleared the issue at the start" says nothing about the next three hours. `one-shot` already prescribes re-running the collision probes against every ref after planning returns and before `soleur:work` begins; this run skipped it because the plan subagent returned a plan that looked self-consistent and the work phase felt like the continuation of a cleared step. The cheapest form of the check costs one command per ref (`gh pr list --search "<N> in:body" --state all` plus a file-anchor probe over the planned files), and it is worth repeating right before review for any pipeline that has run longer than about an hour, because duplicate-work arrives as an ordinary green PR, never as an error.

Two smaller measurements from the same session:

- **A supersede marker inserted mid-paragraph is a lazy blockquote continuation.** Putting a `> **Superseded ...**` line in the middle of a paragraph with no blank line after it pulls the rest of the paragraph into the blockquote, so live text renders under a "Superseded" banner. markdownlint does not catch it. Insert markers after the paragraph and leave a blank line.
- **Design documents attract review rounds without a natural stopping point.** Three rounds on a 700-line wipe design each found a fresh batch of internal contradictions introduced by the previous round's fixes (a count of `secrets.DOPPLER_TOKEN` sites, a scrub-set stated three ways). The stop that worked was an explicit "Open items for the build PR" list, because the build PR is where those claims get tested against code, and capping fix rounds at two plus one verification pass.

## Session Errors

1. **Skipped the post-planning collision re-probe** — Recovery: reverted the duplicate code, kept documents only — Prevention: run the re-probe the skill already prescribes after planning returns, and again before review on a long pipeline; no new rule is needed, the instruction exists.
2. **technical-ruling-gate failed on a class label `technical (legal)`** — Recovery: normalized to `technical` after the gate named the row — Prevention: use the closed class vocabulary when a subagent writes `decision-challenges.md`; the gate catches it.
3. **Supersede marker inserted mid-paragraph in the K1 addendum** — Recovery: added a blank line after the marker (found by the verification seat, not by markdownlint) — Prevention: see Key Insight; place markers after the paragraph.
4. **Local affected-test gate queued behind sibling runs for 40+ minutes** — Recovery: killed the queued runs (own worktree only) once the code was reverted and relied on CI, whose merge gate is authoritative — Prevention: none needed; the queue is the documented contention behavior and the heartbeat says so.
5. **The plan inherited an unmeasured premise** ("the steps after the assert have never run to completion on the rotate path") — Recovery: the live precondition read measured the opposite (poll, pin-load and summary succeeded in run 38140050880) and the plan was corrected by an appended reconciliation — Prevention: a plan premise about what a CI run did is a claim to read from the run's job list before it is written down.
6. **Design-doc fix rounds introduced new internal contradictions** — Recovery: capped at two rounds plus one verification pass and listed the remainder as build-PR open items — Prevention: see Key Insight.

## Tags

category: workflow-patterns
module: one-shot pipeline, git-data cutover documents
