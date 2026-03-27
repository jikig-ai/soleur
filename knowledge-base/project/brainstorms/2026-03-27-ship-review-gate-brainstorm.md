# Ship Review Gate Enforcement Brainstorm

**Date:** 2026-03-27
**Issue:** #1227
**Status:** Decided

## What We're Building

A hard-deny PreToolUse hook (Guard 6) on `gh pr merge` that blocks merging when no review evidence exists on the branch. Bypass via a `hotfix` GitHub label on the PR — auditable, two-step, and consistent with existing label patterns (semver labels).

Additionally: consolidate the ship skill's redundant review checks (Phase 1.5 and Phase 5.5) into a single gate at Phase 1.5, and add a brief hotfix protocol to AGENTS.md.

## Why This Approach

The sign-in fix session (#1213, #1214, #1219, #1220) showed that the review gate inside `/ship` is ineffective when `/ship` is never called. The four PRs were merged via raw `gh pr create` + `gh pr merge`, bypassing all skill-level gates. PR #1219 shipped a TypeScript error that only CI caught.

The fix must be at the hook level — the only enforcement layer that fires regardless of which skill (or no skill) the agent uses. The existing `pre-merge-rebase.sh` already intercepts `gh pr merge`, proving the pattern works.

## Key Decisions

1. **Hard deny, not warning.** The project's existing hooks (Guards 1-5) all use deny. A warning-only review gate would be inconsistent and easily ignored under urgency — the exact failure mode we're fixing.

2. **Escape hatch: GitHub 'hotfix' label.** Requires `gh pr edit <N> --add-label hotfix` before merge. Auditable in PR history, two-step (deliberate), consistent with existing label patterns. The deny message tells the agent exactly how to bypass.

3. **Single review gate at Phase 1.5.** Remove the Phase 5.5 review check in the ship skill. Phase 1.5 is the correct position (fail early). In headless mode: abort, not auto-invoke. Phase 5.5 had inconsistent behavior (auto-invoked review in headless, used looser grep).

4. **Brief hotfix protocol in AGENTS.md.** Three steps: (1) add 'hotfix' label, (2) merge, (3) follow-up review within 24h. The hook's deny message references this protocol.

## Open Questions

None — all decisions made during brainstorm.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO identified that the real interception point is `gh pr merge`, not `git push` or `/ship` internals. Recommends Option A (warning) but user chose hard deny + label escape hatch. Review evidence detection should be centralized in a shared script to prevent drift between hook and ship skill. GitHub branch protection (enforcement outside Claude Code) is a separate future concern.
