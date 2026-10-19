# Tasks: refactor: extract shared PROJECT_ROOT resolution into resolve-git-root.sh

## Phase 1: Extend the Helper

- 1.1 Add `GIT_COMMON_ROOT` variable to `plugins/soleur/scripts/resolve-git-root.sh`
  - 1.1.1 Resolve `git rev-parse --git-common-dir` to absolute path
  - 1.1.2 Strip trailing `/.git` if present
  - 1.1.3 Unset temp variables (`_resolve_common_dir`)
  - 1.1.4 Update file header comment to document `GIT_COMMON_ROOT`

## Phase 2: Refactor Consumers

- 2.1 Refactor `plugins/soleur/hooks/stop-hook.sh`
  - 2.1.1 Add `SCRIPT_DIR` resolution
  - 2.1.2 Replace inline `_common_dir` pattern (lines 13-20) with `source "$SCRIPT_DIR/../scripts/resolve-git-root.sh"`
  - 2.1.3 Set `PROJECT_ROOT="$GIT_COMMON_ROOT"` after sourcing
  - 2.1.4 Preserve error behavior: `|| { exit 0; }` (hook must not block session exit)
- 2.2 Refactor `plugins/soleur/scripts/setup-ralph-loop.sh`
  - 2.2.1 Add `SCRIPT_DIR` resolution
  - 2.2.2 Replace inline `_common_dir` pattern (lines 13-19) with `source "$SCRIPT_DIR/resolve-git-root.sh"`
  - 2.2.3 Set `PROJECT_ROOT="$GIT_COMMON_ROOT"` after sourcing
  - 2.2.4 Preserve error behavior: `|| { echo "Error..."; exit 1; }` (setup must fail loudly)

## Phase 3: Testing

- 3.1 Add `GIT_COMMON_ROOT` tests to `plugins/soleur/test/resolve-git-root.test.sh`
  - 3.1.1 Test: normal repo -- `GIT_COMMON_ROOT` equals `GIT_ROOT`
  - 3.1.2 Test: worktree -- `GIT_COMMON_ROOT` points to parent repo root
  - 3.1.3 Test: `GIT_COMMON_ROOT` is a valid directory
- 3.2 Run existing tests to verify no regressions
  - 3.2.1 Run `bash plugins/soleur/test/resolve-git-root.test.sh`
- 3.3 Smoke test: verify ralph loop state file paths match between setup and stop hook
