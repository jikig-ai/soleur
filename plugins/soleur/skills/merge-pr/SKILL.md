---
name: merge-pr
description: "This skill should be used when merging a feature branch to main with automatic conflict resolution and cleanup. It automates merging main into the feature branch, resolving conflicts, pushing, creating a PR, waiting for CI, merging, and cleaning up the worktree."
---

# merge-pr Skill

**Purpose:** Automate the merge pipeline for a single PR -- replacing the manual execution of `/ship` Phases 3.5-8. Runs lights-out: merge main, resolve conflicts, push, create PR, wait for CI, merge, and cleanup.

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
STOPPED: Uncommitted changes detected. Commit changes before running merge-pr.
```

### 1.3 Compound has run

Extract the feature name from the branch (strip `feat-`, `feature/`, `fix-`, `fix/` prefix). Search for unarchived KB artifacts matching the feature name in:

- `knowledge-base/project/brainstorms/` (excluding `archive/` paths)
- `knowledge-base/project/plans/` (excluding `archive/` paths)
- `knowledge-base/project/specs/feat-<feature>/`

If any unarchived artifacts are found, stop:

```text
STOPPED: Unarchived KB artifacts found for this feature:
<list of files>

Use `skill: soleur:compound` to consolidate and archive these artifacts, then re-run `skill: soleur:merge-pr`.
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

> **Note:** Version bumping is handled automatically by CI at merge time. This skill does not bump versions.

## Phase 3: Conflict Resolution

Identify conflicted files:

```bash
git diff --name-only --diff-filter=U
```

### 3.1 Route conflicts

For each conflicted file, apply the appropriate resolution strategy:

| File Pattern | Strategy |
|-------------|----------|
| `plugins/soleur/CHANGELOG.md` | Merge both sides -- see 3.2 |
| `plugins/soleur/README.md` | Accept feature branch component counts |
| Everything else | Claude-assisted resolution -- see 3.3 |

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

## Phase 4: Push and PR

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

**If no PR exists:** Before creating, detect associated issue numbers from the branch name (e.g., `fix/123-desc`) and commit messages (`git log origin/main..HEAD --oneline`). Then create the PR:

```bash
gh pr create --title "<type>: <description>" --body "
## Summary
<bullet points summarizing changes>

Closes #ISSUE_NUMBER

## Test plan
- [ ] CI passes
- [ ] Manual verification of merge pipeline

Generated with [Claude Code](https://claude.com/claude-code)
"
```

If an issue number was detected, include the `Closes #N` line. If none, omit it. Derive the title from the branch name and changes. Use `feat:` for features, `fix:` for bug fixes.

Announce the PR URL.

## Phase 5: CI and Merge

### 5.1 Queue Auto-Merge

```bash
gh pr merge <number> --squash --auto
```

This queues the merge. GitHub waits for all branch protection requirements (CI checks, CLA) to pass, then merges automatically. Do NOT use `gh pr checks --watch` -- it exits immediately with "no checks reported" when CI hasn't registered yet.

**NEVER use `--delete-branch`.** The guardrails hook blocks it when any worktree exists. Branch cleanup is handled by `cleanup-merged` in Phase 6.

### 5.2 Poll for Merge

Poll until the PR state is MERGED:

```bash
gh pr view <number> --json state --jq .state
```

If the state is `CLOSED` (not `MERGED`), auto-merge was cancelled -- check for CI failures:

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

## Phase 6: Cleanup and Report

### 6.1 Navigate to repo root

The `cleanup-merged` script skips the current working directory's worktree. Navigate to the main repo root first:

Navigate to the main repository root directory (the parent of `.worktrees/`). Run `cd` to the repo root path, then verify with `pwd`.

### 6.2 Run cleanup

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
```

This detects `[gone]` branches (remote deleted after merge), removes worktrees, archives spec directories, deletes local branches, and pulls latest main so the next worktree branches from the current state.

### 6.3 End-of-run report

Print a summary:

```text
merge-pr complete!

PR: #<number> (<URL>)
Merge SHA: <sha>
Cleanup: <worktrees cleaned or "no cleanup needed">

Rollback (if needed): git reset --hard <starting-sha>
```

Replace `<starting-sha>` with the SHA recorded at the start of the pipeline.

## Rollback

If the pipeline fails partway through and the branch has unwanted commits (e.g., merge commit), rollback to the starting state:

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
