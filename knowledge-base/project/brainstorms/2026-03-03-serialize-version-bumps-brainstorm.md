# Brainstorm: Serialize Version Bumps to Merge-Time Only

**Date:** 2026-03-03
**Issue:** [#391](https://github.com/jikig-ai/soleur/issues/391)
**Status:** Decision captured
**Participants:** User, CTO agent, repo-research-analyst, learnings-researcher

## What We're Building

A GitHub Action that centralizes all version bumping, CHANGELOG generation, component count updates, and release creation to merge-time only. Feature branches will no longer touch version files, eliminating the #1 source of merge conflicts (14+ incidents, ~30% of all friction events).

## Why This Approach

### Problem

Every plugin change currently requires updating 6+ files in the feature branch:
- `plugins/soleur/.claude-plugin/plugin.json` (version)
- `plugins/soleur/CHANGELOG.md` (entry)
- `plugins/soleur/README.md` (counts)
- `.claude-plugin/marketplace.json` (version)
- `README.md` root (badge)
- `.github/ISSUE_TEMPLATE/bug_report.yml` (placeholder)

When multiple feature branches bump versions independently, they collide at merge time. The repo has 16 documented learnings about version conflicts, the "triad" expanded to a "quad", truncated CHANGELOGs during rebase, and stale version badges (root README is currently drifted: 3.8.1 vs 3.8.2).

### Options Evaluated

| Option | Verdict | Reason |
|--------|---------|--------|
| **A: GitHub Action on merge** | Selected | Only option compatible with server-side squash-merge |
| **B: Post-merge local hook** | Rejected | `gh pr merge --squash --auto` runs server-side; no local hook fires |
| **C: Merge queue** | Complementary | Serializes PRs but doesn't perform the bump; needs Option A underneath |

### Why Option A Wins

- Feature branches never touch version files = zero conflict surface
- Compatible with `--squash --auto` server-side merges
- Auto-computes component counts = eliminates count drift
- Merges release logic into same workflow = avoids GITHUB_TOKEN cascade problem

## Key Decisions

### 1. CHANGELOG Entries: PR Body Section

Feature branches no longer edit `CHANGELOG.md`. Instead:
- Ship skill requires a `## Changelog` section in the PR body
- The GitHub Action parses this section and inserts it into `CHANGELOG.md` at merge time
- Keeps entries high-quality (human-written during development) without file conflicts

### 2. Bump Type: LLM-Labeled, Fully Automatic

- Ship skill analyzes the diff and determines MINOR/PATCH/MAJOR
- Ship skill sets a PR label (`semver:patch`, `semver:minor`, `semver:major`)
- Ship validates the label (warns if new agent detected but label says PATCH)
- The Action reads the label and bumps accordingly
- No human override gate needed — fully automatic

### 3. Unified Workflow (Bump + Release + Discord)

The new `version-bump-and-release.yml` replaces `auto-release.yml`:
1. Triggers on push to main
2. Reads `semver:*` label from merged PR
3. Computes next version from current `plugin.json`
4. Updates all 6 version files atomically
5. Auto-computes component counts (agents, skills, commands)
6. Parses `## Changelog` from PR body → inserts into `CHANGELOG.md`
7. Commits all changes in one atomic commit
8. Creates GitHub Release with changelog body
9. Posts to Discord webhook

This avoids the GITHUB_TOKEN cascade problem (a commit pushed by GITHUB_TOKEN doesn't trigger other workflows).

### 4. Ship Skill Restructuring

- **Remove:** Phase 5 (version bump sealing operation)
- **Remove:** Phase 3.5 merge-main-before-version-bump (no longer needed)
- **Add:** Bump type analysis + PR label setting
- **Add:** PR body `## Changelog` section validation
- **Simplify:** Pre-commit checklist drops all version-related items

### 5. Component Count Automation

The Action auto-computes counts at merge time:
- `find agents -name '*.md' | wc -l` for agent count
- Similar for skills and commands
- Updates plugin.json description, plugin README.md, root README.md
- Eliminates count drift entirely

## Open Questions

1. **Fallback when no semver label exists:** Default to PATCH? Block the workflow? The Action should probably default to PATCH and log a warning.

2. **Non-plugin changes:** PRs that don't touch `plugins/soleur/` shouldn't trigger a version bump. The Action needs a path filter or conditional skip.

3. **PR template enforcement:** How strictly to enforce the `## Changelog` section? Options: block merge, use PR title as fallback, or skip CHANGELOG entry for chore PRs.

4. **Convention update scope:** ~15 locations reference the current version bump pattern (constitution.md, AGENTS.md, plugin AGENTS.md, ship/one-shot/merge-pr skills). Need a systematic update pass.

5. **Existing worktrees:** Two active worktrees (`feat-standardize-shebang`, `feat-migrate-hooks-json`) contain version files. They'll need to drop version changes before merge under the new model.
