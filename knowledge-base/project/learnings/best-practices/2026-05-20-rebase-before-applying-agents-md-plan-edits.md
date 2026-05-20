---
module: workflow / plan / work skills
date: 2026-05-20
problem_type: integration_issue
component: skill_workflow
symptoms:
  - "Plan's B_ALWAYS budget baseline (24499) was stale at /work time (actual 23936, then 21849 after rebase)"
  - "Sibling PR #4123 trimmed L15 + L55 of AGENTS.core.md while my work was in flight"
  - "Applied plan-prescribed trims duplicated #4123's work; lefthook still rejected commit; required reassessment + rebase + reapply"
root_cause: stale_precondition_high_collision_file
severity: medium
tags: [agents-md, budget-reckoning, rebase, high-collision-file, plan-precondition-drift]
synced_to: []
---

# Rebase before applying AGENTS.* plan edits when sibling PRs are in flight

## Problem

PR #4117 (wg-block-pr-ready-on-undeferred-operator-steps gate) was planned with a Phase 3 budget reckoning premised on `B_ALWAYS=24499` (cap 22000) — a 2499 B pre-existing breach the plan would close by trimming `hr-tagged-build-workflow-needs-initial-tag-push` (L15, 1372 B) and `wg-end-of-work-emit-resume-prompt` (L55, 1040 B) + retiring ≥1 `wg-*` rule.

At /work time, B_ALWAYS was already at 23936 (not 24499) and shifted again to 21849 after rebasing onto origin/main. The deviation was driven by **PR #4123 landing mid-session** — that PR trimmed L15 + L55 (and other rules) and added a new `hr-observability-as-plan-quality-gate`. The plan's prescribed trims were now duplicates of #4123's work, but my branch was based on the older origin/main and didn't see them.

When I applied the plan's prescribed trims plus my new gate rule body, the budget linter still rejected because the additions overshot. User had to adjudicate "retire 2 wg-* + --no-verify" based on the stale 23936 figure. Discovering origin/main was at 21849 forced a full reassessment.

## Solution

Two-part fix:

1. **At /work Phase 0 for any plan that edits AGENTS.* (or other high-collision files like `ship/SKILL.md`):** run `git fetch origin main && git rebase origin/main` BEFORE applying plan-prescribed edits. This catches sibling PRs that landed between plan-write and /work time. If conflicts arise, resolve before applying plan edits — applying-then-rebasing duplicates work.

2. **Pre-byte-check rule body drafts before insertion.** Use `printf '%s' '…rule body…' | wc -c` and confirm `≤600` (per-rule cap) BEFORE editing the file. Avoids the iterate-edit-revert cycle when the rule overshoots the cap.

Concretely, my session's flow should have been:

```bash
# Phase 0 (work-skill)
cd <worktree>
git fetch origin main
git rebase origin/main  # catches #4123's L15/L55 trims and the new hr-observability rule
# THEN re-read AGENTS.core.md fresh, re-compute the budget delta against actual state, plan the trims
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# Now the deficit number is grounded in current state, not 5-hour-old plan estimates
```

## Key insight

**Plans that target AGENTS.* have a unique drift profile.** Every other PR review batch this week edits AGENTS.* (workflow gates, hard rules, sidecar moves are happening constantly). A plan's "B_ALWAYS = N" precondition has a half-life of hours, not days. The `wg-when-a-plan-specifies-relative-paths-e-g`-style discipline of "verify plan-quoted preconditions at /work start" exists for exactly this — but should be elevated to a HARD RULE for AGENTS.*-touching plans specifically.

The cost of `git fetch origin main && git rebase origin/main` at Phase 0 is ~2-5 seconds; the cost of duplicating sibling-PR work and reasserting the plan's premise mid-flight is ~30 minutes.

## Session Errors

1. **Stale plan baseline (B_ALWAYS=24499 estimate vs 23936 actual, then 21849 after rebase).** Recovery: full Phase 3 reassessment + worktree rebase + re-apply work. **Prevention:** /work Phase 0 should run `git fetch origin main && git rebase origin/main` BEFORE applying plan-prescribed edits to high-collision files (AGENTS.*).

2. **Bash CWD persistence drift.** After `cd /tmp` for a budget snapshot comparison, the next `git reset` failed with "must be run in a work tree". Recovery: re-anchor with explicit `cd <worktree-abs-path>`. **Prevention:** anchor every git command with explicit `cd <worktree-abs-path> && git …` when prior bash commands shifted CWD outside the worktree.

3. **Initial wg-block rule body 602 B over the 600 B per-rule cap.** Required one trim iteration. **Prevention:** pre-byte-check rule body drafts via `printf '%s' '…' | wc -c` BEFORE inserting into AGENTS.core.md.

4. **#4114 closed mid-session by sibling PR #4122.** My fixture initially used `Tracks #4114` while the plan's preconditions verified #4114 OPEN. Recovery: swapped fixture to `Tracks #4115` (still OPEN). **Prevention:** at fixture-write time, re-verify cited issue state — or prefer fixture-independent test design (test isolates regex+companion logic; issue OPEN-state is verified by separate shell-side checks).

5. **TC-3 broke when prev-line companion lookup window expanded** (review fix P2-4 from code-reviewer). The mixed fixture didn't have blank line separation, so prev-line lookup falsely cross-matched. Recovery: added blank-line separation to fixture. **Prevention:** when expanding lookup windows in regex-based gates, audit existing fixtures for false-cross-matching before committing.

6. **Edit tool stale-file rejection on parallel batch.** First Edit in a 4-edit parallel batch succeeded, blocking the rest with "File has been modified since read". **Prevention:** when parallelizing Edits to the same file after any tool that touches the file-state tracker (Bash grep with file output, etc.), re-Read first.

7. **Step 0a.5 historical-ref false-positive.** Collision-check aborted on `#3244 CLOSED` and `#4066 MERGED` which are historical references (the PR-H umbrella + merged PR that motivated this PR), not the work being implemented. Required user adjudication. **Prevention:** the one-shot Step 0a.5 gate could distinguish "leading `#N` = working issue" from "body refs = historical context" to reduce false-positive aborts.

## References

- PR #4117 (this work), PR #4125 (this PR).
- PR #4123 (sibling) — the mid-session merge that obsoleted the plan's budget baseline.
- PR #4122 (sibling) — closed #4114 mid-session, invalidating one of the plan's verified preconditions.
- AGENTS.md `wg-when-a-plan-specifies-relative-paths-e-g` — the existing "verify plan-quoted preconditions at /work start" discipline; this learning suggests strengthening it for AGENTS.*-touching plans specifically.
- `plugins/soleur/skills/work/SKILL.md` Phase 0 (`### Phase 0: Load Knowledge Base Context`) — the natural insertion point for the fetch+rebase guidance.
