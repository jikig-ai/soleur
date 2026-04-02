---
title: "fix: pre-merge hook false positive in bare repo worktree setups"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix: pre-merge hook false positive in bare repo worktree setups

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 3 (Proposed Solution, MVP, Test Scenarios)

### Key Improvements

1. Fixed `set -e` interaction in MVP code: bare `git diff ...; DIFF_EXIT=$?` would terminate the script before `$?` capture under `set -eo pipefail`. Changed to `DIFF_EXIT=0; git ... || DIFF_EXIT=$?` pattern that correctly captures all exit codes without triggering errexit.
2. Verified `git diff --quiet` exit code semantics empirically: 0 = clean, 1 = dirty, 128 = bare repo/no work tree, 129 = invalid usage. The `$? -eq 1` check is precise and correct.
3. Simplified test case to reuse existing `remoteDir` bare repo fixture instead of creating a new one (per reviewer feedback).

### New Considerations Discovered

- The `|| VAR=$?` pattern is already documented in `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` as the canonical approach for capturing exit codes under `set -e`. The learning's audit checklist item: "Commands whose failure is intentional (e.g., `grep`, `git diff`) must use `|| true` or `if !`" applies directly here -- `git diff --quiet` is intentionally non-zero on dirty trees.
- `git diff --quiet` returns exit 129 on invalid flags (e.g., `--invalid-flag`). The `$? -eq 1` check correctly ignores this too, failing open on usage errors.
- The `2>/dev/null` on both git diff commands suppresses stderr but does NOT affect the exit code. The `||` captures the actual exit code from git, not from the stderr redirection.

## Overview

The `pre-merge-rebase.sh` PreToolUse hook blocks `gh pr merge` with "BLOCKED: Uncommitted changes detected" in bare repo worktree setups when the working tree is actually clean. The root cause is that `git diff --quiet HEAD` returns exit code 128 ("this operation must be run in a work tree") when run against the bare repo root, and the hook treats any non-zero exit as "uncommitted changes."

## Problem Statement

Lines 106-107 of `.claude/hooks/pre-merge-rebase.sh`:

```bash
if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
```

When `$WORK_DIR` resolves to the bare repo root (because Claude Code's Bash tool CWD is the bare repo, not the worktree), `git diff --quiet HEAD` returns exit code 128. The `! ...` negation treats any non-zero exit (including 128) as truthy, so the hook incorrectly reports "uncommitted changes."

### When does this trigger?

There are two scenarios:

1. **Pre-#1389 (now fixed):** Before PR #1389, `core.bare=true` bled from the shared `.git/config` into all worktrees. This made `git diff --quiet HEAD` fail with exit 128 even inside worktrees. PR #1389 fixed the config bleed, but the hook's flawed logic remains.

2. **Bare repo root as CWD:** If the agent runs `gh pr merge` while the Bash tool's CWD is the bare repo root (not a worktree), the `.cwd` field in hook input points to the bare root. From the bare root, `rev-parse --abbrev-ref HEAD` returns `main`, so the hook normally exits early at line 51. However, if the bare repo's HEAD is not on main (edge case: manual `git symbolic-ref HEAD` change), the diff check is reached and fails with 128.

3. **Future config regression:** If `core.bare=true` bleeds into worktrees again (config regression), the same false positive returns. The hook should be robust against this.

### Impact

Cannot use `gh pr merge` from bare repo context. Workaround requires using the GraphQL API directly:

```bash
gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: { pullRequestId: "...", mergeMethod: SQUASH }) { ... } }'
```

## Proposed Solution

Distinguish between "dirty working tree" (exit code 1) and "not a working tree / other error" (exit code 128 or other non-zero, non-1 exit codes). The fix is minimal: capture the exit code and check specifically for exit 1 (the only code that means "uncommitted changes").

### Approach: Check exit codes explicitly

Replace the boolean negation pattern with explicit exit code capture:

```bash
# Check for uncommitted changes (tracked files only)
# Exit codes: 0 = clean, 1 = dirty, 128 = not a work tree (bare repo)
# Only block on exit 1 (genuinely dirty). Fail open on 128+ (bare repo context).
# Uses || DIFF_EXIT=$? pattern to prevent set -e from terminating the script
# on non-zero exit before $? can be captured.
DIFF_EXIT=0
git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || DIFF_EXIT=$?
CACHED_EXIT=0
git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null || CACHED_EXIT=$?

if [[ $DIFF_EXIT -eq 1 ]] || [[ $CACHED_EXIT -eq 1 ]]; then
  # Genuinely dirty working tree -- block merge
  jq -n '{...deny JSON...}'
  exit 0
fi
# Exit 0 (clean) or 128+ (not a work tree / error) -- proceed
```

### Research Insights: `git diff --quiet` exit code semantics

Verified empirically (2026-04-02):

| Exit Code | Meaning | Example Trigger |
|-----------|---------|-----------------|
| 0 | Clean working tree | No changes |
| 1 | Dirty working tree | Modified tracked files |
| 128 | Not a work tree | Bare repo, `core.bare=true` bleed |
| 129 | Invalid usage | Bad flag, e.g., `--invalid-flag` |

The `$? -eq 1` check is the most precise gate: it blocks only on genuinely dirty trees and fails open on every other exit code. This aligns with the hook's existing fail-open philosophy for infrastructure errors.

### Research Insights: `set -e` and exit code capture

Per `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`, under `set -e` (errexit), a bare command that exits non-zero terminates the script before `$?` can be captured on the next line. The `|| VAR=$?` pattern prevents this because `||` makes the compound command always succeed:

```bash
# WRONG under set -e: script terminates on exit 128 before $? capture
git diff --quiet HEAD 2>/dev/null
DIFF_EXIT=$?  # never reached if git exits 128

# CORRECT under set -e: || captures exit code without triggering errexit
DIFF_EXIT=0
git diff --quiet HEAD 2>/dev/null || DIFF_EXIT=$?
```

The existing code's `if ! git diff ...` pattern was accidentally safe under `set -e` because the `!` + `if` consumes the exit code as a conditional. The proposed fix intentionally uses `||` to achieve the same safety while enabling precise exit code discrimination.

### Why not resolve the worktree path instead?

The issue suggests an alternative: "detect bare repos and resolve the correct worktree path from the PR's branch before running diff checks." This is more complex and fragile:

- Resolving the worktree from a PR branch name requires parsing `git worktree list`, matching branch names, and handling edge cases (multiple worktrees, deleted worktrees)
- The hook's `.cwd` field is the authoritative source of "where the agent is working" -- overriding it with a derived path could cause unexpected behavior
- The exit-code approach is simpler, covers all edge cases, and is consistent with the hook's existing fail-open philosophy

### Why not add bare repo detection?

Adding `git rev-parse --is-bare-repository` before the diff check would work but is redundant with the exit-code approach. Exit code 128 already tells us "this is not a work tree" -- we do not need a separate bare-repo check. The exit-code fix is more general: it also handles any other non-1 exit code from `git diff` (e.g., config errors, corrupt index).

## Technical Considerations

### Other git commands in the hook

The `git diff` commands are the primary failure point, but other commands also run with `$WORK_DIR`:

| Command | Line | Bare repo behavior | Risk |
|---------|------|-------------------|------|
| `git rev-parse --git-dir` | 42 | Returns `.git` -- works | None |
| `git rev-parse --abbrev-ref HEAD` | 47 | Returns `main` -- works | None (triggers main skip) |
| `git diff --quiet HEAD` | 106 | Exit 128 -- BUG | **This fix** |
| `git diff --cached --quiet` | 107 | Exit 128 -- BUG | **This fix** |
| `git fetch origin main` | 119 | Works (bare repos can fetch) | None |
| `git merge-base HEAD origin/main` | 125 | Works | None |
| `git merge origin/main` | 141 | Exit 128 (no work tree) | Handled by existing fail-open on merge error |

The merge command (line 141) would also fail with 128 in a bare repo, but this is correctly handled: the hook captures the error and returns a deny with "Merge of origin/main failed." The deny message could be improved to distinguish "not a work tree" from "merge conflict," but that is a separate enhancement.

### Interaction with review evidence gate (Guard 6)

The review evidence gate runs before the diff check. It uses `git log` and `grep` commands that work in bare repos. If Guard 6 denies (no review evidence), the diff check is never reached. This means the false positive only triggers when:

1. Review evidence exists (Guard 6 passes)
2. Branch is not main/master (line 51 passes)
3. Not detached HEAD (line 99 passes)
4. `$WORK_DIR` is bare repo or has `core.bare=true` bleed

### Test plan alignment

The existing test suite (`test/pre-merge-rebase.test.ts`) creates regular (non-bare) repos for testing. A new test case is needed that creates a bare repo setup to verify the fix.

## Acceptance Criteria

- [x] `git diff --quiet HEAD` exit code 128 (bare repo) does NOT trigger "uncommitted changes" deny
- [x] `git diff --quiet HEAD` exit code 1 (genuinely dirty) still triggers deny
- [x] `git diff --cached --quiet` exit code 128 does NOT trigger deny
- [x] `git diff --cached --quiet` exit code 1 still triggers deny
- [x] Exit code 0 (clean) passes through as before
- [x] New test case: bare repo `.cwd` with non-main HEAD passes diff check
- [x] Existing test suite passes unchanged

## Test Scenarios

- Given a bare repo as `$WORK_DIR` where `rev-parse --abbrev-ref HEAD` returns a non-main branch, when `gh pr merge` is intercepted, then the diff check does NOT block with "uncommitted changes" (exit 128 is treated as fail-open, not as dirty)
- Given a worktree with `core.bare=true` bleed (simulated), when `gh pr merge` is intercepted, then the diff check does NOT block with "uncommitted changes"
- Given a worktree with genuinely dirty tracked files, when `gh pr merge` is intercepted, then the diff check blocks with "Uncommitted changes detected" (exit 1 is still caught)
- Given a worktree with staged but uncommitted changes, when `gh pr merge` is intercepted, then the diff check blocks
- Given a clean worktree (exit 0 from both diff commands), when `gh pr merge` is intercepted, then the diff check passes through

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## MVP

### `.claude/hooks/pre-merge-rebase.sh` (lines 104-116, replacement)

Replace the current uncommitted-changes check:

```bash
# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with merge and should not block it)
if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit before merging."
    }
  }'
  exit 0
fi
```

With:

```bash
# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with merge and should not block it).
# Exit codes: 0 = clean, 1 = dirty, 128 = not a work tree (bare repo).
# Only block on exit 1 (genuinely dirty). Fail open on 128+ to avoid
# false positives in bare repo worktree setups (#1386).
# Uses || VAR=$? to capture exit code without triggering set -e.
DIFF_EXIT=0
git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || DIFF_EXIT=$?
CACHED_EXIT=0
git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null || CACHED_EXIT=$?

if [[ $DIFF_EXIT -eq 1 ]] || [[ $CACHED_EXIT -eq 1 ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit before merging."
    }
  }'
  exit 0
fi
```

### `test/pre-merge-rebase.test.ts` (new test case)

Add a test case that reuses the existing `remoteDir` (already a bare repo in the test fixture) with its HEAD changed to a non-main branch, verifying the hook does not false-positive on the diff check:

```typescript
test("bare repo cwd does not false-positive on uncommitted changes", async () => {
  // remoteDir is already a bare repo (created in beforeAll).
  // Change HEAD to a non-main branch so the hook doesn't skip at the
  // main/master early-exit check (line 51).
  spawnChecked(
    ["git", "symbolic-ref", "HEAD", "refs/heads/test-feature"],
    { cwd: remoteDir }
  );

  try {
    // The hook should NOT block with "uncommitted changes" --
    // exit 128 from diff in bare repo should be treated as fail-open
    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", remoteDir)
    );

    expect(result.exitCode).toBe(0);
    // Should NOT contain "Uncommitted changes" deny
    if (result.stdout) {
      const output = JSON.parse(result.stdout);
      if (output.hookSpecificOutput?.permissionDecision === "deny") {
        expect(output.hookSpecificOutput.permissionDecisionReason).not.toContain(
          "Uncommitted changes"
        );
      }
    }
  } finally {
    // Restore HEAD to main for other tests
    spawnChecked(
      ["git", "symbolic-ref", "HEAD", "refs/heads/main"],
      { cwd: remoteDir }
    );
  }
});
```

## Files to Modify

| File | Change |
|------|--------|
| `.claude/hooks/pre-merge-rebase.sh` | Replace boolean diff check with exit-code-aware check (lines 104-116) |
| `test/pre-merge-rebase.test.ts` | Add bare repo false-positive test case |

## References

- Issue: #1386
- Related PR: #1389 (core.bare bleed fix)
- Learning: `knowledge-base/project/learnings/2026-04-02-bare-repo-config-bleed-worktrees.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-worktree-manager-bare-repo-false-positive.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md`
- Original plan: `knowledge-base/project/plans/2026-03-03-feat-pre-merge-hooks-auto-rebase-plan.md`
- Hook source: `.claude/hooks/pre-merge-rebase.sh`
- Test suite: `test/pre-merge-rebase.test.ts`
