# Ship Review Gate Enforcement Brainstorm

**Date:** 2026-03-27
**Issue:** #1227
**Status:** Decided

## What We're Building

A hard-deny review evidence check in `pre-merge-rebase.sh` that blocks `gh pr merge` when no review evidence exists on the branch. Purely local detection (zero network calls). No escape hatch — run `/review` first, even for hotfixes.

Additionally: consolidate the ship skill's redundant review checks (Phase 1.5 and Phase 5.5) into a single gate at Phase 1.5.

## Why This Approach

The sign-in fix session (#1213, #1214, #1219, #1220) showed that the review gate inside `/ship` is ineffective when `/ship` is never called. The four PRs were merged via raw `gh pr create` + `gh pr merge`, bypassing all skill-level gates. PR #1219 shipped a TypeScript error that only CI caught.

The fix must be at the hook level — the only enforcement layer that fires regardless of which skill (or no skill) the agent uses. The existing `pre-merge-rebase.sh` already intercepts `gh pr merge`, proving the pattern works.

## Key Decisions

1. **Hard deny, not warning.** The project's existing hooks (Guards 1-5) all use deny. A warning-only review gate would be inconsistent and easily ignored under urgency — the exact failure mode we're fixing.

2. ~~**Escape hatch: GitHub 'hotfix' label.**~~ [Updated 2026-03-27] Dropped after plan review — YAGNI. Two of three reviewers recommended removing it. Without the escape hatch, the guard is purely local (zero network calls, no PR number extraction). If a genuine bypass need arises, add it then.

3. **Single review gate at Phase 1.5.** Remove the Phase 5.5 review check in the ship skill. Phase 1.5 is the correct position (fail early). In headless mode: abort, not auto-invoke. Phase 5.5's auto-invoke is *wrong behavior* (hidden side effect), not just redundant.

4. **Guard lives in pre-merge-rebase.sh, not guardrails.sh.** [Updated 2026-03-27] Co-locates the guard with the side-effecting logic (fetch/merge/push) it should gate. Eliminates hook execution order dependency.

## Open Questions

None — all decisions made during brainstorm.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO identified that the real interception point is `gh pr merge`, not `git push` or `/ship` internals. Recommends Option A (warning) but user chose hard deny + label escape hatch. Review evidence detection should be centralized in a shared script to prevent drift between hook and ship skill. GitHub branch protection (enforcement outside Claude Code) is a separate future concern.
