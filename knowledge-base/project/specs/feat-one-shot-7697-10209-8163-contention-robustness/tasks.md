# Tasks — feat-one-shot-7697-10209-8163-contention-robustness

Derived from `knowledge-base/project/plans/2026-10-13-fix-test-all-contention-robustness-plan.md`
(closes #7697, #10209, #8163 + spec-archive housekeeping).

## Phase 1 — #7697: bounded lock wait + holder observability

- [x] 1.1 Write failing test arms first (RED):
  - `plugins/soleur/test/session-state.test.sh`: arm driving
    `acquire_lock`/`with_lock` against a held lock under a blocked-SIGALRM
    fixture (`python3`/`perl` `sigprocmask` → exec bash) — must return within
    `timeout_s + slack`; control arm with normal mask returns via `flock -w`
    expiry; absent-`timeout` degrade arm; forced-bound log line asserted.
  - `scripts/test-contention.test.sh`: holder-marker mint/stamp/remove arms;
    heartbeat emits `holder_pid=`/`holder_alive=`/`holder_progress_age=`;
    `holder=none` post-release; `holder=unreadable` is never an error.
  - `plugins/soleur/test/gitleaks-merge-commit.test.sh`: PATH-pinned
    never-exiting `gitleaks`/`git` stub arm — bounded call returns instead of
    hanging.
- [x] 1.2 `plugins/soleur/scripts/lib/session-state.sh`:
  `_acquire_lock_impl` wraps `flock -w` in `timeout -k <grace> <timeout_s+slack>`;
  rc=124 maps to the existing `return 99` contended path and emits the
  forced-bound `[contention]` line; degrade to bare `flock -w` when `timeout`
  is absent; write `$LOCK_DIR/<name>.holder` on acquire; remove in
  `release_lock`.
- [x] 1.3 `scripts/test-all.sh`: `run_suite` stamps `progress_epoch`,
  `last_suite`, `suites_done` into the holder file per suite boundary (only
  when the file exists and this run holds the `test-all` lock).
- [x] 1.4 `scripts/lib/test-contention.sh`: `_tc_wait_heartbeat` reads the
  marker each beat and prints `holder_*` fields (`kill -0` for
  `holder_alive`); tolerate absent/unreadable marker.
- [x] 1.5 `plugins/soleur/test/lib/gitleaks-probe.sh`: shared bounded-invocation
  helper extending the `timeout`/`gtimeout`/`unbounded+[note]` idiom
  (lines 34-35); `</dev/null` stdin + `GIT_TERMINAL_PROMPT=0` defaults.
- [x] 1.6 `plugins/soleur/test/gitleaks-merge-commit.test.sh`: route
  `scan_git`, `scan_git_count`, `scan_git_rules`, `scan_dir_rules`,
  `patch_bytes`, and `build_fixture`'s `git` calls through the helper.
- [x] 1.7 Sibling sweep: apply the same bound in
  `plugins/soleur/test/gitleaks-rules.test.sh` where call shapes match.
- [x] 1.8 Turn Phase-1 RED arms GREEN; `shellcheck` clean on edited files.

## Phase 2 — #10209: C8 inherited-count immunity

- [x] 2.1 RED arm first: regression arm in
  `scripts/test-all-weight-drift.test.sh` exporting `TC_SIBLING_RUN_COUNT=3`
  around a bare-invocation arm (currently rc=4 red under an exported count).
- [x] 2.2 `ENV_SCRUB` gains `-u TC_SIBLING_RUN_COUNT -u TC_SIBLING_RUN_COUNT_PID`;
  `build_sandbox` re-arm splice pins the count from a suite-controlled var
  (`WD_SIBLING_RUNS`, mirroring `SANDBOX_SIBLINGS`); arm pinning it nonzero
  still observes rc=4.
- [x] 2.3 Sweep `test-all-group-affected.test.sh`,
  `test-all-killed-classification.test.sh`,
  `test-all-runtime-ceiling.test.sh` for the same inherited-count leak into a
  re-armed refusal; edit only where the leak is real.

## Phase 3 — #8163: contention-aware ceiling

- [x] 3.1 RED arms first: `TC_PROC_ROOT` fixture with a synthesized sibling
  `test-all.sh` proc + over-ceiling → `[note]` not fail (currently fails);
  empty procfs + over-ceiling → still fails; unmeasurable procfs counts as
  contended.
- [x] 3.2 `scripts/orphan-process-reaper-mutation.test.sh`: source
  `scripts/lib/test-contention.sh` guarded (`[[ -f ]] && source`, degrade to
  unconditional assert if absent); sample `tc_siblings` at battery start and
  end; over-ceiling + `max_siblings>0` → `[note]` + pass-with-note;
  `ORPHAN_MUT_CEILING_MS` unchanged.

## Phase 4 — Housekeeping + decision record

- [x] 4.1 `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run one-shot-6752-7004-10167-tmp-gate-residuals`
  → verify preview → real run → assert
  `knowledge-base/project/specs/archive/<ts>-feat-one-shot-6752-7004-10167-tmp-gate-residuals/`
  exists; `git status` shows the rename; grep live refs
  (`grep -rn 'feat-one-shot-6752-7004-10167' --exclude-dir=archive`) clean or
  knowingly retained.
- [x] 4.2 ADR-133 dated addendum: live-wedged-holder class, the plan-time
  blocked-mask reproduction table, the `timeout` exec-boundary bound,
  proceed-on-expiry unchanged.
- [x] 4.3 `test-contention.sh` header comment: one clause naming the
  live-wedged class + pointer to the holder marker; fix stale `(900 s)`
  comment at `scripts/test-all.sh:4165`.

## Quality gates (all phases)

- [x] `bash scripts/test-all.sh` (or `TEST_GROUP=scripts`) green incl. new arms.
- [x] `shellcheck` clean on every edited `.sh`.
- [x] No abort/kill paths added; ADR-133 Decision 3 semantics intact.
- [x] Commit plan + tasks together, then implement phase order 1→4.
