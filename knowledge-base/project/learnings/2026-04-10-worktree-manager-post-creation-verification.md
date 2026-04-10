# Learning: worktree-manager.sh post-creation verification and dynamic self-path

## Problem

`worktree-manager.sh feature <name>` (and `create <name>`) could print "Feature setup complete!"
while producing only a directory — not a functioning git worktree. Inside the directory,
`git rev-parse --show-toplevel` failed and `git branch --show-current` returned `main`.

Additionally, the `draft-pr` subcommand's correct invocation path was not shown after
feature creation, causing callers inside worktrees to guess at relative paths and
sometimes trigger the script's own "Cannot run from bare repo root" guard.

## Solution

Two changes to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

1. **Post-creation verification** — added immediately after `ensure_bare_config` in both
   `create_worktree()` and `create_for_feature()`:

   ```bash
   local actual_toplevel
   if ! actual_toplevel=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null); then
     echo -e "${RED}Error: Worktree creation failed — $worktree_path is not a valid git worktree${NC}"
     git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
     exit 1
   fi
   if [[ "$actual_toplevel" != "$worktree_path" ]]; then
     echo -e "${RED}Error: Worktree path mismatch — expected $worktree_path, got $actual_toplevel${NC}"
     git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
     exit 1
   fi
   ```

2. **Dynamic SCRIPT_DIR** — resolved at the top of the script so the correct `draft-pr`
   invocation path is printed in the `create_for_feature` success output:

   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   ```

   The success output now includes:
   ```
   3. Open draft PR: bash /absolute/path/to/worktree-manager.sh draft-pr
   ```

## Key Insight

`git worktree add` on bare repos can silently fail (directory created, no `.git` file,
no registration in the worktree list). The script must verify the worktree is functional
immediately after creation rather than trusting exit code alone.

`SCRIPT_DIR` prevents callers from needing to know where `plugins/` lives relative to
their CWD — the script advertises its own absolute path in the success output.

## Session Errors

- **`worktree-manager.sh --yes create` exited 128 from bare repo root** — `update_branch_ref`
  calls `git fetch` which requires a working tree. Recovery: used `git worktree add` directly.
  Prevention: the post-creation verification added in this fix would have caught the partial
  creation earlier; the `--yes create` path from bare root is a known limitation.
- **Bun test suite segfaults** — Pre-existing (tracked in #1796). Not introduced by this fix.

## Tags

category: integration-issues
module: plugins/soleur/skills/git-worktree
