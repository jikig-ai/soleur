# Tasks: harden shell scripts for bare repo context

## Phase 1: Setup

- [ ] 1.1 Create shared helper `plugins/soleur/scripts/resolve-git-root.sh`
  - [ ] 1.1.1 Implement IS_BARE detection using `git rev-parse --is-bare-repository`
  - [ ] 1.1.2 Implement GIT_ROOT resolution using `--absolute-git-dir` for bare, `--show-toplevel` for non-bare
  - [ ] 1.1.3 Export `GIT_ROOT` and `IS_BARE` variables
  - [ ] 1.1.4 Add `set -euo pipefail` and shebang
  - [ ] 1.1.5 Verify helper works when sourced from different CWD locations

## Phase 2: Core Implementation -- Script Hardening

- [ ] 2.1 Harden `plugins/soleur/hooks/welcome-hook.sh`
  - [ ] 2.1.1 Replace `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` with sourced helper
  - [ ] 2.1.2 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.2 Harden `plugins/soleur/hooks/stop-hook.sh`
  - [ ] 2.2.1 Replace `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` with sourced helper
  - [ ] 2.2.2 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.3 Harden `plugins/soleur/scripts/setup-ralph-loop.sh`
  - [ ] 2.3.1 Replace `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` with sourced helper
  - [ ] 2.3.2 Set `PROJECT_ROOT="$GIT_ROOT"`
- [ ] 2.4 Harden `plugins/soleur/skills/community/scripts/discord-setup.sh`
  - [ ] 2.4.1 Source helper at script top
  - [ ] 2.4.2 Replace `repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` in `cmd_write_env()` with `repo_root="$GIT_ROOT"`
  - [ ] 2.4.3 Replace same pattern in `cmd_verify()` with `repo_root="$GIT_ROOT"`
- [ ] 2.5 Harden `plugins/soleur/skills/community/scripts/x-setup.sh`
  - [ ] 2.5.1 Source helper at script top
  - [ ] 2.5.2 Replace `repo_root` in `cmd_write_env()` with `repo_root="$GIT_ROOT"`
  - [ ] 2.5.3 Replace `repo_root` in `cmd_verify()` with `repo_root="$GIT_ROOT"`
- [ ] 2.6 Harden `plugins/soleur/skills/community/scripts/bsky-setup.sh`
  - [ ] 2.6.1 Source helper at script top
  - [ ] 2.6.2 Replace `repo_root` in `cmd_write_env()` with `repo_root="$GIT_ROOT"`
  - [ ] 2.6.3 Replace `repo_root` in `cmd_verify()` with `repo_root="$GIT_ROOT"`
- [ ] 2.7 Harden `scripts/generate-article-30-register.sh`
  - [ ] 2.7.1 Source helper at script top
  - [ ] 2.7.2 Replace bare `cd "$(git rev-parse --show-toplevel)"` with `cd "$GIT_ROOT"`
  - [ ] 2.7.3 Add IS_BARE guard -- exit with clear error if bare (needs working tree for template)

## Phase 3: worktree-manager.sh Improvements (Medium Priority)

- [ ] 3.1 Add `require_working_tree` guard to `create_draft_pr()`
- [ ] 3.2 Fix `list_worktrees()` bare-context output
  - [ ] 3.2.1 When IS_BARE is true, label as "Bare root (no working tree)" instead of "Main repository"
  - [ ] 3.2.2 Suppress `git rev-parse --abbrev-ref HEAD` call when bare (returns misleading output)
- [ ] 3.3 Add `.claude-plugin` to `sync_bare_files` file list

## Phase 4: worktree-manager.sh Improvements (Low Priority)

- [ ] 4.1 Implement atomic file overwrites in `sync_bare_files`
  - [ ] 4.1.1 Use `mktemp` to write to temp file
  - [ ] 4.1.2 `mv` temp file to target path
  - [ ] 4.1.3 Apply permissions after mv
- [ ] 4.2 Consolidate `.claude/settings.json` into `files=()` array
  - [ ] 4.2.1 Add `.claude/settings.json` to the files array
  - [ ] 4.2.2 Ensure `mkdir -p` handles subdirectory creation for array entries
  - [ ] 4.2.3 Remove the dedicated 7-line block
- [ ] 4.3 Add `sync-bare` alias
  - [ ] 4.3.1 Change primary case pattern to `sync-bare-files|sync-bare`
  - [ ] 4.3.2 Keep `sync` as secondary alias (backward compat)
  - [ ] 4.3.3 Update help text to document `sync-bare` as preferred
- [ ] 4.4 Implement stale file cleanup in `sync_bare_files`
  - [ ] 4.4.1 List hook files on disk
  - [ ] 4.4.2 Compare against git HEAD hook list
  - [ ] 4.4.3 Remove on-disk files not present in HEAD

## Phase 5: Testing and Verification

- [ ] 5.1 Verify `ralph-loop-stuck-detection.test.sh` still passes
- [ ] 5.2 Test helper sourcing from hooks directory (different relative path)
- [ ] 5.3 Test helper sourcing from scripts directory
- [ ] 5.4 Test helper sourcing from skills/community/scripts directory
- [ ] 5.5 Run all modified scripts with `bash -n` for syntax validation
- [ ] 5.6 Run compound before commit
