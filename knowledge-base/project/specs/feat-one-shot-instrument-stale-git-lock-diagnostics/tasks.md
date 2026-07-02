# Tasks: Instrument stale-git-lock sweep with structured blind-surface diagnostics

lane: single-domain
Plan: knowledge-base/project/plans/2026-07-02-feat-instrument-stale-git-lock-diagnostics-plan.md

## Phase 1 — Structured lock diagnostic (read-only probe)
- [ ] 1.1 Add `_git_lock_diag()` helper in worktree-manager.sh: type detection precedence symlink→mount→dir→regular→missing (`-L` before `-f`; `-d` before `-f`).
- [ ] 1.2 Compute owner/perms/mtime via GNU `stat -c '%u:%g' / %a / %Y`, each guarded `|| =unknown`.
- [ ] 1.3 Compute mount via `findmnt -n -o SOURCE -T`, guarded by `command -v findmnt` (emit `mount=findmnt-unavailable` on absence).
- [ ] 1.4 Emit plain (no-color) `SOLEUR_GIT_LOCK_DIAG file=… type=… owner=… perms=… mtime=… age=… mount=…` to stderr.

## Phase 2 — Type-aware removal + errno capture
- [ ] 2.1 In the `config.lock`/`config.worktree.lock` loop, emit before-state diag when present AND stale (keep age/clock-skew guard).
- [ ] 2.2 regular → `rm -f`; symlink → `rm -f` (link only); dir → guarded `rm -rf` (non-empty, basename allowlist, realpath-prefix-under-git_dir, age, not-a-mountpoint); mount → never rm.
- [ ] 2.3 Capture `rm_rc` + `rm_err`; derive coarse errno label (EBUSY/EPERM/EACCES/OTHER); emit after-line diag.
- [ ] 2.4 On unremovable (rc≠0 / guard-blocked / mount): emit `SOLEUR_GIT_LOCK_UNREMOVABLE file=… type=… errno=… reason=… hint=…`; set `unremovable=1`.

## Phase 3 — Fail-loud contract with ensure_bare_config()
- [ ] 3.1 sweep_stale_git_locks returns non-zero iff a config-write lock remained unremovable; 0 otherwise (absent/fresh/removed).
- [ ] 3.2 ensure_bare_config: guard call `if ! sweep_stale_git_locks "$git_dir"; then` (set -e safe); emit fail-loud line via headless_or_stderr; `return 1` BEFORE the git config writes.
- [ ] 3.3 Preserve `Swept N stale git lock file(s)` happy-path summary; preserve scope (no index.lock/HEAD.lock).

## Phase 4 — Tests
- [ ] 4.1 Create plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh (sources test-helpers.sh; synthesized fixtures).
- [ ] 4.2 Cover: regular-stale removed; dir guarded rm; symlink link-removed/target-preserved; fresh preserved; future-dated preserved; unremovable→rc≠0+sentinel; ensure_bare_config no-config-write-on-unremovable.
- [ ] 4.3 Assert grep-ability: `grep -F 'SOLEUR_GIT_LOCK_'` matches (no color-wrapped tokens).
- [ ] 4.4 `bash -n` clean; full scripts/test-all.sh bash-shard green (no regression on existing worktree-manager-*.test.sh).

## Ship
- [ ] S.1 PR body: `Ref` (not `Closes`); flag issue #4826 mismatch for operator confirmation; `## Changelog` section; semver:patch.
- [ ] S.2 Post-merge (AC10): confirm deployed artifact carries SOLEUR_GIT_LOCK_DIAG via deploy-status webhook / next-session grep (no SSH).
