# Tasks: Rule Retirement

**Plan:** `knowledge-base/plans/2026-03-05-feat-rule-retirement-audit-plan.md`
**Issue:** #422
**Branch:** feat-rule-retirement

[Updated 2026-03-05] Simplified after plan review. CI automation cut. Manual migration + compound budget check only.

## Phase 1: Manual Rule Migration

- [x] 1.1 Annotate 5 AGENTS.md rules with `[hook-enforced: <hook> <guard>]` cross-references
- [x] 1.2 Annotate 4 constitution.md rules with `[hook-enforced: <hook>]`
- [x] 1.3 Add corresponding prose rule comments to `guardrails.sh` (4 guards -> AGENTS.md + constitution.md references)
- [x] 1.4 Add corresponding prose rule comments to `pre-merge-rebase.sh` (AGENTS.md + constitution.md references)
- [x] 1.5 Add corresponding prose rule comments to `worktree-write-guard.sh` (AGENTS.md + constitution.md references)

## Phase 2: Compound Budget Check

- [x] 2.1 Add rule budget count to end of Phase 1.5 output in `plugins/soleur/skills/compound/SKILL.md`
- [x] 2.2 Add threshold warning (> 250) with message about retiring hook-enforced rules
- [x] 2.3 Add instruction to Deviation Analyst: check if existing hook covers proposed enforcement before proposing

## Phase 3: Tracking and Cleanup

- [x] 3.1 File GitHub issue: "Revisit automated rule audit if always-loaded rule count exceeds 300" (#451)
- [x] 3.2 Update spec.md with resolved open questions
- [x] 3.3 Run compound to validate budget check works in current session
