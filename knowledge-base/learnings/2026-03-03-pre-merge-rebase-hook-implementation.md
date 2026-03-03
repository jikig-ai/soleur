# Learning: Pre-Merge Rebase Hook Implementation

## Problem
Stale feature branches caused merge conflicts after `gh pr merge` queued auto-merge. Across 226 sessions, 14+ incidents required manual intervention when the merge queue rejected branches that were behind main. The root cause: no automated check ensured branches were current before merge.

## Solution
Created a Claude Code PreToolUse hook (`.claude/hooks/pre-merge-rebase.sh`) that intercepts `gh pr merge` commands, auto-rebases against `origin/main`, and force-pushes before allowing the merge to proceed.

Key implementation decisions:
- **Fail-open on infrastructure errors** (network, non-git context), **fail-closed on logical errors** (conflicts, dirty tree, push failure)
- Uses `hookSpecificOutput` JSON format with `permissionDecision: "deny"` to block merge on logical errors
- `git push --force-with-lease --force-if-includes origin HEAD` for safe force push
- Captures conflict files BEFORE `git rebase --abort` (abort clears conflict state)
- Chain operator pattern `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` catches chained commands with word boundary

## Key Insight
Git commands that produce output to stdout (like `git rebase` printing "Auto-merging file.txt") will corrupt JSON output from hooks. Always redirect both stdout AND stderr (`>/dev/null 2>&1`) on git commands whose output you don't need, especially in scripts that produce structured JSON on stdout.

Additionally, `git push --force-with-lease` without specifying `origin HEAD` requires upstream tracking configuration. In test environments where branches are pushed with `git push origin branch-name` (no `-u`), the push will fail silently. Always specify the remote and refspec explicitly.

## Session Errors
1. **Rebase stdout corrupting JSON**: `git rebase origin/main 2>/dev/null` still outputs "Auto-merging" messages to stdout, mixing with jq JSON output. Fixed: `>/dev/null 2>&1`.
2. **Push without upstream tracking**: `git push --force-with-lease --force-if-includes` without `origin HEAD` requires `-u` tracking. Tests failed because setup used `git push origin branch` (no `-u`). Fixed: explicit `origin HEAD`.
3. **chmod ineffective for local bare repos**: `chmodSync(remoteDir, 0o444)` didn't prevent pushes to local bare repos. Fixed: `git remote set-url --push origin /nonexistent-remote` to split fetch/push URLs.
4. **Wrong CWD for test execution**: Running tests from repo root instead of worktree directory caused file-not-found errors.

## Tags
category: integration-issues
module: claude-hooks
