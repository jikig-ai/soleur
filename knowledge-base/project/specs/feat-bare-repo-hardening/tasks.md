# Tasks: harden shell scripts for bare repo context

## Phase 1: Setup

- [ ] 1.1 Create shared helper `plugins/soleur/scripts/resolve-git-root.sh`
  - [ ] 1.1.1 Implement IS_BARE detection using `git rev-parse --is-bare-repository`
  - [ ] 1.1.2 Implement GIT_ROOT resolution using `--absolute-git-dir` for bare, `--show-toplevel` for non-bare
  - [ ] 1.1.3 Set `GIT_ROOT` and `IS_BARE` variables (no `export`, no `set` commands)
  - [ ] 1.1.4 Add execution guard: print error and `exit 1` if run directly (not sourced)
  - [ ] 1.1.5 Use `return 1` (not `exit 1`) for error paths since the file is sourced
  - [ ] 1.1.6 `unset _git_dir` after use to avoid polluting caller namespace
  - [ ] 1.1.7 Verify helper works when sourced from hooks, scripts, and community/scripts directories

## Phase 2: Core Implementation -- Script Hardening

- [ ] 2.1 Harden `plugins/soleur/hooks/welcome-hook.sh`
  - [ ] 2.1.1 Add `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
  - [ ] 2.1.2 Replace `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` with `source "$SCRIPT_DIR/../scripts/resolve-git-root.sh"`
  - [ ] 2.1.3 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.2 Harden `plugins/soleur/hooks/stop-hook.sh`
  - [ ] 2.2.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/../scripts/resolve-git-root.sh"`
  - [ ] 2.2.2 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.3 Harden `plugins/soleur/scripts/setup-ralph-loop.sh`
  - [ ] 2.3.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/resolve-git-root.sh"` (same directory)
  - [ ] 2.3.2 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.4 Harden `plugins/soleur/skills/community/scripts/discord-setup.sh`
  - [ ] 2.4.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/../../../../scripts/resolve-git-root.sh"`
  - [ ] 2.4.2 Replace `repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` in `cmd_write_env()` with `local repo_root="$GIT_ROOT"`
  - [ ] 2.4.3 Replace same pattern in `cmd_verify()` with `local repo_root="$GIT_ROOT"`
- [ ] 2.5 Harden `plugins/soleur/skills/community/scripts/x-setup.sh`
  - [ ] 2.5.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/../../../../scripts/resolve-git-root.sh"`
  - [ ] 2.5.2 Replace `repo_root` in `cmd_write_env()` with `local repo_root="$GIT_ROOT"`
  - [ ] 2.5.3 Replace `repo_root` in `cmd_verify()` with `local repo_root="$GIT_ROOT"`
- [ ] 2.6 Harden `plugins/soleur/skills/community/scripts/bsky-setup.sh`
  - [ ] 2.6.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/../../../../scripts/resolve-git-root.sh"`
  - [ ] 2.6.2 Replace `repo_root` in `cmd_write_env()` with `local repo_root="$GIT_ROOT"`
  - [ ] 2.6.3 Replace `repo_root` in `cmd_verify()` with `local repo_root="$GIT_ROOT"`
- [ ] 2.7 Harden `scripts/generate-article-30-register.sh`
  - [ ] 2.7.1 Add `SCRIPT_DIR` and source helper via `"$SCRIPT_DIR/../plugins/soleur/scripts/resolve-git-root.sh"`
  - [ ] 2.7.2 Add IS_BARE guard: exit with informative error mentioning "bare repo" and "worktree"
  - [ ] 2.7.3 Replace `cd "$(git rev-parse --show-toplevel)"` with `cd "$GIT_ROOT"`

## Phase 3: worktree-manager.sh Improvements (Medium Priority)

NOTE: worktree-manager.sh keeps inline IS_BARE detection (runs before sync, cannot depend on helper)

- [ ] 3.1 Add `require_working_tree` guard to `create_draft_pr()` (after main/master check)
- [ ] 3.2 Fix `list_worktrees()` bare-context output
  - [ ] 3.2.1 When IS_BARE is true, label as "Bare root (no working tree)" instead of "Main repository"
  - [ ] 3.2.2 Suppress `git rev-parse --abbrev-ref HEAD` call when bare
- [ ] 3.3 Add `.claude-plugin` to `sync_bare_files` file list
- [ ] 3.4 Add `plugins/soleur/scripts/resolve-git-root.sh` to `sync_bare_files` file list
- [ ] 3.5 Restore execute permissions on `resolve-git-root.sh` after sync (alongside worktree-manager.sh chmod)

## Phase 4: worktree-manager.sh Improvements (Low Priority)

- [ ] 4.1 Implement atomic file overwrites in `sync_bare_files`
  - [ ] 4.1.1 Create single temp directory with `mktemp -d "$GIT_ROOT/.sync-tmp.XXXXXX"` (same filesystem for atomic mv)
  - [ ] 4.1.2 Add `trap 'rm -rf "$tmpdir"' EXIT` immediately after mktemp
  - [ ] 4.1.3 Write each file to temp dir, then `mv` to target path
  - [ ] 4.1.4 Remove trap cleanup after successful completion (or let EXIT handle it)
- [ ] 4.2 Consolidate `.claude/settings.json` into `files=()` array
  - [ ] 4.2.1 Add `.claude/settings.json` to the files array
  - [ ] 4.2.2 Verify `mkdir -p "$(dirname ...)"` already handles subdirectory creation (it does, line 637)
  - [ ] 4.2.3 Remove the dedicated 7-line block (lines 652-657)
- [ ] 4.3 Add `sync-bare` alias
  - [ ] 4.3.1 Change case pattern to `sync-bare-files|sync-bare|sync`
  - [ ] 4.3.2 Update help text: document `sync-bare` as preferred, note `sync` is kept for backward compat
  - [ ] 4.3.3 Update the BARE REPO NOTE comment at script top to reference `sync-bare`
- [ ] 4.4 Implement stale file cleanup in `sync_bare_files`
  - [ ] 4.4.1 After syncing hooks, list on-disk files in `.claude/hooks/`
  - [ ] 4.4.2 Compare against `git ls-tree --name-only HEAD .claude/hooks/`
  - [ ] 4.4.3 Remove on-disk files not present in HEAD
  - [ ] 4.4.4 Handle edge case: `.claude/hooks/` does not exist on disk (skip cleanup)

## Phase 5: Testing and Verification

- [ ] 5.1 Run `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- all tests must pass
- [ ] 5.2 Run `bash -n` on all 8 modified scripts for syntax validation
- [ ] 5.3 Run `bash -n plugins/soleur/scripts/resolve-git-root.sh` for syntax validation
- [ ] 5.4 Verify direct execution of `resolve-git-root.sh` prints error and exits 1
- [ ] 5.5 Run compound before commit
