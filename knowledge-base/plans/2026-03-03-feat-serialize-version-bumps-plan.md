---
title: "feat: Serialize version bumps to merge-time only"
type: feat
date: 2026-03-03
---

# feat: Serialize Version Bumps to Merge-Time Only

## Overview

Move all version bumping, CHANGELOG generation, component count updates, and release creation from feature branches to a single GitHub Action that runs at merge time. This eliminates the #1 source of merge conflicts (14+ incidents, ~30% of all friction events) and automates count maintenance that currently drifts.

## Problem Statement / Motivation

Every plugin change requires updating 6 files across the repo. When parallel feature branches each bump independently, they collide at merge time. The repo has 16 documented learnings about version conflicts. The root README badge is currently drifted (3.8.1 vs 3.8.2), proving the manual sync approach fails.

## Proposed Solution

A unified `version-bump-and-release.yml` GitHub Action replaces the current manual version bump + `auto-release.yml`:

1. Feature branches never touch version files
2. Ship skill analyzes diff → sets `semver:*` PR label → generates `## Changelog` section in PR body
3. On merge to main, the Action reads the label, bumps all 6 files, auto-computes counts, commits atomically, creates GitHub Release, posts to Discord

## Technical Considerations

### Branch Protection

Main is **not protected** — the Action can push commits directly using GITHUB_TOKEN. No PAT or GitHub App needed.

### GITHUB_TOKEN Cascade

Commits pushed by GITHUB_TOKEN don't trigger other `on: push` workflows. This means:
- `auto-release.yml` can't be a separate downstream workflow (already solved: unified workflow)
- `deploy-docs.yml` won't fire for the version commit → docs site misses the CHANGELOG update
- **Fix:** Add `workflow_run` trigger to `deploy-docs.yml` that fires after `version-bump-and-release` completes

### Concurrency Control

Two PRs merging within seconds both trigger the Action. Without control, both compute the same next version.
- **Fix:** `concurrency: { group: "version-bump", cancel-in-progress: false }` — queues rather than races

### PR Lookup Mechanism

The `on: push` event has no PR metadata. Parse `(#NNN)` from the squash-merge commit message (all merges use `--squash`). Fallback: `gh pr list --search "SHA" --state merged`. Skip gracefully if no PR found (direct push to main).

### Input Sanitization

PR body is user-controlled input inserted into CHANGELOG.md. Use temp files and `jq` for extraction, never shell variable interpolation. Pipe through heredocs to prevent injection.

### Docs Site Staleness

The merge commit triggers deploy-docs before the version bump. The version commit (GITHUB_TOKEN) doesn't trigger deploy-docs. Fix: add `workflow_run` trigger to deploy-docs.yml keyed on version-bump-and-release completion.

### Component Count Methodology

Exact commands to match current counts (61 agents, 3 commands, 55 skills):
- Agents: `find plugins/soleur/agents -name '*.md' ! -name 'README.md' ! -name 'AGENTS.md' | wc -l`
- Skills: `find plugins/soleur/skills -name 'SKILL.md' | wc -l`
- Commands: `find plugins/soleur/commands -name '*.md' | wc -l`
- MCP servers: hardcoded or count from plugin.json `mcpServers` array

Validate these produce correct counts before deploying. If counts drift due to directory structure changes, update the find patterns in the Action.

### Approximate Line References

Line numbers in this plan (e.g., "constitution.md line 50") are from the time of writing and may shift if other PRs merge first. Always read files before editing.

## Acceptance Criteria

- [ ] Feature branches contain zero version file changes
- [ ] Merging a plugin PR to main auto-bumps version in all 6 files
- [ ] CHANGELOG entries come from PR body `## Changelog` section (fallback: PR title)
- [ ] Component counts auto-computed from filesystem
- [ ] GitHub Release created with changelog body
- [ ] Discord notification sent on release
- [ ] `auto-release.yml` removed
- [ ] Ship skill sets `semver:*` PR label automatically
- [ ] Non-plugin PRs skip version bumping
- [ ] Concurrent merges queue (no race conditions)
- [ ] Idempotent: re-running the Action on the same merge is safe
- [ ] All convention docs updated to reflect new workflow
- [ ] Docs site rebuilds after version commit

## Test Scenarios

- Given a plugin PR merges with `semver:minor` label and `## Changelog` section, when the Action runs, then all 6 files are bumped (MINOR), CHANGELOG contains the PR body text, Release is created, Discord is notified
- Given a non-plugin PR merges (only knowledge-base/ changes), when the Action runs, then no version bump occurs
- Given a PR merges without any `semver:*` label, when the Action runs, then it defaults to PATCH and logs a warning
- Given a PR merges without `## Changelog` section, when the Action runs, then it uses the PR title as the CHANGELOG entry
- Given the Action is re-triggered on the same commit, when it runs, then it detects the existing tag and skips
- Given two PRs merge within 5 seconds, when both Actions trigger, then the concurrency group queues them and both bump sequentially (3.8.3 then 3.8.4)
- Given a direct push to main (no PR), when the Action runs, then it skips gracefully (no PR found)
- Given a PR body contains shell metacharacters in the Changelog section, when the Action runs, then the content is safely written to CHANGELOG.md without injection
- Given a PR body has a `## Changelog` heading with nothing under it, when the Action runs, then it falls back to the PR title (does not produce an empty entry)
- Given a `workflow_dispatch` trigger with `bump_type: minor`, when the Action runs, then it bumps MINOR regardless of labels (manual escape hatch)

## Implementation Phases

### Phase 1: Create the GitHub Action and PR Template

**New files:**

#### `.github/workflows/version-bump-and-release.yml`

Workflow steps:
1. Trigger: `on: push: branches: [main]` (no path filter — the Action itself decides whether to bump) + `workflow_dispatch` with `bump_type` choice input (escape hatch for manual releases)
2. Concurrency: `group: "version-bump"`, `cancel-in-progress: false`
3. Permissions: `contents: write`
4. Checkout with `fetch-depth: 2` (need parent commit to diff)
5. **Check if plugin files changed:** `git diff --name-only HEAD~1 -- plugins/soleur/` — if empty, skip everything
6. **Find merged PR:** Parse `(#NNN)` from `${{ github.event.head_commit.message }}`, then `gh pr view NNN --json labels,body`
7. **Determine bump type:** Read `semver:*` label, default to `patch` if missing (log warning)
8. **Read current version:** `jq -r '.version' plugins/soleur/.claude-plugin/plugin.json`
9. **Compute next version:** Increment MAJOR/MINOR/PATCH accordingly
10. **Check idempotency:** `gh release view "v$NEXT" &>/dev/null` — skip if exists
11. **Extract CHANGELOG from PR body:** Parse text between `## Changelog` and next `##` heading. Fallback: PR title. Write to temp file (sanitized).
12. **Compute component counts:** Run the `find` commands, produce count strings
13. **Update all 6 files atomically:**
    - `plugin.json`: version + description counts (via `jq`)
    - `CHANGELOG.md`: insert new version section at top (via `awk`/`sed` + temp file)
    - `README.md` (plugin): update count tables (via `sed`)
    - `marketplace.json`: update `plugins[0].version` (via `jq`)
    - `README.md` (root): update badge URL (via `sed`)
    - `bug_report.yml`: update placeholder (via `sed`)
14. **Verify consistency:** Check all 6 files now contain the same version string before committing. If any mismatch, abort without pushing.
15. **Commit and push:** Stage only the 6 explicit sync target files (never `git add -A`):
    ```bash
    git add plugins/soleur/.claude-plugin/plugin.json \
           plugins/soleur/CHANGELOG.md \
           plugins/soleur/README.md \
           .claude-plugin/marketplace.json \
           README.md \
           .github/ISSUE_TEMPLATE/bug_report.yml
    git commit -m "chore(release): vX.Y.Z"
    git push
    ```
16. **Create GitHub Release:** `gh release create "vNEXT" --notes-file /tmp/changelog.md`
17. **Post to Discord:** Same pattern as current auto-release.yml (with secret check, truncation, jq payload)

#### `.github/PULL_REQUEST_TEMPLATE.md`

```markdown
## Summary
<!-- Brief description of changes -->

## Changelog
<!-- Required for plugin changes. Describe what changed for the CHANGELOG.
     Use Keep a Changelog format: Added, Changed, Fixed, Removed.
     This section is parsed by CI and inserted into CHANGELOG.md at merge time. -->

## Test plan
<!-- How to verify this works -->
```

### Phase 2: Update Ship Skill

**File:** `plugins/soleur/skills/ship/SKILL.md`

Changes:
- **Remove Phase 3.5** (merge main before version bump) — no longer needed
- **Remove Phase 5** (version bump sealing operation) — moved to CI
- **Remove version conflict resolution from Phase 7.5** — version files are never modified in feature branches, so conflict routing strategies for plugin.json/README badge/bug_report.yml are dead code
- **Update Phase 6 checklist** — remove version-related items
- **Update Phase 7** (PR creation) — add steps:
  - Analyze diff to determine bump type (MINOR/PATCH/MAJOR)
  - Set `semver:*` label via `gh pr edit --add-label semver:patch`
  - Generate `## Changelog` section from diff summary and insert into PR body
  - Validate: warn if new agent/skill detected but label says PATCH
- **Update Phase 8** — remove reference to auto-release.yml trigger
- **Update description frontmatter** — remove "version is bumped before creating a PR"

### Phase 3: Update Related Skills

**File:** `plugins/soleur/skills/merge-pr/SKILL.md`
- Remove Phase 4 (Version Bump) entirely (lines 222-281)
- Update Phase 3 conflict resolution table — remove version file routing strategies
- Update description frontmatter — remove "bumping version" reference
- Update Phase 7.3 end-of-run report — remove version line
- Update rollback section — remove "merge + version bump" reference

**File:** `plugins/soleur/skills/one-shot/SKILL.md`
- Update line 98 ship phase description — remove Phase 5 reference

**File:** `plugins/soleur/skills/compound-capture/SKILL.md`
- Line 308: remove "or version-bump" from "Do NOT commit or version-bump"

**File:** `plugins/soleur/skills/release-announce/SKILL.md`
- Add note that this is now a manual fallback — the Action handles releases automatically

### Phase 4: Convention Documentation Updates

**File:** `AGENTS.md` (root)
- Line 24: Rewrite "Every plugin change: bump version..." → "Every plugin change: CI auto-bumps version at merge time. Feature branches must NOT touch version files."

**File:** `plugins/soleur/AGENTS.md`
- Rewrite "Versioning Requirements" section — explain new CI-driven model
- Keep MAJOR/MINOR/PATCH definitions (still relevant for PR labels)
- Replace Pre-Commit Checklist — remove all version-related items, add: "Ensure `## Changelog` section in PR body for plugin changes"
- Add note: "Version bumping, CHANGELOG updates, count reconciliation, and release creation are handled by `version-bump-and-release.yml` at merge time"

**File:** `knowledge-base/overview/constitution.md`
- Line 50: Update docs version grep → "CI handles version propagation at merge time"
- Line 63: Rewrite three-file rule → "CI auto-updates version files at merge time"
- Line 64: Remove "Always fetch and check main before version bumps"
- Line 66: Update count diff rule → "CI auto-reconciles counts at merge time"
- Line 77: Rewrite sealing operation → "Version bump is handled by CI at merge time, after compound runs in the feature branch"
- Line 104: Simplify parallel branch conflict note → "Version files are not modified in feature branches, eliminating version conflicts"
- Line 150: Keep semver intent rule but simplify rationale

### Phase 5: Remove auto-release.yml and Update deploy-docs.yml

**File:** `.github/workflows/auto-release.yml`
- Delete entirely (replaced by version-bump-and-release.yml)

**File:** `.github/workflows/deploy-docs.yml`
- Add `workflow_run` trigger with success check:
  ```yaml
  on:
    workflow_run:
      workflows: ["Version Bump and Release"]
      types: [completed]
  jobs:
    deploy:
      if: ${{ github.event.workflow_run.conclusion == 'success' }}
  ```
- This ensures docs rebuild after a successful version commit (not after failed bumps)

### Phase 6: Fix Pre-Existing Drift

- Root `README.md` line 7: Fix badge from `3.8.1` to current version (this will be auto-maintained going forward)
- Validate all 6 version files are in sync before the first merge under the new model

### Phase 7: Migration Notes

- Document in PR description that existing worktrees (`feat-standardize-shebang`, `feat-migrate-hooks-json`) must revert version file changes before merging:
  ```bash
  git checkout origin/main -- plugins/soleur/.claude-plugin/plugin.json plugins/soleur/CHANGELOG.md plugins/soleur/README.md .claude-plugin/marketplace.json README.md .github/ISSUE_TEMPLATE/bug_report.yml
  ```
- First merge after this lands will be the real test

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Concurrent merge race condition | HIGH | `concurrency` group with `cancel-in-progress: false` |
| PR body injection into CHANGELOG | MEDIUM | Temp file approach, no shell interpolation |
| Wrong component counts | MEDIUM | Validate `find` commands against current counts before deploy |
| Docs site misses version commit | MEDIUM | `workflow_run` trigger on deploy-docs.yml |
| Existing worktrees have version changes | LOW | Migration note in PR; revert version files |
| release-announce skill redundancy | LOW | Keep as manual fallback, add deprecation note |

## File Hit List (Complete)

### New Files (2)
- `.github/workflows/version-bump-and-release.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`

### Files to Delete (1)
- `.github/workflows/auto-release.yml`

### Files to Modify (10)
- `plugins/soleur/skills/ship/SKILL.md` — remove Phase 3.5 + 5 + 7.5 version conflict routing, add label + changelog
- `plugins/soleur/skills/merge-pr/SKILL.md` — remove Phase 4
- `plugins/soleur/skills/one-shot/SKILL.md` — update ship description
- `plugins/soleur/skills/compound-capture/SKILL.md` — minor rewording
- `plugins/soleur/skills/release-announce/SKILL.md` — add fallback note
- `AGENTS.md` (root) — rewrite version gate
- `plugins/soleur/AGENTS.md` — rewrite versioning section + checklist
- `knowledge-base/overview/constitution.md` — update ~6 lines
- `.github/workflows/deploy-docs.yml` — add workflow_run trigger
- `plugins/soleur/docs/index.njk` — optional: reword marketing copy line 116

### CI Sync Targets (6 files the Action writes)
- `plugins/soleur/.claude-plugin/plugin.json`
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md`
- `.claude-plugin/marketplace.json`
- `README.md` (root)
- `.github/ISSUE_TEMPLATE/bug_report.yml`

## References

- Issue: [#391](https://github.com/jikig-ai/soleur/issues/391)
- Brainstorm: `knowledge-base/brainstorms/2026-03-03-serialize-version-bumps-brainstorm.md`
- Spec: `knowledge-base/specs/feat-serialize-version-bumps/spec.md`
- Current workflow: `.github/workflows/auto-release.yml`
- Learnings: `knowledge-base/learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md`
- Learnings: `knowledge-base/learnings/2026-02-26-version-bump-after-compound-ordering.md`
- Learnings: `knowledge-base/learnings/integration-issues/github-actions-auto-release-permissions.md`
