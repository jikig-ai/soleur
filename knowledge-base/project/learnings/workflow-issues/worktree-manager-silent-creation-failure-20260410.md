---
module: System
date: 2026-04-10
problem_type: workflow_issue
component: tooling
symptoms:
  - "worktree-manager.sh reported success but directory did not exist"
  - "Had to fall back to manual git worktree add command"
root_cause: missing_validation
resolution_type: workflow_improvement
severity: medium
tags: [worktree-manager, git-worktree, silent-failure, bare-repo]
---

# Troubleshooting: worktree-manager.sh Reports Success but Worktree Not Created

## Problem

The `worktree-manager.sh --yes create` command printed "Worktree created successfully!" and exited 0, but the worktree directory did not exist on disk. The `git worktree list` output did not include the new worktree.

## Environment

- Module: System (git worktree tooling)
- Affected Component: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Date: 2026-04-10

## Symptoms

- Script output showed all steps completing: "Creating worktree...", "Copying environment files...", "Installing dependencies...", "Worktree created successfully!"
- The printed worktree path (`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-verify-replica-identity-1766`) did not exist
- `git worktree list` did not include the branch
- `cd` to the path failed with "No such file or directory"

## What Didn't Work

**Direct solution:** The problem was identified immediately by checking if the directory existed. Fell back to manual `git worktree add` which succeeded.

## Session Errors

**worktree-manager.sh silent creation failure**

- **Recovery:** Used `git worktree add .worktrees/feat-verify-replica-identity-1766 -b feat-verify-replica-identity-1766 origin/main` directly
- **Prevention:** worktree-manager.sh should verify the directory exists after `git worktree add` before printing success. Add a post-creation check: `[[ -d "$worktree_path" ]] || { echo "ERROR: Worktree directory not created"; exit 1; }`

## Solution

**Commands run:**

```bash
# Manual worktree creation (bypassing worktree-manager.sh)
git worktree add .worktrees/feat-verify-replica-identity-1766 -b feat-verify-replica-identity-1766 origin/main
```

This created the worktree correctly. The underlying `git worktree add` command works; the issue is in the manager script's error handling or path construction.

## Why This Works

The root cause is likely a mismatch between the path the script constructs internally and the path it passes to `git worktree add`, or a silent failure in one of the intermediate steps (env copy, dependency install) that masks the actual worktree creation failure. The script does not verify the directory exists before declaring success.

## Prevention

- The worktree-manager.sh script should add a post-creation verification step that checks the directory exists before printing success
- When worktree-manager.sh reports success but the directory is missing, fall back to manual `git worktree add` immediately rather than debugging the script

## Related Issues

- See also: [archive-kb-stale-path-resolution](../2026-03-13-archive-kb-stale-path-resolution.md) (worktree-manager.sh path issues)
- See also: [draft-pr-requires-commit](../2026-03-18-draft-pr-requires-commit.md) (worktree-manager.sh draft-pr behavior)
