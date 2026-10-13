# Tasks: feat: test-all local weight-drift detector (#9814)

Plan: `knowledge-base/project/plans/2026-10-11-feat-test-all-local-weight-drift-detector-plan.md`

## Phase 1: Comparator lib + suite (RED first)

- [x] 1.1 Write `scripts/test-all-weight-drift.test.sh` with fixture arms (RED against absent lib):
  - [x] 1.1.1 drift emits `WEIGHT_DRIFT <label> committed=<ms> local=<ms>` (local > 2x committed AND > 10000ms)
  - [x] 1.1.2 within-tolerance emits nothing (ratio < 2x; >2x but <10s; exactly-2x strict `>`)
  - [x] 1.1.3 two-drifted-rows fixture emits two lines (stops-at-first is the defect)
  - [x] 1.1.4 `skip=*` rows emit nothing; `NF < 2` / `^#` rows skipped
  - [x] 1.1.5 ran-but-rowless label emits `committed=unmeasured`
  - [x] 1.1.6 `floor`-class anchor row emits with `basis=floor`
  - [x] 1.1.7 FAIL/KILLED/TRIPWIRE rows still compared
  - [x] 1.1.8 all-zero elapsed → single `WEIGHT_DRIFT_UNAVAILABLE` line
  - [x] 1.1.9 dual-emit: lines reach stdout AND stderr
  - [x] 1.1.10 report never exits non-zero
- [x] 1.2 Write `scripts/lib/test-weight-drift.sh` (`weight_drift_report`, one `LC_ALL=C awk -F'\t'` pass; bash-3.2-safe, no `declare -A`; per-manifest `-f` check; zero readable manifests → every ran row `unmeasured`) → GREEN
- [x] 1.3 Suite shell constraints (repo ratchets): all `mktemp` under one owning `trap ... EXIT` (lint-trap-tempfile-ownership rule c); fixture root is provably-absolute `mktemp -d` (fixture-relative-assert); sandboxed arms scrub env per arm (`env -u TEST_GROUP`, never inherit `TEST_TIMING_LOG`/`CI`)

## Phase 2: Runner wiring

- [x] 2.1 Source the lib opportunistically in `scripts/test-all.sh` beside the scratch-root include (~:496), `|| true` + `declare -F` guard
- [x] 2.2 Add the `TEST_TIMING_LOG` default arm after `_durable_log_dir` (~:4275): `-z TEST_TIMING_LOG && -z CI && enumerate/print decline && (TEST_GROUP==affected || (all && _AFFECTED==1))` → `mkdir -p` + `[[ -w && -O ]]` probe → in-shell (never export) `TEST_TIMING_LOG="$_durable_log_dir/suite-timings.tsv"` + truncate + armed `[note]`
- [x] 2.3 Add the epilogue emit after the `=== N/N suites passed ===` marker (post-marker NOTE region): `-z CI && -n TEST_TIMING_LOG && -f file && declare -F weight_drift_report` → call `|| true` over `"$_scriptdir"/suite-durations*.tsv` (glob, not two literals; `$_scriptdir` via `dirname "${BASH_SOURCE[0]}"`)
- [x] 2.4 Register `run_suite "scripts/test-all-weight-drift" bash scripts/test-all-weight-drift.test.sh` beside the fast-tier-budget registration (~:5184)

## Phase 3: Classification + generated-table regen

- [x] 3.1 Add `"scripts/test-all-weight-drift"` to `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`
- [x] 3.2 Add `AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS` block (suite file, lib, test-all.sh, `glob:scripts/*.tsv`, test-affected-paths.sh self-inclusion)
- [x] 3.3 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write` (adds floor row to `scripts/suite-durations.tsv` + leg row to `scripts/suite-shard-legs.tsv`)
- [x] 3.4 Wiring arms in the suite: sandboxed affected run asserts the timing log exists + WEIGHT_DRIFT emitted + rc unchanged; CI=1 arm asserts no auto-default; read-only-dir arm asserts green completion with no log

## Phase 4: ADR-242 amendment

- [x] 4.1 Append a dated `## Amendment — 2026-10-11 (#9814)` section recording the decision ("local run reports local-vs-committed weight drift as an advisory line, never a gate") + rejected alternatives to `ADR-242-*.md`

## Phase 5: Verify

- [ ] 5.1 `bash scripts/test-all-weight-drift.test.sh` green
- [ ] 5.2 `bash scripts/test-all-fast-tier-budget.test.sh` green (allowlist still 2 members)
- [ ] 5.3 `bash scripts/lint-orphan-test-suites.sh` census green
- [x] 5.4 Manifest-readers sweep (QG-5): `git grep -lE 'regenerate-shard-manifest|suite-shard-legs|suite-durations' -- plugins/soleur/test scripts tests` — run every hit's suite
- [ ] 5.5 Local `bash scripts/test-all.sh --affected > /tmp/run.log 2>&1; rc=$?` (redirect+`$?`, never `| tail`) — emits WEIGHT_DRIFT lines or nothing when in tolerance; `=== N/N suites passed ===` remains the last `===`-shaped line; exit code unchanged
- [ ] 5.6 Commit and push
