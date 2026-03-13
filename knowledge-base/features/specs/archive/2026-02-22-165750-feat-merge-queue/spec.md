# Feature: merge-one-pr

## Problem Statement

Git operations (53/139 sessions) and PR merges (42/139 sessions) are the top two activities in Soleur development. Merge conflicts, especially in version files (plugin.json, CHANGELOG.md, README.md), cause recurring friction (11 instances). The current workflow requires manual execution of `/ship` Phases 3.5-8 for every PR, which is repetitive and error-prone.

## Goals

- Automate the merge pipeline for a single PR (replacing /ship Phases 3.5-8)
- Auto-resolve merge conflicts using deterministic heuristics for known patterns and Claude-assisted resolution for code conflicts
- Handle version bumping as part of the pipeline (batched for future multi-PR mode)
- Make wrong-branch commits structurally impossible by operating exclusively in worktrees
- Provide clear end-of-run reporting of successes and failures

## Non-Goals

- Multi-PR queue orchestration (Phase 2, deferred -- YAGNI)
- Replacing /compound (remains a pre-condition, not a pipeline step)
- Interactive conflict resolution gates (fully autonomous, no human pauses)
- Replacing /ship entirely (Phases 0-2 remain manual)

## Functional Requirements

### FR1: PR Validation

Validate pre-conditions before starting the pipeline:
- PR exists and is open
- Branch has been pushed to remote
- Compound has been run (no unarchived KB artifacts for the feature slug)
- No uncommitted changes in the worktree

### FR2: Merge Main into PR Branch

Fetch latest `origin/main` and merge into the PR branch using `git merge` (not rebase). Single conflict surface per PR.

### FR3: Conflict Auto-Resolution

Three tiers of conflict resolution:

1. **Deterministic heuristics** for known patterns:
   - Version files (plugin.json, README badge, bug_report.yml): read version from main, keep higher
   - CHANGELOG: keep both entries in descending version order
   - Component counts (README.md): use feature branch count
2. **Claude-assisted** for code conflicts: analyze both sides, resolve based on intent
3. **Abort** if resolution fails: skip PR, report failure, continue with next (future multi-PR mode)

Critical constraint: always read full files with `git show HEAD:` before editing to prevent truncation (documented learning).

### FR4: Version Bump

After merging content:
- Read current version from main's `plugin.json`
- Determine bump type based on PR changes (new skill/agent = MINOR, fix = PATCH)
- Update versioning triad: plugin.json, CHANGELOG.md, README.md
- Update additional version locations: root README badge, bug_report.yml

### FR5: CI Wait and Merge

- Push updated branch
- Wait for CI with `gh pr checks --watch --fail-fast`
- Merge with `gh pr merge --squash` (never `--delete-branch`)
- Run `cleanup-merged` to remove worktree and branch

### FR6: End-of-Run Report

Display summary of:
- PRs successfully merged (with version numbers)
- PRs skipped due to failures (with failure reasons)
- New version on main
- Any warnings or notes

## Technical Requirements

### TR1: Worktree Isolation

All operations must happen in the PR's worktree, never in the main working tree. Verify `pwd` before every git operation.

### TR2: Guardrails Compatibility

Must work with the existing guardrails hook:
- Never commit on main (version bump goes on a temporary branch or uses exception flag)
- Never use `--delete-branch` with `gh pr merge`
- Handle the worktree existence check gracefully

### TR3: CHANGELOG Integrity

When editing CHANGELOG.md:
- Read full file from `git show HEAD:plugins/soleur/CHANGELOG.md`
- Reconstruct complete file after edits
- Validate structure (no duplicate version headers, correct date format)
- Verify line count is reasonable (not truncated)

### TR4: Context Budget

Estimated 20-30k tokens per PR for conflict resolution + version bump. Single-PR mode stays within context limits. Document this constraint for future multi-PR planning.

### TR5: Exclusive Main Access

Pipeline assumes exclusive write access to main during execution. If another merge happens concurrently, version coordination breaks. Document this constraint and detect stale main with pre-merge fetch.

### TR6: Skill Structure

Implement as a new skill at `plugins/soleur/skills/merge-queue/SKILL.md`. Follow existing skill conventions (YAML frontmatter, third-person description, phased execution).
