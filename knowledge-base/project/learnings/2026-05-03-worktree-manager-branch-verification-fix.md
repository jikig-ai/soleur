# Learning: worktree-manager silent-fail — branch not created despite exit 0

## Problem

`worktree-manager.sh --yes create <name>` could print success messages and exit 0 while the branch was never created. Subsequent `git branch -a` showed no branch; a second invocation was required. The `verify_worktree_created` function checked directory existence and `git worktree list` registration but not branch existence via `git show-ref`.

## Solution

Added Check 3 to `verify_worktree_created()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

```bash
if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
  echo -e "${RED}Error: Branch $branch_name was not created despite successful worktree add${NC}"
  echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
  git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
  exit 1
fi
```

This fires after Check 2 (worktree list registration) and before success output, ensuring the branch ref exists before reporting success.

## Key Insight

`git worktree add` can silently fail to create the branch ref even when the worktree directory appears, especially on bare repos with config fixup (the `ensure_bare_config` dance). Post-condition checks must cover all expected side effects (directory, worktree list entry, AND branch ref) — not just the most visible one.

## Session Errors

- **First `worktree-manager.sh` invocation exited 128** — `git fetch` inside `update_branch_ref` ran before `ensure_bare_config` fixed the `core.bare` state. Recovery: second invocation succeeded after config was restored. Prevention: `update_branch_ref` should guard against bare-repo fetch (already partially mitigated; consider `git fetch --update-head-ok` or a `core.bare` check before fetch).

## Tags
category: integration-issues
module: git-worktree
