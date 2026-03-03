# Tasks: Migrate Hooks to hookSpecificOutput JSON Format

## Phase 1: Setup

- [x] 1.1 Verify worktree is on correct branch (`feat/migrate-hooks-json`)
- [x] 1.2 Read current `guardrails.sh` and `worktree-write-guard.sh` content

## Phase 2: Core Implementation

- [x] 2.1 Migrate `guardrails.sh` Guard 1 (commit on main) from `echo '{"decision":"block",...}'` to `jq -n` with `hookSpecificOutput`
- [x] 2.2 Migrate `guardrails.sh` Guard 2 (rm -rf worktrees) from `echo '{"decision":"block",...}'` to `jq -n` with `hookSpecificOutput`
- [x] 2.3 Migrate `guardrails.sh` Guard 3 (delete-branch with worktrees) from `echo '{"decision":"block",...}'` to `jq -n` with `hookSpecificOutput`
- [x] 2.4 Migrate `worktree-write-guard.sh` from `echo` with escaped JSON to `jq -n --arg` with `hookSpecificOutput`

## Phase 3: Verification

- [x] 3.1 Verify no remaining `"decision":"block"` patterns in `.claude/hooks/guardrails.sh` and `.claude/hooks/worktree-write-guard.sh`
- [x] 3.2 Verify `stop-hook.sh` was NOT modified (Stop hooks use different format)
- [x] 3.3 Verify all modified hooks produce valid JSON by piping sample output through `jq .`
- [x] 3.4 Run `shellcheck` on modified files if available (not installed — skipped)
- [ ] 3.5 Run compound (`soleur:compound`)
- [ ] 3.6 Commit and push
