# Tasks — ci/test-scripts `--rows` arm debt (#11647)

Plan: `knowledge-base/project/plans/2026-11-01-chore-11647-rows-arm-debt-plan.md`
Branch: `feat-one-shot-11647-rows-arm-debt`
Issue: #11647 (epic #11556, mandated-by #11562)

Ordering: S1 (est tier) and S5 (ADR+checklist) are independent of S2–S4.
S2 must land before S3/S4 in the same files (both edit the preamble/floor
regions the extraction touches). S3 and S4 may land in one commit per file or
separate commits per file — listed separately so review can isolate them.
Never `git stash`. Read every file before editing it.

## Phase 1 — `estimate` provenance tier (S1)

- [ ] 1.1 `scripts/regenerate-shard-manifest.py`: widen the `src` enum to
      `(measured, floor, estimate)` in `read_durations_rows` (:421) and
      `parse_durations_text` (:480); update both die messages (:423, :481-482)
- [ ] 1.2 `read_durations` (:428-439) returns `(weights, floor_labels,
      est_labels)`; `weights` = `src ∈ {measured, estimate}`; call site
      :1142 updated; `src_map` build (:1209-1215) emits `estimate` for
      `--durations`-sourced est rows — never `measured`
- [ ] 1.3 `read_durations_ms` (:593-603): `measured` list stays
      `src == "measured"` only (`all_ms` already covers est weight).
      **`--durations` floor-median (:1174,:1207)**: `measured = weights`
      includes est labels post-1.2 — `floor_ms = median(measured.values())`
      must exclude `est_labels`; empty measured set → `DEFAULT_SUITE_MS`
      + WARN, mirroring the incremental path (:1026-1034). (Row 17.)
- [ ] 1.4 `drift_violations` (:487-521): `base_e`/`new_e` sets;
      `estimate→measured` and `measured→estimate` emit named note lines;
      new measured over an est baseline counts toward total growth
- [ ] 1.5 `drift_report_group` (:638-642): est rows join the DRIFT_ROW /
      FLOOR_UNMEASURED population
- [ ] 1.6 `plugins/soleur/test/scripts-shard-manifest.test.sh`:
      `check_durations` enum (:314) + enum comment (:284)
- [ ] 1.7 `plugins/soleur/test/regenerate-shard-manifest.test.sh`: fixture
      cases — est row supplies weight, re-emits `estimate` (never
      `measured`), excluded from floor median (est-only or est+measured
      `--durations` input prices floor rows off the measured median, not
      the blended one — :1207), est→measured / measured→est named notes
- [ ] 1.8 Verify: `python3 -m pytest plugins/soleur/test/regenerate-shard-manifest.test.sh` —
      **NO: it is bash** → `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` green;
      `bash plugins/soleur/test/scripts-shard-manifest.test.sh` green;
      `python3 scripts/regenerate-shard-manifest.py --incremental` dry-run prints
      unchanged totals
- [ ] 1.9 `git commit` Phase 1 alone

## Phase 2 — `scripts/lib/rows-range.sh` + retire the four copies (S2)

- [ ] 2.1 New `scripts/lib/rows-range.sh`: `rows_parse_args "$@"` (reads
      caller's `DECLARED_TOTAL`; refuse repeat/malformed/unknown/out-of-bounds
      → exit 2), `in_range [ord]` (optional ordinal check →
      `FATAL(harness)` exit 2), `rows_gate_floor` (`_site_seq ==
      DECLARED_TOTAL`, `EXECUTED == expected`, optional `ROWS_BLOCK_CASES`
      per-block floor via `ROWS_COUNT_VAR`). **Never** spell `DECLARED_TOTAL=`
      or a literal `--rows <digits>-<digits>` anywhere in the file
      (Direction-1/Direction-2 census constraints)
- [ ] 2.2 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: delete
      :66-118 copy → `source "$REPO_ROOT/scripts/lib/rows-range.sh"` +
      `rows_parse_args "$@"`; keep `DECLARED_TOTAL=42` (:79); rename
      `_row_seq`→`_site_seq` (:1016-1026); keep `TOTAL == EXECUTED + 1` extra
- [ ] 2.3 `scripts/lint-orphan-test-suites.test.sh`: delete :78-133 copy →
      lib source + call; keep `DECLARED_TOTAL=35   # the gated mutation rows
      M1..M35; C0/R1/R1b are unconditional` BYTE-IDENTICAL (totality-mutations
      `DECL-PREFIX-READER` anchor :998-1001); call sites `in_range "${_id#M}"`
      unchanged (:1155)
- [ ] 2.4 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: delete
      :62-123 copy → lib source + call; keep `DECLARED_TOTAL=582`; keep
      `_MUT_UNGATED`/`mutate_ungated` (:124-127); in_range call sites inside
      `ow_mutate` (:3746) and `mutate` (:4281) unchanged
- [ ] 2.5 `scripts/test-all-affected.test.sh`: delete :325-375 copy → lib
      source + call; keep `DECLARED_TOTAL=38`
- [ ] 2.6 `scripts/lib/test-relevance-paths.sh`: add
      `"scripts/lib/rows-range.sh"` to `LINT_ORPHAN_BATTERY_PATHS` (:171-179)
      and `TEST_ALL_AFFECTED_BATTERY_PATHS` (:207-213) — declared edge AND
      pr-gated arming on lib edits
- [ ] 2.7 Verify: each battery per registered arm —
      `bash scripts/lint-orphan-test-suites.test.sh --rows 1-18` and `--rows 19-35`;
      `bash scripts/test-all-affected.test.sh --rows 1-13`, `--rows 14-32`,
      `--rows 33-36`, `--rows 37-38`;
      `bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 1-193`,
      `--rows 194-386`, `--rows 387-582` (long — spot-check at least one);
      `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` (dirty-tree
      refusal applies — run clean);
      `bash plugins/soleur/test/scripts-shard-totality.test.sh` (Direction-1/2
      censuses, tiling arms, distinct legs)
- [ ] 2.8 Ratchet check: run the affected-index audit
      (`scripts/ci-pr-affected-preactivation.sh` or the ratchet path used by
      `ci-pr-affected-replay.py --audit`); add accept rows to
      `scripts/ci-pr-affected-audit.accept.tsv` only if new (suite,
      `scripts/lib/rows-range.sh`) pairs are flagged — pr-gated arms are
      already covered by the 2.6 declared edges
- [ ] 2.9 `git commit` Phase 2 alone

## Phase 3 — exit-code normalization (S3)

- [ ] 3.1 `scripts/test-all-affected.test.sh`: :92 (missing required file) and
      :109 (instrument self-test) `exit 1` → `exit 2`
- [ ] 3.2 `scripts/lint-orphan-test-suites.test.sh`: `exit 1` → `exit 2` at
      :1206, :1210, :1214 (aggregation FATALs) and :1320, :1325, :1333, :1342
      (end-gate FATALs); `:1346` verdict stays 1; `mutate`'s `sys.exit(3)`
      untouched
- [ ] 3.3 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: `exit 1` →
      `exit 2` on every battery-process `[FATAL]` path — :53, :57, :59, :140,
      :141, :145, :176, :179, :711, :740, :953, :1735, :1754, :2253, :2294,
      :2347, :2351, :2352, :2370, :5177, :5183, :5186, :5189, :5192, :5195;
      verdict tail (:5199-5200) and stub/fixture exits untouched
- [ ] 3.4 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: end-gate
      `FAIL:` lines (:1017, :1026, :1033) → `FATAL:` + `exit 2` (shape
      accounting, not verdicts); `:1040-1041` verdict exit stays 1
- [ ] 3.5 Verify: `grep -n 'exit 1'` per file — remaining hits are verdicts or
      fixture/stub code only; run at least one arm per battery from 2.7
- [ ] 3.6 `git commit` Phase 3 alone

## Phase 4 — per-block declared case floors (S4)

- [ ] 4.1 `scripts/test-all-affected.test.sh`: declare `ROWS_COUNT_VAR=cases`
      and `ROWS_BLOCK_CASES=( <38 declared minimums> )` beside
      `DECLARED_TOTAL` with a comment mapping ordinals to block letters;
      count each block's `cases+=` sites; loop-driven blocks get their
      structural minimum
- [ ] 4.2 `scripts/lib/rows-range.sh`: `in_range` snapshots
      `${!ROWS_COUNT_VAR}` per call when set; `rows_gate_floor` closes the
      last block and `FATAL exit 2`s any dispatched block with
      `actual < declared`, naming the ordinal
- [ ] 4.3 Proof: hollow one block to fewer cases → the covering arm reds with
      the block ordinal in the message; restore
- [ ] 4.4 Verify: `bash scripts/test-all-affected.test.sh --rows <each arm>`
      green on the intact tree
- [ ] 4.5 `git commit` Phase 4 alone

## Phase 5 — ADR + checklist (S5)

- [ ] 5.1 `knowledge-base/engineering/architecture/decisions/ADR-313-<slug>.md`
      (next free ordinal — ADR-312 is top): `-<letter>` arm convention —
      boundary in the flag argument, distinct-legs post-pass, tiling +
      label-shape + literal-census + DECLARED_TOTAL-census arms, same-commit
      re-split rule, both split styles (run_suite arms, ci.yml `rows:` matrix)
- [ ] 5.2 `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`:
      arm-split checklist — run_suite/skip_suite pairs +
      `_relevance_declined` count; shared `<NAME>_PATHS` array +
      `RELEVANCE_ARRAYS` row; `AFFECTED_CONSUMED_EDGES` per arm;
      `is_pr_gated_decline`; `GATED` rows; pr-battery-gate constants;
      `DECLARED_TOTAL` + `rows_parse_args` + `in_range` + `rows_gate_floor`;
      `--incremental --write` regen (distinct legs); totality-mutations
      verbatim-anchor re-pin; ratchet pair check — plus the `estimate`
      seeding rule (seed → `estimate`, never `measured`)
- [ ] 5.3 Verify: `grep -n 'ADR-313' knowledge-base/engineering/architecture/decisions/`;
      ADR lint/`lint-adr-*` suites if present green
- [ ] 5.4 `git commit` Phase 5 alone

## Phase 6 — decision row 12 (optional, only if ruled)

- [ ] 6.1 `scripts/lib/rows-range.test.sh` — parse-edge unit suite (repeat,
      malformed, bounds, ordinal mismatch, per-block floor). If added:
      auto-globbed registration; `python3
      scripts/regenerate-shard-manifest.py --incremental --write` for both
      TSVs; PRODUCER_JOIN row if it pipes text to a producer; fixture-assert
      baseline if it builds fixture dirs; ratchet pair check.
      Census constraints the suite file must satisfy: (a) **Direction-1**
      — `scripts/lib` is enumerated (`scripts-shard-totality.test.sh:1020`),
      so NO literal `--rows <digits>-<digits>` outside `#`-comments —
      construct specs via `--rows "${_a}-${_b}"` or the census reds
      `_lit_n > _emit_n`; (b) **Direction-2** — repo-wide, so NO
      line-start `DECLARED_TOTAL=` spelling anywhere in the file — use
      subshell-scoped `( export DECLARED_TOTAL=N; … )` forms only.
- [ ] 6.2 `git commit` separately

## Phase 7 — final verification

- [ ] 7.1 All eight verification batteries from 2.7/4.4 green on the final tree
- [ ] 7.2 `bash plugins/soleur/test/scripts-shard-totality.test.sh` +
      `scripts-shard-manifest.test.sh` + `lint-orphan-test-suites.sh` green
- [ ] 7.3 `git status --porcelain` clean of scratch files; diff review: no
      `DECLARED_TOTAL=` outside the four batteries, no `--rows N-M` literal in
      the lib, no secrets

## Acceptance criteria

See the plan's `## Acceptance Criteria` (AC1–AC8).
