# Learning: bare repo cleanup runs stale on-disk scripts and fetch needs refspec

## Problem

After merging a PR via `cleanup-merged`, the warning "Main checkout has uncommitted changes to tracked files -- skipping pull" appeared even though there are no uncommitted changes in a bare repo. Main was not updated, so subsequent worktrees branched from stale commits.

Two root causes:

1. **Stale on-disk script:** Bare repos have no working tree, so files on disk (including `worktree-manager.sh` itself) never update after merges. The script running was an old version that lacked the `IS_BARE` guard added in a recent PR. It fell through to `git -C "$GIT_ROOT" diff --quiet HEAD` which returns exit code 128 ("must be run in a work tree"), which the `!` inversion treated as "has changes."

2. **Fetch without refspec:** Even in the fixed version, `git fetch origin main` only updates `FETCH_HEAD` and `origin/main` -- it does NOT advance the local `main` ref. New worktrees created with `git worktree add ... main` branch from the **local** main, which stays stale.

3. **Trap scoping bug:** `sync_bare_files` set `trap 'rm -rf "$tmpdir"' EXIT` with single quotes, deferring `$tmpdir` expansion. Since `tmpdir` is a `local` variable, it's out of scope when the trap fires at script exit, causing `set -u` to crash with "unbound variable."

## Solution

1. **fetch refspec:** Changed `git fetch origin main` to `git fetch origin main:main` so the local ref advances.
2. **trap early-expansion:** Changed single quotes to double quotes (`trap "rm -rf '$tmpdir'" EXIT`) so `$tmpdir` is expanded at set-time, not fire-time. Added shellcheck disable comment explaining the intentional early expansion.
3. **Manual sync:** Ran `git show HEAD:<file> > <file>` to bootstrap the bare repo's on-disk files to the current version.

## Key Insight

Bare repos are a chicken-and-egg problem: the script that syncs files is itself one of the files that needs syncing. Any fix to the sync mechanism only takes effect after a manual bootstrap. The `sync_bare_files` function exists for this purpose but must be bootstrapped once when first deployed.

Also: `git fetch origin <branch>` and `git fetch origin <branch>:<branch>` are fundamentally different. The former updates tracking refs only; the latter advances the local ref. In bare repos where `git pull` is unavailable, the refspec form is essential.

## Tags

category: shell-scripts
module: worktree-manager
