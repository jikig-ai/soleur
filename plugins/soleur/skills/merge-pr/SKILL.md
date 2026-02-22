---
name: merge-pr
description: This skill should be used when merging a feature branch to main with automatic conflict resolution and cleanup. It automates the merge pipeline -- merging main into the feature branch, resolving conflicts, bumping version, pushing, creating a PR, waiting for CI, merging, and cleaning up the worktree. Triggers on "merge this PR", "merge my branch", "auto-merge", "merge and cleanup".
---

# merge-pr Skill

**Purpose:** Automate the merge pipeline for a single PR -- replacing the manual execution of `/ship` Phases 3.5-8. Runs lights-out: merge main, resolve conflicts, version bump, push, create PR, wait for CI, merge, and cleanup.

**Relationship to /ship:** Both skills are independent user-invoked entry points. `/ship` handles artifact validation, compound, and documentation (Phases 0-3). This skill handles the merge-through-cleanup pipeline. They do NOT invoke each other.

**Arguments:** Optional branch name. If omitted, auto-detects from current branch.

## Phase 0: Context Detection

Detect the current environment and record the starting state for rollback. Run these commands separately and store the results:

1. Get current branch name:
```bash
git rev-parse --abbrev-ref HEAD
```

2. Get current commit SHA (this is the rollback point):
```bash
git rev-parse HEAD
```

3. Get current working directory path (worktree path):
```bash
pwd
```

4. Get the main repo root (first path from worktree list output):
```bash
git worktree list
```

Store these four values as BRANCH, STARTING_SHA, WORKTREE_PATH, and REPO_ROOT for use throughout the pipeline.

Load project conventions:

```bash
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

If an argument was provided, verify that branch exists and check it out. Otherwise use the current branch.

Announce:

```text
merge-pr: Starting pipeline for branch: <branch-name>
Starting SHA: <starting-sha> (rollback point)
```

Replace `<branch-name>` with the actual branch name and `<starting-sha>` with the current HEAD SHA.

## Phase 1: Pre-condition Validation

Validate all pre-conditions before proceeding. On any failure, stop immediately and report.

### 1.1 Not on default branch

```bash
git rev-parse --abbrev-ref HEAD
```

If the branch is `main` or `master`, stop:

```text
STOPPED: Cannot run merge-pr on the default branch.
Switch to a feature branch or provide a branch name as argument.
```

### 1.2 Clean working tree

```bash
git status --porcelain
```

If output is non-empty, stop:

```text
STOPPED: Uncommitted changes detected. Commit or stash before running merge-pr.
```

### 1.3 Compound has run

Extract the feature name from the branch (strip `feat-`, `feature/`, `fix-`, `fix/` prefix). Search for unarchived KB artifacts matching the feature name in:

- `knowledge-base/brainstorms/` (excluding `archive/` paths)
- `knowledge-base/plans/` (excluding `archive/` paths)
- `knowledge-base/specs/feat-<feature>/`

If any unarchived artifacts are found, stop:

```text
STOPPED: Unarchived KB artifacts found for this feature:
<list of files>

Run /soleur:compound to consolidate and archive these artifacts, then re-run /soleur:merge-pr.
```

If no unarchived artifacts exist (either compound already archived them, or no artifacts were created), proceed.

## Phase 2: Merge Main

Fetch the latest main and merge into the feature branch:

```bash
git fetch origin main
git merge origin/main
```

**If merge is clean (exit code 0):** Proceed to Phase 4 (skip Phase 3).

**If merge conflicts (exit code non-zero):** Proceed to Phase 3.

## Phase 3: Conflict Resolution

Identify conflicted files:

```bash
git diff --name-only --diff-filter=U
```

### 3.1 Route conflicts

For each conflicted file, apply the appropriate resolution strategy:

| File Pattern | Strategy |
|-------------|----------|
| `plugins/soleur/.claude-plugin/plugin.json` | Accept main's version (Phase 4 re-bumps) |
| `plugins/soleur/CHANGELOG.md` | Merge both sides -- see 3.2 |
| `plugins/soleur/README.md` | Accept feature branch component counts |
| `README.md` (root) | Accept main's version badge (Phase 4 re-bumps) |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Accept main's placeholder (Phase 4 re-bumps) |
| Everything else | Claude-assisted resolution -- see 3.3 |

**For version files where "accept main's version" is the strategy:**

```bash
git checkout --theirs <file>
git add <file>
```

**For README.md (accept feature branch):**

```bash
git checkout --ours plugins/soleur/README.md
git add plugins/soleur/README.md
```

### 3.2 CHANGELOG merge

CHANGELOG requires special handling to preserve entries from both sides without truncation.

Read both sides using git stage numbers (NOT `git show HEAD:` which only gives one side):

```bash
git show :2:plugins/soleur/CHANGELOG.md > /tmp/changelog-ours.md
git show :3:plugins/soleur/CHANGELOG.md > /tmp/changelog-theirs.md
```

- `:2:` is "ours" (feature branch)
- `:3:` is "theirs" (main)

Read both files. Reconstruct the complete CHANGELOG:
- Keep the file header (title, description, links)
- Merge version entries in descending version order
- If the feature branch has a draft entry, keep it
- All entries from main must be preserved

Write the complete reconstructed file. Then verify integrity:

```bash
wc -l plugins/soleur/CHANGELOG.md
```

The line count should be roughly the sum of unique lines from both sides. If the result is suspiciously short (less than 80% of the larger input file), something was truncated -- stop and report.

```bash
git add plugins/soleur/CHANGELOG.md
```

### 3.3 Claude-assisted resolution

For non-version-file conflicts, read the conflicted file and resolve based on intent:

1. Read the file with conflict markers
2. Understand what each side changed and why
3. Resolve the conflict preserving the intent of both changes
4. Write the resolved file

If resolution confidence is low (ambiguous intent, large conflict spanning many lines, or the changes are contradictory), abort the entire merge:

```bash
git merge --abort
```

Then stop:

```text
STOPPED: Could not confidently resolve conflict in: <file>
The merge has been aborted. Working tree is clean at the starting SHA.

Conflicted files:
<list>

Resolve manually, then re-run /soleur:merge-pr.
```

### 3.4 Commit resolved conflicts

After all conflicts are resolved:

```bash
git commit -m "merge: resolve conflicts with origin/main"
```

## Phase 4: Version Bump (Conditional)

Check if any files under `plugins/soleur/` were modified in this branch:

```bash
git diff --name-only origin/main...HEAD -- plugins/soleur/
```

**If no plugin files changed:** Skip this phase entirely. Announce "No plugin files changed -- skipping version bump."

**If plugin files changed:**

### 4.1 Determine bump type

Check for new component files:

```bash
git diff --name-only --diff-filter=A origin/main...HEAD -- \
  plugins/soleur/skills/ \
  plugins/soleur/agents/ \
  plugins/soleur/commands/
```

- If new files in skills/, agents/, or commands/ directories: **MINOR** bump
- Otherwise: **PATCH** bump

### 4.2 Read current version

```bash
cat plugins/soleur/.claude-plugin/plugin.json
```

Extract the `"version"` field. This is the base version to bump from.

### 4.3 Update versioning triad

1. **plugin.json:** Update the `"version"` field. If component counts changed, also update the `"description"` field.

2. **CHANGELOG.md:** Add a new entry at the top of the version list with today's date. Use Keep a Changelog format with `### Added`, `### Changed`, `### Fixed`, `### Removed` sections as appropriate. Write the entry based on the changes in this branch.

3. **README.md (plugin):** Verify component counts in the table match actual counts. Update if needed.

### 4.4 Update sync targets

4. **README.md (root):** Update the version badge: `![Version](https://img.shields.io/badge/version-X.Y.Z-blue)`

5. **bug_report.yml:** Update the `placeholder:` field on line 36 of `.github/ISSUE_TEMPLATE/bug_report.yml`

### 4.5 Commit version bump

```bash
git add plugins/soleur/.claude-plugin/plugin.json \
       plugins/soleur/CHANGELOG.md \
       plugins/soleur/README.md \
       README.md \
       .github/ISSUE_TEMPLATE/bug_report.yml
git commit -m "chore: bump version to X.Y.Z"
```

If the commit fails due to a pre-commit hook (e.g., markdownlint on the CHANGELOG entry), fix the linting issue and retry the commit once.

## Phase 5: Push and PR

Push the branch to remote:

```bash
git push -u origin <branch-name>
```

Replace `<branch-name>` with the actual branch name.

Check for an existing PR:

```bash
gh pr list --head <branch-name> --json number,state | jq '.[] | select(.state == "OPEN") | .number'
```

**If a PR exists:** Announce the PR number and proceed.

**If no PR exists:** Create one with `gh pr create`. Pass the body via HEREDOC to preserve formatting:

```bash
gh pr create --title "<type>: <description>" --body "
## Summary
<bullet points summarizing changes>

## Test plan
- [ ] CI passes
- [ ] Manual verification of merge pipeline

Generated with [Claude Code](https://claude.com/claude-code)
"
```

Derive the title from the branch name and changes. Use `feat:` for features, `fix:` for bug fixes.

Announce the PR URL.

## Phase 6: CI and Merge

### 6.1 Wait for CI

```bash
gh pr checks --watch --fail-fast
```

**If all checks pass:** Proceed to merge.

**If a check fails:**

```bash
gh pr checks --json name,state,description | jq '.[] | select(.state != "SUCCESS")'
```

Stop and report:

```text
STOPPED: CI check failed.

Failed checks:
<check name>: <description>

Starting SHA for rollback: <starting-sha>
To rollback: git reset --hard <starting-sha> && git push --force-with-lease origin <branch-name>
```

### 6.2 Merge

```bash
gh pr merge <number> --squash
```

**NEVER use `--delete-branch`.** The guardrails hook blocks it when any worktree exists. Branch cleanup is handled by `cleanup-merged` in Phase 7.

If `gh pr merge` fails (PR already merged, branch protection, etc.), stop and report the error.

## Phase 7: Cleanup and Report

### 7.1 Navigate to repo root

The `cleanup-merged` script skips the current working directory's worktree. Navigate to the main repo root first:

Navigate to the main repository root directory (the parent of `.worktrees/`). Run `cd` to the repo root path, then verify with `pwd`.

### 7.2 Run cleanup

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
```

This detects `[gone]` branches (remote deleted after merge), removes worktrees, archives spec directories, and deletes local branches.

### 7.3 End-of-run report

Print a summary:

```text
merge-pr complete!

PR: #<number> (<URL>)
Version: <X.Y.Z> (or "no version bump")
Merge SHA: <sha>
Cleanup: <worktrees cleaned or "no cleanup needed">

Rollback (if needed): git reset --hard <starting-sha>
```

Replace `<starting-sha>` with the SHA recorded at the start of the pipeline.

## Rollback

If the pipeline fails partway through and the branch has unwanted commits (merge + version bump), rollback to the starting state:

```bash
git reset --hard <starting-sha>
git push --force-with-lease origin <branch-name>
```

Replace `<starting-sha>` and `<branch-name>` with the actual values recorded at pipeline start.

The starting SHA is recorded in Phase 0 and printed in the end-of-run report.

## Important Rules

- **On any failure: stop and report.** Do not retry, do not guess, do not continue.
- **Never use `--delete-branch`** with `gh pr merge`. Use `cleanup-merged` for branch deletion.
- **Never commit on main.** All commits happen on the feature branch.
- **CHANGELOG integrity is critical.** Read both sides via `:2:` and `:3:` stage numbers. Verify line count after writing. Never truncate.
- **Version bump is conditional.** Skip entirely if no files under `plugins/soleur/` changed.
- **Accept main's version for most version files.** The version bump step overwrites them anyway. CHANGELOG and plugin README are the exceptions.
