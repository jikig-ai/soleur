# Tasks — test-all.sh pre-launch capacity signal (#7545)

Derived from `knowledge-base/project/plans/2026-08-19-chore-test-all-pre-launch-capacity-gate-plan.md`
after plan review. The plan is the source of truth; this is its execution breakdown.

**Scope reminder:** this ships a capacity **signal**, not a decline. The decline was cut on review
(see `decision-challenges.md` DC-2). No exit code changes in this PR.

## Phase 0 — Preconditions (no code)

- [ ] 0.1 `git status --porcelain` is empty before any gate run.
- [ ] 0.2 Confirm seams by content anchor in `scripts/lib/test-contention.sh`: `TC_PROC_ROOT`,
      `TC_NPROC`, `TC_DF_CMD`, `TC_MIN_AVAIL_MB`, `TC_LOCK_TIMEOUT`.
- [ ] 0.3 Measure the current uncontended full-gate wall clock; derive the new `TC_LOCK_TIMEOUT`
      default from it (must exceed the hold time; plan-time proposal 3600). Record both numbers for
      the ADR addendum. If a full run is unaffordable in-session, use ADR-133's recorded ~45-minute
      baseline and state which source was used.
- [ ] 0.4 Re-measure tmpfs headroom **immediately after** a full run, not only at rest (ADR-133
      records `/tmp` dipping to 699 MB against the 1024 MB floor). Confirm the verdict's wording
      treats `low_tmp` as a statement, not a fault.
- [ ] 0.5 Re-check PR #7616 for file overlap after the ship-time rebase.

## Phase 1 — RED: the verdict suite

- [ ] 1.1 Create `scripts/test-all-capacity-signal.test.sh` on the `test-contention.test.sh` harness
      (`make_fake_proc` + `tc_env`), extended with a fake `df` via `TC_DF_CMD` and a fake `meminfo`.
- [ ] 1.2 Write the mutation matrix rows (M1-M21, H1-H7) **before** the implementation exists.
- [ ] 1.3 Threshold arms at below / at / far-above for each signal — including the **at-threshold
      sibling row** (1 sibling), without which the `>=`→`>` mutation is vacuous.
- [ ] 1.4 Two distinct sibling worktrees ⇒ count 2; two PIDs in one worktree ⇒ count 1.
- [ ] 1.5 Degraded-input arms with the corrected witness set: unreadable `/proc/meminfo`; `TC_DF_CMD`
      stub emitting non-numeric output; `TC_PROC_ROOT` with no readable process entries. Do **not**
      use `TC_NPROC=""` (falls through to real `nproc`) or a missing `cwd` (substituted with an
      `<unreadable>` sentinel and still counted).
- [ ] 1.6 Mixed arm: one reading degraded + another over threshold ⇒ `CONTENDED`, degraded named.
- [ ] 1.7 ADR-193 compliance (the suite auto-enrols into `guard-vacuity-floor.test.sh` via
      `COVERED_DIRS='^(scripts/|plugins/soleur/test/)'`):
  - [ ] 1.7.1 D1 — floor `exit 1`s **directly**, never through the suite's own `fail()`.
  - [ ] 1.7.2 D2 — case counter incremented at the **call site**, never inside a helper or `$( … )`.
  - [ ] 1.7.3 D3 — accounting-conservation check `passes + fails == cases`, reported directly.
  - [ ] 1.7.4 D4 — conservation check runs **before** the floor.
- [ ] 1.8 must-PASS non-canonical fixture (different core count, different `TC_TMPDIR`).
- [ ] 1.9 Confirm RED.

## Phase 2 — GREEN: promote measurements, emit the verdict

- [ ] 2.1 In `tc_preamble`, assign `TC_LAST_SIB_COUNT` / `TC_LAST_AVAIL_MB` / `TC_LAST_MEMAVAIL_MB`
      **and their `_OK` validity flags** at script scope. Zero output bytes change.
- [ ] 2.2 Add `tc_capacity_line()` **before** `tc_acquire` in the lib, preserving the stub block's
      "LAST-defined function" invariant.
- [ ] 2.3 Add a `tc_capacity_line` stub to the runner's lib-stub block, emitting
      `CAPACITY_UNKNOWN reason=lib_unavailable` (never silence).
- [ ] 2.4 Emit the verdict in `scripts/test-all.sh` between `tc_preamble` and `tc_acquire`. The
      verdict reads value **and** validity flag, never the value alone.
- [ ] 2.5 Update the lib's `TEST SEAMS` header block: add `TC_WAIT_HEARTBEAT_S` and the
      pre-existing omission `TC_DF_CMD`. (Plan Phase 2.1b.)
- [ ] 2.6 Confirm GREEN; confirm `tc_preamble` stderr byte-identical vs
      `git show origin/main:scripts/lib/test-contention.sh` on a fixed fake `/proc`.

## Phase 3 — RED→GREEN: `--capacity` query mode

- [ ] 3.1 RED arms: exits 0; zero suite invocations recorded; no `LOCK_` line emitted.
- [ ] 3.2 Implement beside `--print-suite-globs`, before every side effect (no `TMPDIR` export, no
      bare-repo guard, no `TEST_GROUP` validation, no `tc_acquire`).
- [ ] 3.3 Confirm GREEN.

## Phase 4 — RED→GREEN: the wait

- [ ] 4.1 RED arms: heartbeat emits holder worktree/pid/elapsed at the interval; contended banner
      names a **re-sampled** count; `tc_acquire` returns 0 on every arm **including zero siblings
      after the wait**.
- [ ] 4.2 Raise the `TC_LOCK_TIMEOUT` default per 0.3; add `TC_WAIT_HEARTBEAT_S` (default 60).
- [ ] 4.3 Implement heartbeat + re-sample. **Carry the trailing or-true guard on the `grep -c`
      count** — `grep -c` exits 1 on a zero count and would abort `tc_acquire` under `set -e`.
- [ ] 4.4 Confirm GREEN.

## Phase 5 — RED→GREEN: the diff-justification report

- [ ] 5.1 RED arms: names touched shards; named "diff undeterminable" line; **no narrowing advice
      under `TEST_GROUP=all`** (ADR-183 Ceiling 1).
- [ ] 5.2 Implement as an advisory line placed after `_diff_touches` is defined. No new `*_PATHS`.
- [ ] 5.3 Confirm GREEN.

## Phase 6 — Registration, consumers, docs

- [ ] 6.1 Register the suite with an explicit `run_suite` line under `want_scripts` — repo-root
      `scripts/*.test.sh` is **not** in `SUITE_GLOBS`.
- [ ] 6.2 `bash scripts/lint-orphan-test-suites.sh` reports no orphan.
- [ ] 6.3 `bash scripts/guard-vacuity-floor.test.sh` exits 0 with the new suite enrolled.
- [ ] 6.4 `plugins/soleur/scripts/grok-pre-push-gate.sh`: `--capacity` as advisory step 0; must not
      gate the push.
- [ ] 6.5 `plugins/soleur/skills/work/SKILL.md` §9: document the verdict line and `--capacity`.
- [ ] 6.6 `plugins/soleur/skills/ship/SKILL.md`: note `--capacity` as the Phase 4 pre-launch probe.
- [ ] 6.7 Write the dated, append-only ADR-133 addendum (verdict, `--capacity`, timeout raise with
      its measurement, heartbeat, re-sample, and **why the decline was cut** with the 616 s datum and
      the #7454 pointer). No new ADR ordinal is claimed.
- [ ] 6.8 Check the two sandbox suites (`test-all-infra-coverage-notice.test.sh`,
      `test-all-killed-classification.test.sh`) still pass — they drive the real runner with
      `SOLEUR_ALLOW_FULL_GATE=` blanked and will now see the new verdict line in its output.

## Phase 7 — Exit gate

- [ ] 7.1 Clean tree, then `TEST_GROUP=scripts bash scripts/test-all.sh`.
- [ ] 7.2 Read the preamble and epilogue, not just `rc`; state which shards ran. A contention banner
      or `CAPACITY_CONTENDED` verdict qualifies the run — apply `work/SKILL.md` §9's three-way
      confirmation before accepting any RED.
- [ ] 7.3 Record every mutation-row transcript (M1-M21, H1-H7) for the PR body (AC20).
