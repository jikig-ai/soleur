# Tasks: committed extractor-mutation coverage for the run_suite --rows tiling arm

Plan: `knowledge-base/project/plans/2026-09-27-test-extractor-mutation-rows-coverage-plan.md`
Issue: #8990

## Phase 0: Setup — base sync (load-bearing prerequisite)

- [ ] 0.1 `git merge origin/main` — expected fast-forward (merge-base == HEAD `dfee49ef53`,
  zero unique commits). The `--rows` registrations and the `_rows_tile_check` tiling arm under
  test exist only at `d453170127`+.
- [ ] 0.2 Verify anchors exist post-sync: `grep -n 'lint-orphan-test-suites-mutations-b.*--rows 9-16' scripts/test-all.sh`
  returns exactly one line; `git grep -n _rows_tile_check plugins/soleur/test/` is non-empty.
- [ ] 0.3 Confirm the three mutation-target paths are clean before running the battery locally
  (`git status --porcelain -- scripts/test-all.sh .github/workflows/ci.yml plugins/soleur/test/scripts-shard-totality.test.sh`
  prints nothing — the battery refuses to run on a dirty target).

## Phase 1: Core implementation

- [ ] 1.1 In `plugins/soleur/test/scripts-shard-totality-mutations.sh`, append three
  `in_range && row` sites — `ROWS-GAP` (RED, `--rows 9-16` → `--rows 10-16`), `ROWS-DROP`
  (RED, flag removed → MIXED contract), `ROWS-SWAP` (GREEN, -a/-b order swap) — after the
  `MUSTPASS` row site and before the RANGE ACCOUNTING block, using the byte-exact anchors from
  the plan's Proposed Solution.
- [ ] 1.2 Bump `DECLARED_TOTAL=24` → `DECLARED_TOTAL=27` and update the header comment
  "twenty-four ways" → "twenty-seven ways".
- [ ] 1.3 In `.github/workflows/ci.yml` `shard-totality-mutations` job: `rows: ["1-12", "13-24"]`
  → `["1-14", "15-27"]`; update "declares 24 numbered row sites" → "27" and "24-row battery"
  → "27-row". Same commit as 1.1/1.2 (the declared-row-drift check and the guard's ci.yml
  tiling arm both red on a split commit).

## Phase 2: Testing

- [ ] 2.1 `bash plugins/soleur/test/scripts-shard-totality-mutations.sh --rows 25-27` → exit 0,
  `3 executed` (AC3).
- [ ] 2.2 `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` (full range) → exit 0,
  `27 of 27` declared-row accounting (AC4).
- [ ] 2.3 Collect the AC5 evidence: with the DECLARED_TOTAL bump applied but ci.yml still
  `["1-12", "13-24"]`, `bash plugins/soleur/test/scripts-shard-totality.test.sh` goes RED on the
  tiling arm; after the re-split it goes GREEN. Commit only the green state.
- [ ] 2.4 `bash plugins/soleur/test/fixture-relative-assert.test.sh` → exit 0; only if the
  battery's flagged-operand count moved, regenerate
  `plugins/soleur/test/fixture-relative-assert.baseline.txt` via `--write-baseline` in the same
  commit (AC6).
- [ ] 2.5 `git diff origin/main...HEAD --stat` shows only the two (or three) prescribed files
  plus knowledge-base artifacts (AC7).
