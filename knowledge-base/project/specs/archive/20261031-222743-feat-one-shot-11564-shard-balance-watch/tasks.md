# Tasks — ci-shard-balance-watch drift probe (issue #11564)

Plan: `knowledge-base/project/plans/2026-10-31-ci-shard-balance-watch-drift-probe-plan.md`

## Phase 1 — measurement mode (generator)

- [x] 1.1 Add `--drift-report` to `scripts/regenerate-shard-manifest.py` (read-only; requires `--timings-dir`; refuses `--write`/`--incremental`/`--legs`; `--durations`/`--manifest` honored as comparison-base overrides = fixture seam)
- [x] 1.2 Emit `DRIFT_ROW <group> <label> <committed_ms> <fresh_median_ms> <timed>/<sampled>` per floor row with >=1 fresh sample (light + heavy)
- [x] 1.3 Emit `LEG_PREDICTED <group> <leg> <ms>` from committed tables; `LEG_OBSERVED light <leg> <ms>` (light only); `BOUND_PERFECT light <ms>`; `FLOOR_UNMEASURED <group> <count>`
- [x] 1.4 Extend `plugins/soleur/test/regenerate-shard-manifest.test.sh` — emission shape, floor-vs-measured discrimination, light/heavy artifact filtering, refusal arms, exit codes

## Phase 2 — watch script

- [x] 2.1 Write `scripts/watch-shard-balance-11564.sh` (conventions of `scripts/watch-registration-narrowing-9564.sh`: `set -uo pipefail`, xtrace refusal exit 78, exit vocabulary 0/1/2/3/78, `--dry-run`)
- [x] 2.2 Run selection + download: `gh run list --workflow ci.yml --event merge_group --status success -L 5`; `gh run download <id> -R "$GH_REPO" -p 'suite-timings-scripts-*' -D <tmpdir>/<id>`
- [x] 2.3 Thresholds: `FLOOR_DRIFT_BOUND_MS=300000`, `LEG_DRIFT_RATIO=1.30`; compose findings comment
- [x] 2.4 Tracker lifecycle: find-or-file `ci-shard-balance-watch: manifest drift findings` (sentinel `<!-- shard-balance-watch:v1 drift=<sha1> -->`); comment only on set-hash change; resolution comment + close on all-clear
- [x] 2.5 Write `scripts/watch-shard-balance-11564.test.sh` fixture suite covering the Guard Contract mutation matrix rows 1-9

## Phase 3 — workflow + registration + docs

- [x] 3.1 Write `.github/workflows/shard-balance-watch.yml` (weekly `'41 9 * * 2'`; `dry_run` dispatch input; `permissions: {}` top / `contents: read, issues: write` job; default-branch repo-scoped `if:`; `concurrency.group: shard-balance-watch`, no cancel; `timeout-minutes: 15`; `persist-credentials: false`, `fetch-depth: 1`; WHY/DEDUP/SELF-DISABLE/RESIDUAL-RISK/RETIREMENT header)
- [x] 3.2 `run_suite "scripts/watch-shard-balance-11564" bash scripts/watch-shard-balance-11564.test.sh` in `scripts/test-all.sh` want_scripts region (beside other `watch-*` suites)
- [x] 3.3 `python3 scripts/regenerate-shard-manifest.py --incremental --write` → rows in `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv`
- [x] 3.4 Update `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — watcher section + `--timings-dir` regen recipe
- [x] 3.5 Add `scripts/ci-pr-affected-audit.accept.tsv` rows only if the replay ratchet flags the new suite's fixture path names

## Phase 4 — deferral filings + verification

- [ ] 4.1 File follow-up issue: required-ratchet promotion (re-eval: >=4 advisory weekly runs, zero false-positive flags, bounds holding)
- [ ] 4.2 File follow-up issue: widen sampling to pull_request runs + infra-group leg balance
- [ ] 4.3 Verify AC1-AC10 against the plan; post-merge `gh workflow run shard-balance-watch.yml -f dry_run=true` per the workflow header recipe
