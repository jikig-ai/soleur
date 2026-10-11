# Tasks: feat: test-all local weight-drift detector (#9814)

Plan: `knowledge-base/project/plans/2026-10-11-feat-test-all-local-weight-drift-detector-plan.md`

## Phase 1: Comparator lib + suite (RED first)

- [ ] 1.1 Write `scripts/test-all-weight-drift.test.sh` with fixture arms (RED against absent lib):
  - [ ] 1.1.1 drift emits `WEIGHT_DRIFT <label> committed=<ms> local=<ms>` (local > 2x committed AND > 10000ms)
  - [ ] 1.1.2 within-tolerance emits nothing (ratio < 2x; >2x but <10s; exactly-2x strict `>`)
  - [ ] 1.1.3 two-drifted-rows fixture emits two lines (stops-at-first is the defect)
  - [ ] 1.1.4 `skip=*` rows emit nothing; `NF < 2` / `^#` rows skipped
  - [ ] 1.1.5 ran-but-rowless label emits `committed=unmeasured`
  - [ ] 1.1.6 `floor`-class anchor row emits with `basis=floor`
  - [ ] 1.1.7 FAIL/KILLED/TRIPWIRE rows still compared
  - [ ] 1.1.8 all-zero elapsed → single `WEIGHT_DRIFT_UNAVAILABLE` line
  - [ ] 1.1.9 dual-emit: lines reach stdout AND stderr
  - [ ] 1.1.10 report never exits non-zero
- [ ] 1.2 Write `scripts/lib/test-weight-drift.sh` (`weight_drift_report`, one `LC_ALL=C awk -F'\t'` pass; bash-3.2-safe, no `declare -A`) → GREEN

## Phase 2: Runner wiring

- [ ] 2.1 Source the lib opportunistically in `scripts/test-all.sh` beside the scratch-root include (~:496), `|| true` + `declare -F` guard
- [ ] 2.2 Add the `TEST_TIMING_LOG` default arm after `_durable_log_dir` (~:4275): `-z TEST_TIMING_LOG && -z CI && (TEST_GROUP==affected || _AFFECTED==1)` → `mkdir -p` + `[[ -w ]]` probe → `TEST_TIMING_LOG="$_durable_log_dir/suite-timings.tsv"`
- [ ] 2.3 Add the epilogue emit after the `=== N/N suites passed ===` marker (post-marker NOTE region): `-z CI && -n TEST_TIMING_LOG && -f file && declare -F weight_drift_report` → call `|| true` over both durations manifests resolved via `dirname "${BASH_SOURCE[0]}"`
- [ ] 2.4 Register `run_suite "scripts/test-all-weight-drift" bash scripts/test-all-weight-drift.test.sh` beside the fast-tier-budget registration (~:5184)

## Phase 3: Classification + generated-table regen

- [ ] 3.1 Add `"scripts/test-all-weight-drift"` to `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`
- [ ] 3.2 Add `AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS` block (suite file, lib, test-all.sh, both durations manifests, test-affected-paths.sh self-inclusion)
- [ ] 3.3 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write` (adds floor row to `scripts/suite-durations.tsv` + leg row to `scripts/suite-shard-legs.tsv`)
- [ ] 3.4 Wiring arms in the suite: sandboxed affected run asserts the timing log exists + WEIGHT_DRIFT emitted + rc unchanged; CI=1 arm asserts no auto-default; read-only-dir arm asserts green completion with no log

## Phase 4: ADR-242 amendment

- [ ] 4.1 Append the new decision ("local run reports local-vs-committed weight drift as an advisory line, never a gate") + rejected alternatives to `ADR-242-*.md` (next free ordinal — verify against origin/main at ship)

## Phase 5: Verify

- [ ] 5.1 `bash scripts/test-all-weight-drift.test.sh` green
- [ ] 5.2 `bash scripts/test-all-fast-tier-budget.test.sh` green (allowlist still 2 members)
- [ ] 5.3 `bash scripts/lint-orphan-test-suites.sh` census green
- [ ] 5.4 Local `bash scripts/test-all.sh --affected` emits WEIGHT_DRIFT lines or nothing when in tolerance; `=== N/N suites passed ===` remains the last `===`-shaped line; exit code unchanged
- [ ] 5.5 Commit and push
