# Tasks: ci-duration-aware-shard-packing

Plan: `knowledge-base/project/plans/2026-09-29-ci-duration-aware-shard-packing-plan.md`
Issue: #9232 — duration-aware shard packing (extends ADR-240's sticky-LPT generator).

## Phase 1: Battery rows first (RED)

- [ ] 1.1 Extend `plugins/soleur/test/regenerate-shard-manifest.test.sh` with
      fixtures J–M + floor/second-member/dispatch rows from Guard Contract 1
      (multi-run median via repeated `--timings-dir`; untimed-label floor
      tabling; `--write` n-mismatch refusal; `--durations` read honored;
      `src=floor` never re-read as measured); bump `MIN_CASES` in the same
      edit.
- [ ] 1.2 Extend `plugins/soleur/test/scripts-shard-manifest.test.sh` with a
      `--- durations tables ---` block (exists / well-formed
      `label<TAB>ms<TAB>src` / `src` enum / ⊆ registered / manifest-keys ==
      durations-keys) for light + heavy; bump `MIN_CASES`.
- [ ] 1.3 Extend `.github/scripts/test/test-infra-suite-registration.sh` with
      the matching coherence arm for `apps/web-platform/infra/suite-durations.tsv`.

## Phase 2: Generator implementation (GREEN)

- [ ] 2.1 `scripts/regenerate-shard-manifest.py` input layer: `green_main_runs()`,
      `--runs N` (default 5), repeatable `--timings-dir` (one run per dir),
      `--durations`/`--durations-out`, source precedence `--durations` >
      `--timings-dir` > gh with honest provenance (mirrors `main()`'s
      pairing rule at ~line 355); `expected_legs` WARN stays bound to the
      workflow's declared N, never the `--legs` override.
- [ ] 2.2 Aggregation + floor: per-label median across runs (mean of two
      middles for even N); `floor_ms` = median-of-measured else
      `DEFAULT_SUITE_MS = 60000`; `src` provenance; all-floor WARN-degrade
      (no more die on empty timings).
- [ ] 2.3 Emission: `--legs K`; refuse `--write` to the default committed
      manifest when `K !=` workflow N; durations-table writer;
      `GENERATOR_VERSION` → `"3"`; header gains `# generated-from-runs=` +
      `# default-weight-ms=`; report prints per-run coverage + floor count.
- [ ] 2.4 Re-run both batteries to GREEN.

## Phase 3: Regenerated artifacts + docs

- [ ] 3.1 Regenerate `scripts/suite-shard-legs{,-heavy}.tsv`,
      `apps/web-platform/infra/suite-shard-legs.tsv`, and the three
      `suite-durations*.tsv` against the latest green main runs; paste the
      dry-run predicted-leg table into PR evidence.
- [ ] 3.2 Refresh the stale positional-era guidance comment above the
      `test-scripts` matrix in `.github/workflows/ci.yml` (~lines 1029–1044)
      — comment-only; direct K-changes at `--legs` dry-run simulation.
- [ ] 3.3 Update `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
      (regen procedure with `--runs`/`--durations`/`--legs`, floor rule,
      resolve-by-regen conflict rule, #8231 local-parallel recipe) and amend
      ADR-240 per the plan's Architecture Decision section.
- [ ] 3.4 Post the consumption-contract pointer comment on #8231.

## Phase 4: Soak probe

- [ ] 4.1 Add `scripts/followthroughs/ci-leg-balance-9232.sh` (sweeper exit
      contract: 0/1/2/3; ≥3 qualifying post-`earliest` green runs; every leg
      ≤ ~2× mean, excluding legs dominated by one suite > mean) +
      `.test.sh` (synthesized fixtures only) + one `run_suite` registration
      in `scripts/test-all.sh` (~line 4042 region — the only test-all.sh
      change).

## Phase 5: End-to-end verification

- [ ] 5.1 `SCRIPTS_SHARD=k/4 SOLEUR_SHARD_MANIFEST=<emitted n=4>` ×
      `--enumerate scripts` for all four legs — disjoint union equals the
      registered set (the #8231 consumption path).
- [ ] 5.2 Full touched-shard run; markdownlint on all touched `.md` files;
      confirm `git diff origin/main...HEAD -- scripts/test-all.sh` is exactly
      the one registration hunk.
