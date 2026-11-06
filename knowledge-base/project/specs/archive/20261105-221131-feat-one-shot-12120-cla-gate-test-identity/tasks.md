# Tasks: fix cla-signed-author-gate.test.sh setup-commit identity (#12120)

Plan: knowledge-base/project/plans/2026-11-05-fix-cla-gate-test-setup-commit-identity-plan.md

## Phase 1: Reproduce (RED)

- [x] 1.1 Run the suite with an empty HOME, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`; confirm exit 128 after `PASS: T14`.
- [x] 1.2 Record `python3 scripts/ci-pr-affected-replay.py audit` baseline (`gap_refs`, `stale`).

## Phase 2: Fix (GREEN)

- [x] 2.1 Add `setup_commit <work> <msg>` after `commit_branch` in `.claude/hooks/cla-signed-author-gate.test.sh` (env GIT_AUTHOR_*/GIT_COMMITTER_*; no `git config`).
- [x] 2.2 `push_cla_yml`: use `setup_commit "$work" "add cla.yml"`.
- [x] 2.3 `push_cla_signatures`: use `setup_commit "$work" "signatures"`.
- [x] 2.4 Do not change `run_hook_noglobal`, `commit_branch`, `make_repo`, or any case body.

## Phase 3: Verify

- [x] 3.1 Re-run the no-identity command: exit 0, 26/26.
- [x] 3.2 Normal-env run: 26/26, T15/T16 PASS.
- [x] 3.3 Re-run the audit; `gap_refs`/`stale` unchanged.
- [x] 3.4 `git diff --name-only` shows only the one test file (plus KB artifacts).
- [x] 3.5 Ship with `Closes #12120` in PR #12198 body.
