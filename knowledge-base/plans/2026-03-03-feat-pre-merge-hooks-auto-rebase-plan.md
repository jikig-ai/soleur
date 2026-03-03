---
title: "feat: implement pre-merge hooks for auto-rebase against main"
type: feat
date: 2026-03-03
version_bump: PATCH
---

# feat: implement pre-merge hooks for auto-rebase against main

Merge conflicts from stale branches and version bumps are the most frequent friction source across 226 sessions (14+ incidents). A PreToolUse hook that intercepts `gh pr merge` commands and auto-rebases against `origin/main` before the merge proceeds would eliminate the most common merge failure pattern: the branch is behind main, `gh pr merge --squash --auto` queues, CI passes, but GitHub refuses to merge because the branch has conflicts with main that were not visible at push time.

## Enhancement Summary

The issue (#390) proposes two hooks:

1. **Pre-merge rebase hook** -- intercept `gh pr merge` and auto-rebase against main first
2. **Post-edit compound reminder** -- remind the agent to run compound after edits

After analyzing the codebase and the Claude Code hooks API, the scope should be narrowed:

- The **pre-merge rebase hook** is the high-value target. It addresses a real, measured friction source (14+ incidents).
- The **post-edit compound reminder** is low value and potentially harmful. Compound should run once before the commit, not after every edit. A PostToolUse reminder on every `Edit` call would spam context and distract the agent. The compound gate is already enforced by AGENTS.md hard rules and the ship/merge-pr skill instructions. A reminder on every edit inverts the intended workflow (compound is a batch operation, not a per-edit check).

## Non-goals

- Changing the compound workflow or adding PostToolUse edit reminders (addressed above)
- Modifying the ship or merge-pr skill instructions (they already handle the correct flow)
- Adding hooks that modify the `gh pr merge` command itself via `updatedInput` (the rebase is a precondition, not a command transformation)
- Handling merge conflicts automatically (if rebase fails, the hook blocks and the agent must resolve manually)

## Proposed Solution

Add a new PreToolUse hook script `.claude/hooks/pre-merge-rebase.sh` that:

1. Intercepts Bash commands matching `gh pr merge`
2. Runs `git fetch origin main && git rebase origin/main`
3. If rebase succeeds: allows the merge to proceed (exit 0, no JSON output)
4. If rebase fails: blocks the merge with a clear error message via `permissionDecision: "deny"`

### Why a hook script, not inline in settings.json

The issue proposes a `"command"` string directly in settings.json. This does not work for the real use case because:

- The hook must read JSON from stdin to extract `tool_input.command`
- The hook must do conditional matching (only `gh pr merge`, not all Bash commands)
- The hook must handle rebase failure gracefully and return structured JSON
- Error handling requires multi-line logic that cannot be a single shell command

### Why PreToolUse and not a skill instruction

The constitution already states: "Prefer hook-based enforcement over documentation-only rules for agent discipline -- PreToolUse hooks make violations impossible rather than aspirational." The ship and merge-pr skills already instruct agents to rebase, but agents skip these steps under complex reasoning chains. A hook makes the rebase automatic and unavoidable.

### Architecture Decision: Separate script vs. adding to guardrails.sh

Two options:

**Option A: New script `pre-merge-rebase.sh`** (recommended)
- Single responsibility: guardrails.sh blocks dangerous commands; pre-merge-rebase.sh automates a workflow step
- The rebase hook has side effects (modifies the working tree); guardrails.sh is pure inspection
- Easier to test and debug independently
- Follows the pattern established by `worktree-write-guard.sh` (separate concerns)

**Option B: Add a guard to `guardrails.sh`**
- Fewer hook entries in settings.json
- But violates the single-responsibility principle: guardrails.sh is a gatekeeping script (block/allow), not a workflow automation script (fetch/rebase)

### Hook Registration

Add to `.claude/settings.json` under the existing `PreToolUse` hooks array:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/pre-merge-rebase.sh"
    }
  ]
}
```

This means the matcher fires on every Bash command. The script itself does the `gh pr merge` substring check and exits 0 immediately for non-matching commands. This is the same pattern used by `guardrails.sh`.

### SpecFlow Analysis

**Edge case 1: Rebase succeeds but creates new commits that need pushing**
After a successful rebase, the local branch has diverged from the remote. The script must `git push --force-with-lease` after rebase to update the remote branch before `gh pr merge --auto` can succeed. Without this push, the auto-merge queues on the old (pre-rebase) commit SHA, and GitHub may reject it or merge the wrong state.

**Edge case 2: Already up-to-date**
If the branch is already ahead of or at `origin/main`, `git rebase origin/main` is a no-op. The script should detect this and skip the force-push.

**Edge case 3: Rebase conflict**
If rebase fails (exit code non-zero), the script must:
1. Run `git rebase --abort` to restore the working tree
2. Return `permissionDecision: "deny"` with a clear message
3. The agent then needs to resolve the conflict manually (or the user does)

**Edge case 4: Dirty working tree**
If there are uncommitted changes, `git rebase` will refuse to start. The script should check for this and block with a clear message.

**Edge case 5: Not in a git repository or worktree**
If the hook runs outside a git repo (unlikely but possible), all git commands fail. The script should handle this gracefully and allow the merge to proceed (fail-open for non-git contexts).

**Edge case 6: Network failure on fetch**
`git fetch origin main` can fail due to network issues. The script should fail-open: warn but allow the merge to proceed. The merge will fail on GitHub's side if there are actual conflicts, which is a safe degradation.

**Edge case 7: gh pr merge without --auto**
The script should match any `gh pr merge` command regardless of flags. The rebase is valuable whether the merge is immediate or queued.

**Edge case 8: Chained commands**
Like Guard 1 in guardrails.sh, the match must work for `gh pr merge` at any position in a chained command (`&& gh pr merge`, `; gh pr merge`, etc.). Use the same `(^|&&|\|\||;)` pattern.

## Acceptance Criteria

- [ ] PreToolUse hook script `.claude/hooks/pre-merge-rebase.sh` created
- [ ] Hook registered in `.claude/settings.json` under `PreToolUse`
- [ ] On `gh pr merge`, auto-fetches and rebases against `origin/main`
- [ ] On successful rebase with new commits, force-pushes with lease before allowing merge
- [ ] On rebase conflict, blocks the merge with `permissionDecision: "deny"` and aborts the rebase
- [ ] On already up-to-date branch, allows merge without force-push
- [ ] On dirty working tree, blocks with clear error message
- [ ] On network failure during fetch, warns and allows merge to proceed (fail-open)
- [ ] Non-`gh pr merge` Bash commands pass through with no delay (early exit)
- [ ] Script follows shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`, `local` variables
- [ ] Learning documented about the hook pattern for pre-condition automation (vs. guardrails for blocking)
- [ ] Constitution updated with principle about pre-merge hooks

## Test Scenarios

- Given a branch that is behind `origin/main` by 3 commits, when `gh pr merge 123 --squash --auto` is intercepted, then `git fetch && git rebase origin/main` runs, `git push --force-with-lease` runs, and the merge command proceeds
- Given a branch that is already at `origin/main`, when `gh pr merge` is intercepted, then no rebase or push occurs, and the merge command proceeds immediately
- Given a branch with uncommitted changes, when `gh pr merge` is intercepted, then the hook returns `permissionDecision: "deny"` with message "Uncommitted changes -- commit or stash before merging"
- Given a branch with conflicts against `origin/main`, when `gh pr merge` is intercepted, then the rebase fails, `git rebase --abort` runs, and the hook returns `permissionDecision: "deny"` with message listing the conflicting files
- Given network is down, when `gh pr merge` is intercepted and `git fetch` fails, then the hook warns on stderr and allows the merge to proceed
- Given a chained command `git add -A && gh pr merge 123 --squash --auto`, when the hook intercepts the Bash call, then the `gh pr merge` substring is detected and the rebase runs
- Given a non-merge command like `gh pr view 123`, when the hook runs, then it exits 0 immediately with no side effects

## MVP

### `.claude/hooks/pre-merge-rebase.sh`

```bash
#!/usr/bin/env bash
# PreToolUse hook: auto-rebase against origin/main before gh pr merge.
# Ensures the branch is current before merge to prevent post-queue conflicts.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands
if ! echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge'; then
  exit 0
fi

# Determine the working directory from the command
GIT_DIR=""
if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
  GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
fi
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [[ -n "$GIT_DIR" ]] && [[ -d "$GIT_DIR" ]]; then
  WORK_DIR="$GIT_DIR"
elif [[ -n "$HOOK_CWD" ]] && [[ -d "$HOOK_CWD" ]]; then
  WORK_DIR="$HOOK_CWD"
else
  # Not in a recognizable directory -- fail open
  exit 0
fi

# Check for uncommitted changes
if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit or stash before merging."
    }
  }'
  exit 0
fi

# Fetch latest main -- fail open on network error
if ! git -C "$WORK_DIR" fetch origin main 2>/dev/null; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

# Check if rebase is needed
LOCAL_HEAD=$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null)
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null)

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no rebase needed
  exit 0
fi

# Attempt rebase
if ! git -C "$WORK_DIR" rebase origin/main 2>/dev/null; then
  # Rebase failed -- abort and block
  local_conflicts=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" rebase --abort 2>/dev/null || true
  jq -n --arg files "$local_conflicts" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Rebase against origin/main failed. Conflicting files: " + $files + ". Resolve conflicts manually before merging.")
    }
  }'
  exit 0
fi

# Rebase succeeded -- force push to update the remote branch
if ! git -C "$WORK_DIR" push --force-with-lease 2>/dev/null; then
  echo "Warning: Rebase succeeded but force-push failed. The merge may use stale commits." >&2
fi

# Allow the merge to proceed
exit 0
```

### `.claude/settings.json` (additions to existing PreToolUse array)

Add this entry to the existing `hooks.PreToolUse` array:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/pre-merge-rebase.sh"
    }
  ]
}
```

## Files to Modify

| File | Change |
|------|--------|
| `.claude/hooks/pre-merge-rebase.sh` | New file: PreToolUse hook script for auto-rebase |
| `.claude/settings.json` | Add PreToolUse hook entry for pre-merge-rebase |

## References

- Issue: #390
- Claude Code hooks API: https://code.claude.com/docs/en/hooks
- Existing hook pattern: `.claude/hooks/guardrails.sh` (command interception)
- Existing hook pattern: `.claude/hooks/worktree-write-guard.sh` (file path interception)
- Learning: `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` (hook > documentation)
- Learning: `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md` (chain operator matching)
- Learning: `knowledge-base/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md` (single-pattern guards)
- Learning: `knowledge-base/learnings/logic-errors/2026-02-17-parallel-agents-on-main-cause-conflicts.md` (stale branch conflicts)
- Learning: `knowledge-base/learnings/integration-issues/2026-02-17-truncated-changelog-during-rebase-conflict-resolution.md` (rebase conflict risk)
- Related plan: `knowledge-base/plans/2026-02-24-feat-pull-latest-after-merge-plan.md` (post-merge pull-latest)
- Constitution: "Prefer hook-based enforcement over documentation-only rules for agent discipline"
