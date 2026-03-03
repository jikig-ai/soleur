# fix: close remaining merge conflict gaps

**Issue:** #395
**Branch:** feat-merge-conflict-fixes
**Type:** fix
**Semver:** patch (bug fixes and doc corrections, no new skills/agents)

## Summary

Four targeted fixes that close the remaining merge conflict gaps after tag-only versioning (#412) eliminated the #1 conflict source. Canonicalizes the merge strategy (resolving the rebase/merge contradiction), adds pre-push sync to `/ship`, adds a conflict marker pre-commit guard, and adds a worktree refresh command.

## Context

The brainstorm and CTO assessment revealed:
- AGENTS.md mandates rebase but both `/ship` and `/merge-pr` use merge. The `pre-merge-rebase.sh` hook uses rebase but only fires on `gh pr merge`.
- No pre-push conflict detection exists — conflicts are discovered after PR creation.
- Conflict markers have been accidentally committed (documented learning) with no hook to prevent it.
- No `worktree-manager.sh` command exists to bring stale worktrees current with main.

SpecFlow analysis identified 21 gaps. Critical resolutions incorporated below.

## Changes

### 1. Canonicalize merge strategy (FR1, FR2)

**Files:**

- `AGENTS.md:14` — Change "rebase on origin/main (`git fetch origin main && git rebase origin/main`)" to "merge origin/main into the feature branch (`git fetch origin main && git merge origin/main`)"
- `knowledge-base/overview/constitution.md:107` — Change "rebase feature branch on latest origin/main" to "merge latest origin/main into feature branch"
- `.claude/hooks/pre-merge-rebase.sh` → `.claude/hooks/pre-merge-sync.sh` — Rename file, replace `git rebase origin/main` with `git merge origin/main`, replace `git rebase --abort` with `git merge --abort`, change push from `--force-with-lease --force-if-includes` to plain `git push` (merge doesn't rewrite history)
- `.claude/settings.json:28` — Update hook path from `pre-merge-rebase.sh` to `pre-merge-sync.sh`

**SpecFlow edge cases addressed:**
- **Gap 6:** After `git merge origin/main` fails, run `git merge --abort` before returning deny JSON (mirrors current `rebase --abort` pattern)
- **Gap 5:** Switch from force-push to regular push since merge doesn't rewrite history
- **Gap 7:** Let `git merge` auto-commit when no conflict (no `--no-commit` flag — matches merge-pr Phase 2)
- **Gap 9:** Rename + settings.json update in same commit

### 2. Pre-push sync in `/ship` Phase 5.5 (FR3, TR1)

**Files:**

- `plugins/soleur/skills/ship/SKILL.md` — Insert new Phase 5.5 "Pre-Push Sync" between Phase 5 (Final Checklist, ends ~line 157) and Phase 6 (Push and Create PR, starts ~line 159)

**Phase 5.5 logic:**

```text
1. git fetch origin main
2. Compare: MERGE_BASE=$(git merge-base HEAD origin/main)
   MAIN_TIP=$(git rev-parse origin/main)
   If MERGE_BASE == MAIN_TIP → already up-to-date, skip to Phase 6
3. git merge origin/main
4. If clean merge → continue to Phase 6 (merge commit auto-created)
5. If conflicts:
   a. Route by file pattern (from merge-pr Phase 3.1):
      - plugins/soleur/CHANGELOG.md → merge both sides via :2: and :3:
      - plugins/soleur/README.md → accept feature branch (ours)
      - Everything else → Claude-assisted resolution
   b. After resolution, grep for conflict markers: git diff --cached | grep -E '^\+(<{7}|={7}|>{7})'
   c. If markers remain or confidence is low → git merge --abort, print structured summary, STOP
   d. If clean → git add resolved files, git commit -m "merge: sync with origin/main"
6. Continue to Phase 6
```

**SpecFlow edge cases addressed:**
- **Gap 9 (Phase 5.5 vs 6.5 overlap):** Leave Phase 6.5 as safety net — it catches the rare case where main advances between push and PR creation. Add a note in Phase 6.5: "This is a fallback. Phase 5.5 handles the common case."
- **Gap 10 (low confidence definition):** Reuse merge-pr Phase 3.3 criteria: ambiguous intent, large conflict spanning many lines, or contradictory changes
- **Gap 11 (strategy duplication):** Copy the decision table with a comment: "Mirrors merge-pr Phase 3.1. If updating, update both." Accept the duplication per brainstorm decision (shared utility deferred).
- **Gap 12 (ordering):** Phase 5.5 runs after the checklist but before push. The checklist is a gate summary, not a pre-merge verification.

### 3. Conflict marker pre-commit hook (FR4, TR2)

**Files:**

- `.claude/hooks/guardrails.sh` — Add Guard 4 after line 73 (end of Guard 3, before exit 0)

**Guard 4 logic:**

```bash
# Guard 4: Block commits with conflict markers in staged content
if echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  if git diff --cached | grep -qE '^\+(<{7}|={7}|>{7})'; then
    echo '{"decision":"block","reason":"Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."}'
    exit 0
  fi
fi
```

**SpecFlow edge cases addressed:**
- **Gap 1 (false positives):** The pattern `^\+(<{7}|={7}|>{7})` requires exactly 7 chars at BOL after `+`. Markdown `=======` as a heading separator typically follows content, not at BOL of a diff-added line. Acceptable tradeoff — false positives are preferable to missed markers. Users can inspect and re-commit.
- **Gap 2 (added lines only):** Filter to `^\+` prefix to match only added lines. Removing conflict markers (lines starting with `-`) won't trigger.
- **Gap 4 (`git merge --continue`):** Add `git\s+merge\s+--continue` to the pattern alongside `git\s+commit` since merge --continue internally commits.

**Cross-reference:** Constitution.md line 83 already has an advisory grep instruction. Add a note: "Enforced by guardrails.sh Guard 4 (PreToolUse hook)."

### 4. Worktree refresh command (FR5, TR3)

**Files:**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — Add `refresh_worktree()` function and `refresh` case in dispatch (after cleanup-merged, before draft-pr)

**Function logic:**

```bash
refresh_worktree() {
  # Guard: refuse on main/master
  local branch
  branch=$(git branch --show-current)
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "Cannot refresh default branch. Switch to a feature branch."
    exit 1
  fi

  # Guard: refuse on dirty working tree
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or discard changes before refreshing."
    exit 1
  fi

  # Fetch and merge
  git fetch origin main
  if git merge origin/main; then
    echo "Refreshed from origin/main."
  else
    git merge --abort
    echo "Merge conflicts detected. Aborting refresh."
    echo "Resolve manually: git fetch origin main && git merge origin/main"
    exit 1
  fi
}
```

**SpecFlow edge cases addressed:**
- **Gap 13 (merge conflicts):** Abort and report (option a). Keeps worktree clean.
- **Gap 14 (running on main):** Guard against main/master.
- **Gap 15 (stale node_modules):** Out of scope. File as separate issue if needed.

**Help text update:** Add to `show_help()`:
```
  refresh              Fetch and merge origin/main into current branch
```

### 5. Documentation reconciliation

- **Constitution.md line 83:** Add parenthetical: "(enforced by guardrails.sh Guard 4)"
- **Merge-pr SKILL.md Phase 1.2:** Change "Commit or stash" to "Commit changes" (removes stash reference per AGENTS.md hard rule). Pre-existing issue surfaced by SpecFlow Gap 17.

## Pre-existing issues to file

- [ ] `merge-pr` Phase 1.2 says "stash" which contradicts AGENTS.md — file issue after this PR

## Rollback

- **Hook rename:** Revert `settings.json` path and rename file back. Both in same commit = single revert.
- **Strategy change:** Revert AGENTS.md and constitution.md text. The merge strategy is already what the skills use, so reverting to "rebase" text would re-introduce the contradiction (not recommended).
- **Conflict marker guard:** Remove Guard 4 from `guardrails.sh`. No side effects.
- **Worktree refresh:** Remove function and case from `worktree-manager.sh`. No side effects.

## Test Scenarios

### Conflict marker guard

```
Given staged content with "<<<<<<< HEAD" on an added line
When the agent runs "git commit"
Then guardrails.sh blocks with "conflict markers" message

Given staged content removing "<<<<<<< HEAD" (line starts with -)
When the agent runs "git commit"
Then guardrails.sh allows the commit

Given staged content with "=======" in a markdown file as decorative separator
When the line is at BOL of an added line
Then guardrails.sh blocks (acceptable false positive)
```

### Pre-merge-sync hook

```
Given a feature branch that is up-to-date with origin/main
When the agent runs "gh pr merge"
Then pre-merge-sync.sh skips merge and allows

Given a feature branch behind origin/main with no conflicts
When the agent runs "gh pr merge"
Then pre-merge-sync.sh merges, pushes, and allows

Given a feature branch behind origin/main with conflicts
When the agent runs "gh pr merge"
Then pre-merge-sync.sh runs git merge --abort and denies with conflict file list

Given no network access
When the agent runs "gh pr merge"
Then pre-merge-sync.sh fails open (allows)
```

### Worktree refresh

```
Given a clean worktree on feat-xyz behind origin/main
When the user runs "worktree-manager.sh refresh"
Then the script merges origin/main and reports success

Given a dirty worktree
When the user runs "worktree-manager.sh refresh"
Then the script aborts with "Working tree is dirty"

Given the user is on main branch
When the user runs "worktree-manager.sh refresh"
Then the script aborts with "Cannot refresh default branch"

Given a merge conflict during refresh
When the conflict cannot be auto-resolved
Then the script runs git merge --abort and reports failure
```

### /ship Phase 5.5

```
Given a feature branch up-to-date with origin/main
When /ship reaches Phase 5.5
Then it skips to Phase 6

Given CHANGELOG.md conflicts during Phase 5.5
When both sides have new entries
Then Phase 5.5 merges both sides using :2: and :3: stage numbers

Given an unresolvable conflict in an arbitrary file
When Claude-assisted resolution has low confidence
Then Phase 5.5 runs git merge --abort and prints structured summary, stopping /ship
```
