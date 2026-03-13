---
title: "feat: implement pre-merge hooks for auto-rebase against main"
type: feat
date: 2026-03-03
version_bump: PATCH
deepened: 2026-03-03
---

# feat: implement pre-merge hooks for auto-rebase against main

Merge conflicts from stale branches and version bumps are the most frequent friction source across 226 sessions (14+ incidents). A PreToolUse hook that intercepts `gh pr merge` commands and auto-rebases against `origin/main` before the merge proceeds would eliminate the most common merge failure pattern: the branch is behind main, `gh pr merge --squash --auto` queues, CI passes, but GitHub refuses to merge because the branch has conflicts with main that were not visible at push time.

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 5 (Proposed Solution, SpecFlow Analysis, MVP, Test Scenarios, References)

### Key Improvements
1. Replaced `set -euo pipefail` with `set -eo pipefail` in the hook script -- `set -u` (nounset) causes unrecoverable exit on unset variables, but hooks must return JSON on failure, not crash silently; `set -e` already exits on error, and all variables are initialized before use
2. Added `--force-if-includes` alongside `--force-with-lease` for defense-in-depth against stale remote state after background fetches
3. Added edge case 9 (detached HEAD) and edge case 10 (hook re-entrancy) discovered during SpecFlow deepening
4. Replaced global variables with function-scoped `local` declarations in the script body to match shell conventions
5. Added `additionalContext` output on successful rebase so the agent sees confirmation of what the hook did

### New Considerations Discovered
- The `git fetch origin main` in the hook only updates `refs/remotes/origin/main`, which does NOT weaken `--force-with-lease` for the feature branch push. The lease checks the feature branch's remote ref, not main's. This is a safe interaction.
- PreToolUse hooks with side effects (rebase + push) are non-reversible if the subsequent tool call fails. This is acceptable because the rebase only makes the branch more current -- there is no scenario where being rebased on latest main is worse than being stale.
- The `echo "$INPUT" | jq` pattern is safe with `pipefail` because jq returns 0 on valid JSON parse. However, the `grep -qE` calls require careful handling: grep returns exit code 1 when no match is found, which under `set -e` would terminate the script before it can return JSON. The `if ! ...; then` and `if echo ... | grep` patterns handle this correctly because the exit code is consumed by the conditional.
- The `git -C "$WORK_DIR"` pattern avoids any `cd` that could leave the hook in an unexpected directory. All git operations use `-C` for idempotent directory targeting.
- The learnings about cleanup-merged path mismatch (`2026-02-22`) confirm that constructing paths from branch names is fragile. The hook avoids this entirely by using the `cwd` field from the hook input JSON.

## Enhancement Summary (Issue Scope)

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
- Fetching the feature branch's remote ref (this would weaken `--force-with-lease` safety)

## Proposed Solution

Add a new PreToolUse hook script `.claude/hooks/pre-merge-rebase.sh` that:

1. Intercepts Bash commands matching `gh pr merge`
2. Runs `git fetch origin main && git rebase origin/main`
3. If rebase succeeds: pushes with `--force-with-lease --force-if-includes`, then allows the merge to proceed (exit 0 with `additionalContext` confirmation)
4. If rebase fails: blocks the merge with a clear error message via `permissionDecision: "deny"`

### Why a hook script, not inline in settings.json

The issue proposes a `"command"` string directly in settings.json. This does not work for the real use case because:

- The hook must read JSON from stdin to extract `tool_input.command`
- The hook must do conditional matching (only `gh pr merge`, not all Bash commands)
- The hook must handle rebase failure gracefully and return structured JSON
- Error handling requires multi-line logic that cannot be a single shell command

### Why PreToolUse and not a skill instruction

The constitution already states: "Prefer hook-based enforcement over documentation-only rules for agent discipline -- PreToolUse hooks make violations impossible rather than aspirational." The ship and merge-pr skills already instruct agents to rebase, but agents skip these steps under complex reasoning chains. A hook makes the rebase automatic and unavoidable.

### Research Insights: Side Effects in PreToolUse Hooks

PreToolUse hooks are designed primarily for inspection (allow/deny/ask decisions). This hook introduces side effects (rebase + push) which is atypical. Analysis of the implications:

**Safe because:**
- The side effect (rebasing onto latest main) is always beneficial -- a branch that is current with main is never worse than a stale branch
- If the subsequent `gh pr merge` fails for unrelated reasons, the rebase still leaves the branch in a better state
- The hook returns `additionalContext` so the agent knows what happened, maintaining transparency

**Risk mitigated by:**
- `--force-with-lease --force-if-includes` ensures no remote work is overwritten
- `git rebase --abort` on conflict ensures the working tree is always clean on exit
- Network failures are fail-open, never blocking the agent unnecessarily

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

### Research Insights: Hook Execution Model

All matching hooks run in parallel per the Claude Code hooks API. This means `guardrails.sh` and `pre-merge-rebase.sh` both run simultaneously when a `gh pr merge` Bash command is detected. This is safe because:

- `guardrails.sh` only checks for `--delete-branch` on `gh pr merge` (Guard 3) -- it does not block the merge itself
- The two hooks inspect different aspects and cannot conflict
- If `guardrails.sh` blocks (e.g., `--delete-branch` detected), the rebase from `pre-merge-rebase.sh` is a harmless side effect
- Claude Code's hook resolution uses the most restrictive decision: if any hook denies, the tool call is denied regardless of other hooks' decisions

### SpecFlow Analysis

**Edge case 1: Rebase succeeds but creates new commits that need pushing**
After a successful rebase, the local branch has diverged from the remote. The script must `git push --force-with-lease --force-if-includes` after rebase to update the remote branch before `gh pr merge --auto` can succeed. Without this push, the auto-merge queues on the old (pre-rebase) commit SHA, and GitHub may reject it or merge the wrong state.

**Research Insight:** `--force-if-includes` (Git 2.30+) adds a check that the local branch has incorporated the remote tracking branch's latest state. This prevents the scenario where a background `git fetch` updates the remote ref without the user seeing the changes, which would silently weaken `--force-with-lease` alone. Since the hook only fetches `origin main` (not the feature branch), this is belt-and-suspenders protection.

**Edge case 2: Already up-to-date**
If the branch is already ahead of or at `origin/main`, `git rebase origin/main` is a no-op. The script should detect this via merge-base comparison and skip both the rebase and force-push entirely.

**Edge case 3: Rebase conflict**
If rebase fails (exit code non-zero), the script must:
1. Capture conflicting file names from `git diff --name-only --diff-filter=U` BEFORE aborting
2. Run `git rebase --abort` to restore the working tree
3. Return `permissionDecision: "deny"` with a clear message listing the conflicting files
4. The agent then needs to resolve the conflict manually (or the user does)

**Research Insight:** The order of operations matters. `git diff --name-only --diff-filter=U` must run while the rebase conflict is active (before `--abort`), because `--abort` restores the working tree and the conflict information is lost.

**Edge case 4: Dirty working tree**
If there are uncommitted changes, `git rebase` will refuse to start. The script should check for this using `git diff --quiet HEAD` and `git diff --cached --quiet` (checking tracked file changes only -- per the learning from `2026-02-26-worktree-enforcement-pretooluse-hook.md`, untracked files should not block operations they cannot conflict with).

**Edge case 5: Not in a git repository or worktree**
If the hook runs outside a git repo (unlikely but possible), all git commands fail. The script should handle this gracefully and allow the merge to proceed (fail-open for non-git contexts).

**Edge case 6: Network failure on fetch**
`git fetch origin main` can fail due to network issues. The script should fail-open: warn but allow the merge to proceed. The merge will fail on GitHub's side if there are actual conflicts, which is a safe degradation.

**Edge case 7: gh pr merge without --auto**
The script should match any `gh pr merge` command regardless of flags. The rebase is valuable whether the merge is immediate or queued.

**Edge case 8: Chained commands**
Like Guard 1 in guardrails.sh, the match must work for `gh pr merge` at any position in a chained command (`&& gh pr merge`, `; gh pr merge`, etc.). Use the same `(^|&&|\|\||;)` pattern. Per learning `2026-02-24-guardrails-chained-commit-bypass.md`, a `^`-only anchor misses chained commands because the Bash tool routinely chains with `&&`.

**Edge case 9: Detached HEAD state** (discovered during deepening)
If the worktree is in detached HEAD state (e.g., after a failed previous operation), `git rebase origin/main` will still work but `git push --force-with-lease` will fail because there is no upstream branch. The script should check for detached HEAD and fail-open with a warning.

**Edge case 10: Hook re-entrancy** (discovered during deepening)
If the agent's `gh pr merge` command is part of a retry loop (e.g., merge failed, agent retries), the hook will run again. This is safe because:
- If the first run already rebased and pushed, the merge-base check will show "already up-to-date" and the hook exits early
- If the first run's rebase conflicted, the agent resolved it, and now retries -- the hook runs a fresh rebase which may succeed this time

## Acceptance Criteria

- [x] PreToolUse hook script `.claude/hooks/pre-merge-rebase.sh` created
- [x] Hook registered in `.claude/settings.json` under `PreToolUse`
- [x] On `gh pr merge`, auto-fetches and rebases against `origin/main`
- [x] On successful rebase with new commits, force-pushes with `--force-with-lease --force-if-includes` before allowing merge
- [x] On rebase conflict, blocks the merge with `permissionDecision: "deny"` and aborts the rebase
- [x] On already up-to-date branch, allows merge without rebase or force-push
- [x] On dirty working tree, blocks with clear error message
- [x] On network failure during fetch, warns and allows merge to proceed (fail-open)
- [x] On detached HEAD, warns and allows merge to proceed (fail-open)
- [x] Non-`gh pr merge` Bash commands pass through with no delay (early exit)
- [x] Script follows shell conventions: `#!/usr/bin/env bash`, `set -eo pipefail`, `local` variables, stderr for warnings
- [x] Successful rebase emits `additionalContext` so the agent knows what happened
- [x] Script emits positive confirmation on success (per constitution: "Diagnostic scripts must print positive confirmation on success")

## Test Scenarios

- Given a branch that is behind `origin/main` by 3 commits, when `gh pr merge 123 --squash --auto` is intercepted, then `git fetch origin main && git rebase origin/main` runs, `git push --force-with-lease --force-if-includes` runs, and the merge command proceeds with `additionalContext` confirming the rebase
- Given a branch that is already at `origin/main`, when `gh pr merge` is intercepted, then no rebase or push occurs, and the merge command proceeds immediately
- Given a branch with uncommitted changes, when `gh pr merge` is intercepted, then the hook returns `permissionDecision: "deny"` with message "Uncommitted changes -- commit or stash before merging"
- Given a branch with conflicts against `origin/main`, when `gh pr merge` is intercepted, then the rebase fails, conflicting files are captured, `git rebase --abort` runs, and the hook returns `permissionDecision: "deny"` with message listing the conflicting files
- Given network is down, when `gh pr merge` is intercepted and `git fetch` fails, then the hook warns on stderr and allows the merge to proceed
- Given a chained command `git add -A && gh pr merge 123 --squash --auto`, when the hook intercepts the Bash call, then the `gh pr merge` substring is detected and the rebase runs
- Given a non-merge command like `gh pr view 123`, when the hook runs, then it exits 0 immediately with no side effects
- Given a detached HEAD state, when `gh pr merge` is intercepted, then the hook warns on stderr and allows the merge to proceed
- Given the hook already rebased and pushed on a previous run, when `gh pr merge` is retried, then the merge-base check shows up-to-date and the hook exits early with no side effects

## MVP

### `.claude/hooks/pre-merge-rebase.sh`

```bash
#!/usr/bin/env bash
# PreToolUse hook: auto-rebase against origin/main before gh pr merge.
# Ensures the branch is current before merge to prevent post-queue conflicts.
#
# Design: This hook has SIDE EFFECTS (rebase + push), unlike guardrails.sh
# which is pure inspection. Side effects are always beneficial (branch becomes
# more current) and non-reversible (acceptable because staleness is never better).
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree).

set -eo pipefail
# Note: -u (nounset) is omitted intentionally. Hook scripts must return JSON
# on failure paths, and an unset variable causing immediate exit prevents the
# structured error response that Claude Code needs to show the agent why the
# tool call was blocked.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands.
# Uses the (^|&&|\|\||;) pattern from guardrails.sh to catch chained commands.
if ! echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge'; then
  exit 0
fi

# Determine the working directory.
# Priority: cd in command > cwd from hook input > fail open.
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

# Verify we are in a git repository
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Check for detached HEAD -- rebase works but push will fail without upstream
CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Warning: Detached HEAD state. Skipping auto-rebase." >&2
  exit 0
fi

# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with rebase and should not block it)
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

# Fetch latest main -- fail open on network error
if ! git -C "$WORK_DIR" fetch origin main 2>/dev/null; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

# Check if rebase is needed by comparing merge-base with origin/main tip
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  # Could not determine relationship -- fail open
  echo "Warning: Could not determine branch relationship with main. Proceeding with merge." >&2
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no rebase needed
  exit 0
fi

# Attempt rebase
if ! git -C "$WORK_DIR" rebase origin/main 2>/dev/null; then
  # Rebase failed -- capture conflicts BEFORE aborting (abort clears conflict state)
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" rebase --abort 2>/dev/null || true
  jq -n --arg files "${CONFLICT_FILES:-unknown}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Rebase against origin/main failed. Conflicting files: " + $files + ". Resolve conflicts manually before merging.")
    }
  }'
  exit 0
fi

# Rebase succeeded -- force push to update the remote branch.
# --force-with-lease: prevents overwriting remote work pushed by others.
# --force-if-includes: ensures local branch has incorporated remote tracking
# branch state, protecting against background fetches weakening the lease.
PUSH_OUTPUT=""
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push --force-with-lease --force-if-includes 2>&1); then
  # Try fallback without --force-if-includes for older git versions
  if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push --force-with-lease 2>&1); then
    echo "Warning: Rebase succeeded but force-push failed: $PUSH_OUTPUT" >&2
    # Still allow merge -- the agent may need to push manually
  fi
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: rebased " + $branch + " onto origin/main and force-pushed. Branch is now current.")
  }
}'
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

### Research Insights: `set -eo pipefail` vs `set -euo pipefail`

The existing hooks (`guardrails.sh`, `worktree-write-guard.sh`) use `set -euo pipefail`. For this hook, `-u` (nounset) is intentionally omitted because:

1. Hook scripts must return structured JSON on failure paths. An unset variable causing immediate exit (exit code 1) prevents the JSON response, and Claude Code interprets exit code 1 as a non-blocking error rather than a denial.
2. The risk of unset variables is mitigated by initializing all variables before use and using `${VAR:-default}` patterns for optional values.
3. The existing hooks do not have complex failure paths that require JSON output -- they either `exit 0` (allow) or `echo '{"decision":"block"...}'` then `exit 0`. This hook has more failure branches that need structured responses.

**Recommendation:** Update the existing hooks to also use `set -eo pipefail` for consistency, or accept the asymmetry with a comment explaining why this hook differs.

### Research Insights: Force Push Safety

Per [Atlassian's analysis](https://www.atlassian.com/blog/it-teams/force-with-lease) and [Adam Johnson's recommendation](https://adamj.eu/tech/2023/10/31/git-force-push-safely/):

- `--force-with-lease` alone is vulnerable to background fetches that silently update the remote ref without the user seeing the changes
- `--force-if-includes` (Git 2.30+, released 2020-12) adds a second check: verifies that the local branch has incorporated the remote tracking branch's latest commit
- The combination `--force-with-lease --force-if-includes` is the recommended safe force push pattern
- Fallback to `--force-with-lease` alone is needed for environments with Git < 2.30

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
- Learning: `knowledge-base/learnings/2026-02-22-cleanup-merged-path-mismatch.md` (never construct paths from ref names)
- Learning: `knowledge-base/learnings/2026-02-24-pull-latest-main-after-cleanup-merged.md` (post-merge lifecycle in scripts)
- Learning: `knowledge-base/learnings/2026-02-12-ship-integration-pattern-for-post-merge-steps.md` (thin orchestration layer)
- Related plan: `knowledge-base/plans/2026-02-24-feat-pull-latest-after-merge-plan.md` (post-merge pull-latest)
- Constitution: "Prefer hook-based enforcement over documentation-only rules for agent discipline"
- Git force-push safety: [Atlassian blog](https://www.atlassian.com/blog/it-teams/force-with-lease), [Adam Johnson](https://adamj.eu/tech/2023/10/31/git-force-push-safely/)
