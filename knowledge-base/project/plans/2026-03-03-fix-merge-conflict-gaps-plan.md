# fix: close remaining merge conflict gaps

**Issue:** #395
**Branch:** feat-merge-conflict-fixes
**Type:** fix
**Semver:** patch (bug fixes and doc corrections, no new skills/agents)

## Summary

[Updated 2026-03-03] Two targeted fixes plus doc cleanup that close the remaining merge conflict gaps after tag-only versioning (#412) eliminated the #1 conflict source. Canonicalizes the merge strategy (resolving the rebase/merge contradiction) and adds a conflict marker pre-commit guard.

Scope reduced from 4 fixes to 2 after plan review: Phase 5.5 pre-push sync dropped (pre-merge hook + Phase 6.5 already provide two sync layers), worktree refresh command dropped (wraps two git commands nobody has asked for), hook rename dropped (edit in place, avoid settings.json churn).

## Context

The brainstorm and CTO assessment revealed:

- AGENTS.md mandates rebase but both `/ship` and `/merge-pr` use merge. The `pre-merge-rebase.sh` hook uses rebase but only fires on `gh pr merge`.
- Conflict markers have been accidentally committed (documented learning) with no hook to prevent it.

## Changes

### 1. Canonicalize merge strategy

**Files:**

- `AGENTS.md:14` — Change "Before merging any PR, rebase on origin/main (`git fetch origin main && git rebase origin/main`). Never use interactive rebase (`-i`)." to "Before merging any PR, merge origin/main into the feature branch (`git fetch origin main && git merge origin/main`)." (Remove vestigial interactive rebase clause)
- `knowledge-base/overview/constitution.md:107` — Change "rebase feature branch on latest origin/main (`git fetch origin main && git rebase origin/main`) -- rebasing ensures a clean merge even when multiple PRs land in sequence" to "merge latest origin/main into the feature branch (`git fetch origin main && git merge origin/main`) -- merging ensures a clean PR even when multiple PRs land in sequence"
- `.claude/hooks/pre-merge-rebase.sh` — Edit in place (no rename): replace `git rebase origin/main` with `git merge origin/main`, replace `git rebase --abort` with `git merge --abort`, change push from `--force-with-lease --force-if-includes` to plain `git push origin HEAD`, update file header comment to reflect merge strategy

**Edge cases:**

- After `git merge origin/main` fails with conflicts, run `git merge --abort` before returning deny JSON (mirrors current `rebase --abort` pattern)
- Switch from force-push to regular push since merge doesn't rewrite history
- Let `git merge` auto-commit when no conflict (matches merge-pr Phase 2)

### 2. Conflict marker pre-commit hook

**Files:**

- `.claude/hooks/guardrails.sh` — Add Guard 4 after Guard 3 (after line 73, before exit 0)

**Guard 4 logic:**

```bash
# Guard 4: Block commits with conflict markers in staged content
if echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*git\s+(commit|merge\s+--continue)'; then
  if git diff --cached 2>/dev/null | grep -qE '^\+(<{7}|={7}|>{7})'; then
    jq -n '{hookSpecificOutput:{permissionDecision:"deny",permissionDecisionReason:"Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."}}' 2>/dev/null
    exit 0
  fi
fi
```

**Review corrections applied:**

- Uses `hookSpecificOutput.permissionDecision/permissionDecisionReason` JSON schema (matching Guards 1-3), not the incorrect `decision/block` from the original plan
- Includes `git merge --continue` in the command pattern (Gap 4)
- Redirects stderr on git diff (TR5)
- Uses `jq -n` for JSON output (matches existing guard patterns)

**Cross-reference:** Constitution.md line 83 already has an advisory grep instruction. Add parenthetical: "(enforced by guardrails.sh Guard 4)"

### 3. Documentation cleanup

- **Constitution.md line 83:** Add "(enforced by guardrails.sh Guard 4)" after existing conflict marker grep instruction
- **Merge-pr SKILL.md Phase 1.2:** Change "Commit or stash" to "Commit changes" (removes stash reference per AGENTS.md hard rule). Pre-existing issue surfaced by SpecFlow.

## Deferred (cut by plan review)

- **Phase 5.5 pre-push sync in /ship** — Pre-merge hook + Phase 6.5 already provide two sync layers. A third is redundant and duplicates conflict resolution logic from merge-pr.
- **Worktree refresh command** — Wraps `git fetch origin main && git merge origin/main` (two commands) in a script function. Insufficient justification for the added surface area.
- **Hook rename** — `pre-merge-rebase.sh` edited in place. Name is slightly misleading but functional. Avoids settings.json churn.

## Rollback

- **Strategy change:** Revert AGENTS.md and constitution.md text, revert hook edits. The merge strategy is already what the skills use, so reverting to "rebase" text would re-introduce the contradiction.
- **Conflict marker guard:** Remove Guard 4 from `guardrails.sh`. No side effects.

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

Given the agent runs "git merge --continue" with conflict markers staged
Then guardrails.sh blocks (matches merge --continue pattern)
```

### Pre-merge hook (updated to merge strategy)

```
Given a feature branch that is up-to-date with origin/main
When the agent runs "gh pr merge"
Then pre-merge-rebase.sh skips merge and allows

Given a feature branch behind origin/main with no conflicts
When the agent runs "gh pr merge"
Then pre-merge-rebase.sh merges, pushes (regular push), and allows

Given a feature branch behind origin/main with conflicts
When the agent runs "gh pr merge"
Then pre-merge-rebase.sh runs git merge --abort and denies with conflict file list

Given no network access
When the agent runs "gh pr merge"
Then pre-merge-rebase.sh fails open (allows)
```
