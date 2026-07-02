# Tasks: Instrument stale-git-lock sweep with structured blind-surface diagnostics

lane: single-domain
brand_survival_threshold: aggregate pattern
Plan: knowledge-base/project/plans/2026-07-02-feat-instrument-stale-git-lock-diagnostics-plan.md

REFRAME (deepen-plan): instrument + REPORT all lock types; auto-REMOVE only the regular-file case
(existing behavior). Non-regular/mount → loud SOLEUR_GIT_LOCK_UNREMOVABLE + fail-loud, NOT rm -rf/unlink.
All emission on STDOUT (stderr is invisible under `claude --bg`). Diverges from literal task
"rm -rf/unlink" instruction — flag for operator sign-off (AC11).

## Phase 1 — Structured lock diagnostic (read-only, any PRESENT lock, STDOUT)
- [ ] 1.1 Emit SOLEUR_GIT_LOCK_DIAG on STDOUT whenever config.lock/config.worktree.lock is PRESENT (any age), plain/no-color.
- [ ] 1.2 Type precedence: -L (symlink) → mountpoint → -d (dir) → -f (regular) → missing.
- [ ] 1.3 Mountpoint test via `stat -c%m "$rp" == "$rp"` (realpath first); NO bare `findmnt -T` (returns containing-fs SOURCE + exit 0 for every path). findmnt only for SOURCE label once confirmed a mountpoint; guard `command -v findmnt` → mount=findmnt-unavailable else mount=none.
- [ ] 1.4 owner/perms/mtime via `stat -c '%u:%g'/%a/%Y`, each `|| =unknown` on its own line.
- [ ] 1.5 age only after numeric guard: `age=unknown; [[ "$mtime" =~ ^[0-9]+$ ]] && age=$(( now - mtime ))`.

## Phase 2 — Removal (regular-only) + errno, set -e-safe
- [ ] 2.1 regular + stale → `rm_err=$(rm -f -- "$path" 2>&1 >/dev/null) || rm_rc=$?` (redirection order load-bearing); `swept=$(( swept + 1 ))` (NOT ((swept++))) on success.
- [ ] 2.2 regular + stale + rm-fail → SOLEUR_GIT_LOCK_UNREMOVABLE errno=<_rm_errno text-map> reason=rm-failed; unremovable=1.
- [ ] 2.3 non-regular (dir/symlink/mount) → do NOT remove; SOLEUR_GIT_LOCK_UNREMOVABLE reason=non-regular-lock; unremovable=1.
- [ ] 2.4 fresh (age<threshold) → untouched (DIAG already emitted). Preserve clock-skew/future-date guard.
- [ ] 2.5 Add _rm_errno() map: EBUSY/EPERM/EACCES/EROFS/OTHER from GNU rm strerror text.

## Phase 3 — Fail-loud contract + caller guarding
- [ ] 3.1 sweep returns non-zero iff unremovable=1; echo `Swept N` summary BEFORE any early return (partial progress).
- [ ] 3.2 ensure_bare_config: `if ! sweep_stale_git_locks "$git_dir"; then` emit loud line; `return 1` BEFORE git config writes.
- [ ] 3.3 Guard ensure_bare_config at ALL 5 callers (:506/:567/:589/:643/:942):
        - :942 cleanup_merged_worktrees → warn + CONTINUE (do not abort unrelated session-start maintenance).
        - :506/:567/:589/:643 create paths → clear message + `exit 1`.
- [ ] 3.4 Preserve scope (only config.lock/config.worktree.lock).

## Phase 4 — Tests
- [ ] 4.1 Create plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh (sources test-helpers.sh; synthesized fixtures; capture STDOUT).
- [ ] 4.2 Cases: regular-stale-removed(Swept 1,rc0); regular-fresh-preserved; future-dated-preserved; dir-reported-not-removed(rc!=0); symlink-reported-not-removed(rc!=0); regular-rm-fail EPERM loud-line-present(rc!=0); ensure_bare_config no-config-write-on-unremovable; cleanup_merged_worktrees caller continues.
- [ ] 4.3 Assert sentinels on STDOUT, color-free: `grep -F 'SOLEUR_GIT_LOCK_'`.
- [ ] 4.4 `bash -n` clean; full scripts/test-all.sh bash-shard green (no regression on existing worktree-manager-*.test.sh).

## Ship
- [ ] S.1 PR body: `Ref` (not `Closes`); flag #4826 mismatch; flag rm-rf/unlink divergence for operator sign-off; `## Changelog`; semver:patch.
- [ ] S.2 Post-merge (AC12): confirm deployed artifact carries SOLEUR_GIT_LOCK_DIAG via deploy-status webhook / next-session grep (no SSH).
