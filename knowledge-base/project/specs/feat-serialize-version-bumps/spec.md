# Feature: Serialize Version Bumps to Merge-Time Only

## Problem Statement

Version bump conflicts are the top time sink — 14+ merge conflict incidents caused by parallel version bumps on main. Feature branches currently update 6+ files (plugin.json, CHANGELOG.md, README.md, marketplace.json, root README badge, bug_report.yml) independently, causing collisions at merge time. The version "triad" has expanded to a "quad" and beyond, with 16 documented learnings about version-related failures including truncated CHANGELOGs, stale badges, and cascading count drift.

## Goals

- Eliminate version bump merge conflicts entirely by moving all version file mutations to merge-time
- Automate component count updates (agents, skills, commands) to prevent drift
- Maintain high-quality human-written CHANGELOG entries via PR body parsing
- Unify version bump + release + Discord notification into a single GitHub Action
- Simplify the ship skill by removing the version bump "sealing operation" phase

## Non-Goals

- Merge queue implementation (complementary but separate concern — tracked in archived feat-merge-queue spec)
- Changing the semver classification rules (MAJOR/MINOR/PATCH definitions stay the same)
- Auto-generating CHANGELOG text from commit messages (entries remain human-written)
- Modifying the pre-merge rebase hook behavior
- Changing the compound skill ordering (compound still runs pre-push in feature branches)

## Functional Requirements

### FR1: Version Bump GitHub Action

A new `version-bump-and-release.yml` workflow triggers on push to main. It reads the `semver:patch`, `semver:minor`, or `semver:major` label from the merged PR, computes the next version from current `plugin.json`, and updates all 6 version files atomically in one commit.

### FR2: CHANGELOG Parsing from PR Body

The Action extracts the `## Changelog` section from the merged PR body and inserts it into `CHANGELOG.md` under a new version heading with the current date. If no `## Changelog` section exists, the Action uses the PR title as a single-line entry.

### FR3: Component Count Auto-Computation

The Action auto-computes agent, skill, and command counts from the filesystem (e.g., `find agents -name '*.md'`) and updates `plugin.json` description, plugin `README.md`, and root `README.md` badge/counts.

### FR4: Unified Release and Notification

The same workflow creates a GitHub Release with the changelog body and posts to the Discord webhook. This replaces `auto-release.yml` entirely, avoiding the GITHUB_TOKEN cascade problem (commits pushed by GITHUB_TOKEN don't trigger other workflows).

### FR5: Ship Skill Semver Labeling

The ship skill analyzes the diff to determine bump type (using existing semver rules), sets the appropriate `semver:*` PR label via `gh pr edit --add-label`, and validates the classification (warns if new agent/skill detected but label says PATCH). No human override gate — fully automatic.

### FR6: Feature Branch Version Exclusion

Feature branches no longer touch version files. The ship skill's Phase 5 (version bump sealing operation) and Phase 3.5 (merge-main-before-version-bump) are removed. The pre-commit checklist drops all version-related items for feature branch work.

## Technical Requirements

### TR1: Atomic Version Commit

All 6 file updates must happen in a single commit. If any file update fails, the workflow must abort without partial commits. The commit message should follow `chore(release): vX.Y.Z` format.

### TR2: Idempotency

If the workflow is re-run (e.g., manual retry), it must not create duplicate version bumps or releases. Check if the computed version tag already exists before proceeding.

### TR3: Path Filtering

The workflow must skip version bumping for PRs that don't touch `plugins/soleur/` files. Non-plugin PRs (e.g., docs-only, knowledge-base changes) should not trigger a version bump.

### TR4: Label Fallback

If no `semver:*` label is present on the merged PR, default to `patch` and log a warning. Never block the workflow for a missing label.

### TR5: Convention Updates

~15 locations reference the current version bump pattern and must be updated: constitution.md, root AGENTS.md, plugin AGENTS.md, ship SKILL.md, one-shot SKILL.md, merge-pr SKILL.md, and related learnings files.

## Acceptance Criteria

- [ ] Feature branches contain zero version file changes
- [ ] Merging a PR to main auto-bumps version in all 6 files
- [ ] CHANGELOG entries come from PR body `## Changelog` section
- [ ] Component counts are auto-computed, not manually maintained
- [ ] GitHub Release created automatically with changelog body
- [ ] Discord notification sent on release
- [ ] `auto-release.yml` removed or disabled
- [ ] Ship skill no longer has Phase 5 (version bump)
- [ ] Ship skill sets `semver:*` PR label automatically
- [ ] All convention docs updated to reflect new workflow
- [ ] Idempotent: re-running the Action on the same merge is safe
