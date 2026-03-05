# Scheduled Ship-Merge Workflow

**Date:** 2026-03-05
**Issue:** #417
**Branch:** feat-scheduled-ship-merge
**Status:** Brainstorm complete, ready for planning

## What We're Building

A GitHub Actions scheduled workflow (`scheduled-ship-merge.yml`) that automatically runs `soleur:ship --headless` on qualifying PRs. The workflow selects one qualifying PR per run, checks out its branch, invokes the full ship pipeline (compound, tests, PR update, conflict resolution, auto-merge), and applies outcome labels for deduplication.

## Why This Approach

### Problem

- PRs accumulate waiting for manual `/ship` invocation
- The `--headless` flag convention is implemented across ship, compound, and work skills but has no CI consumer yet
- Manual shipping is a repeatable, mechanical process consuming developer attention

### Why Thin Workflow YAML + ship --headless Over Alternatives

1. **Reuses existing ship skill entirely.** Ship already handles compound, tests, PR creation/update, semver labeling, conflict resolution, and auto-merge. No new skill needed.
2. **Bug-fixer workflow is a proven template.** `scheduled-bug-fixer.yml` demonstrates the PR-selection + `claude-code-action` pattern. The ship-merge workflow follows the same structure.
3. **Ship's worktree assumptions are non-blocking.** In Actions, ship's Phase 0 (worktree detection) finds no worktrees and proceeds. Phases 0-2 may produce harmless warnings but headless mode auto-skips interactive gates.
4. **Alternative approaches are YAGNI.** A new `ship-merge` skill duplicates ship logic. Extending ship with `--pr` flag requires significant refactoring. Both add complexity without clear benefit today.

## Key Decisions

### 1. Qualifying PR Criteria: Age + CI Passing

PRs qualify for auto-ship when ALL conditions are met:
- Open (not draft) for 24+ hours
- CI checks passing
- No `ship/scheduled` label (not currently being processed)
- No `ship/failed` label (not previously failed)
- No `no-auto-ship` label (not explicitly excluded)

Draft PRs are excluded by default. The `no-auto-ship` label provides an explicit opt-out mechanism.

### 2. Batching: 1 PR Per Run

One PR per scheduled run. Matches the bug-fixer pattern. Simple concurrency, bounded cost, easier debugging. If the cron runs daily and multiple PRs qualify, they clear over successive days.

### 3. Scope: Full ship --headless

The workflow invokes the complete ship skill pipeline:
- Phase 0-1: Context detection, artifact trail validation
- Phase 2: Compound (captures learnings)
- Phase 3: Documentation verification
- Phase 4: Tests
- Phase 5: Final checklist
- Phase 6: PR update, semver label, mergeability
- Phase 7: Auto-merge + poll + cleanup

### 4. Deduplication: Label-Based

| Label | Applied When | Purpose |
|-------|-------------|---------|
| `ship/scheduled` | Processing starts | Prevents parallel processing |
| `ship/failed` | Ship fails | Prevents retry without human intervention |
| (removed) `ship/scheduled` | Ship succeeds | Label removed after merge |

The selection query excludes PRs with `ship/scheduled`, `ship/failed`, or `no-auto-ship` labels.

### 5. Opt-Out: Draft + Label

Two layers of protection:
- Draft PRs excluded by default
- `no-auto-ship` label provides explicit opt-out for any PR

### 6. Workflow Architecture

```
Selection step (bash, no LLM)
  |-- gh pr list with filters
  |-- Select oldest qualifying PR
  |-- Apply ship/scheduled label
  |
Checkout step
  |-- gh pr checkout <number>
  |
LLM step (claude-code-action)
  |-- skill: soleur:ship --headless
  |
Post step (bash, always runs)
  |-- On success: remove ship/scheduled label
  |-- On failure: replace with ship/failed label + PR comment
```

## CTO Assessment Summary

- **Ship assumes worktree context (HIGH risk):** Ship's Phase 0 runs `git worktree list` and `pwd`. In Actions, no worktrees exist -- ship proceeds but may produce warnings. Non-blocking in headless mode.
- **Ship creates PRs, doesn't process them (HIGH risk):** Ship's Phase 6 checks for existing PR on current branch. When the workflow checks out the PR branch, Phase 6 finds the existing PR and updates it. This should work.
- **PreToolUse hooks unverified in Actions (HIGH risk):** Issue #419 exists but work not started. Hooks guard against commits on main, rm -rf, --delete-branch. If hooks don't fire in Actions, guardrails are absent. Mitigation: `claude-code-action` runs in a disposable container, and branch protection provides server-side guardrails.
- **Cost:** ~$1-3 per PR with Sonnet. Use `--max-turns 40`, `timeout-minutes: 30`.
- **Model:** `claude-sonnet-4-6` sufficient for mechanical shipping operations.

## Open Questions

1. Should the schedule run daily or multiple times per day?
2. What time should the cron run? (After bug-fixer at 07:00 UTC? e.g., 09:00 UTC)
3. Should failed PRs have a mechanism to retry? (e.g., removing `ship/failed` label triggers re-processing)
4. Is #419 (PreToolUse hooks verification) a hard blocker or can we proceed with branch protection as the guardrail?
