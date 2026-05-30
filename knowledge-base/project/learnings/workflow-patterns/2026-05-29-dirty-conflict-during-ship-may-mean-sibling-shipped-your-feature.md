---
date: 2026-05-29
category: workflow-patterns
tags: [one-shot, ship, merge-conflict, collision, sibling-pr, reset-and-rebuild]
related_pr: 4641
related_to: [4638]
---

# A DIRTY conflict during ship can mean a sibling PR shipped your whole feature

## Problem

During a `/soleur:one-shot` run for the workspace-invite-acceptance bug, the
branch passed every gate (review, full suite, preflight) and queued auto-merge.
The PR then flipped `OPEN BEHIND → OPEN DIRTY`. The DIRTY was not a stray
line conflict: a sibling PR (**#4638**, ostensibly an OTP-rate-limit fix) had
merged to `main` mid-pipeline and implemented the **same feature** — invite
return-target threading through the auth funnel — with a *different* param
convention (`redirectTo` vs my `return_to`), a different `safeReturnTo` shape
(string|null + percent-decode vs my widened-fallback), and the *opposite*
T&C-timing decision. Six files conflicted, each a competing implementation.

## Root cause

The one-shot collision gate (Step 0a.5) only probes for open/merged PRs that
reference the SAME issue at pipeline START. It cannot catch a sibling PR that
(a) targets a different issue but (b) incidentally implements the same feature,
and (c) merges DURING the 30–90-min pipeline window. The auth surface is
high-collision; #4633, #4638, #4639 all merged into `app/(auth)` during this
single session.

## Solution

On a DIRTY conflict during ship, do NOT reflexively resolve conflicts to
"mine." Instead:

1. `git merge --abort` (get back to a clean tree).
2. Read `origin/main`'s ACTUAL implementation of the conflicting files —
   `git show origin/main:<file>` — not just the `<<<<<<<` markers. Ask: "did a
   sibling PR already implement this feature?"
3. If main now supersedes the feature: trace main's implementation end-to-end
   against the original bug to find what (if anything) it still misses. (#4638
   fixed the existing-user case but deliberately dropped the target for a
   keyless brand-new invitee — the exact reported case.)
4. Surface the collision + the residual gap to the operator and get a design
   decision (the competing approaches had a legal/T&C-timing tradeoff that was
   not mine to resolve autonomously).
5. `git reset --hard origin/main` (salvage planning artifacts to /tmp first —
   the plan/spec live only on the feature branch) and rebuild ONLY the residual
   delta on top of the sibling's shipped design. The final PR became a 2-file
   surgical change instead of a 6-file competing rewrite.

## Key Insight

A DIRTY/CONFLICTING merge state where MANY files conflict and the conflicts are
whole-function competing implementations (not line tweaks) is a signal that a
sibling shipped your feature — treat it as a "is my PR still needed?" decision,
not a "resolve the conflict" task. Force-resolving to "mine" would have shipped
a second, conflicting param convention and overridden a deliberate shipped
design. Reset-and-rebuild-the-delta is the correct recovery when main
supersedes; it also keeps the diff small enough for a fast focused re-review.

## Session Errors

1. **Sibling PR #4638 shipped the same feature mid-one-shot → 6-file DIRTY
   conflict at merge.** — Recovery: abort merge, inspect main's real impl, reset
   to main, rebuild only the residual keyless-funnel delta. — Prevention: this
   learning; on DIRTY during ship, diff origin/main against the feature surface
   and check for supersession before resolving.
2. **Queued `gh pr merge --auto` while the PR was still a draft** (skipped
   `gh pr ready`). — Recovery: marked ready, re-queued. — Prevention: ship
   Phase 6 marks ready before queueing; follow phase order, don't queue merge
   from the preflight step.
