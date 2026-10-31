# Tasks — feat-one-shot-11556-reprice-checkpoint

Plan: `knowledge-base/project/plans/2026-10-31-chore-11556-sharding-reprice-checkpoint-plan.md`
Issue: #11556 (epic — this checkpoint does not close it)

## Phase 1 — Setup: session-state restore (do FIRST — fragile source)

- [ ] 1.1 `git apply --check` then `git apply`
      `knowledge-base/project/specs/feat-one-shot-11556-reprice-checkpoint/session-state-updates-18-19.patch`
      against
      `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md`
- [ ] 1.2 Verify Updates 18-19 appear verbatim after Update 17 (AC-7); commit
      this restoration as its own commit before the measurement work

## Phase 2 — Artifact capture

- [ ] 2.1 `WORK=$(mktemp -d -t reprice-11556.XXXXXXXX)`; per plan Phase 1,
      `gh run download <id> -p 'suite-timings-scripts-*' -D $WORK/<id>` for:
      41132662609, 41136687119, 41138355176, 41141190932, 41146395715,
      41180934660, 41133279254, 41135223254
- [ ] 2.2 Completeness gate: every run dir holds exactly 8
      `suite-timings.tsv` leg files (AC-1). Incomplete/expired dirs are
      excluded and named; <3 complete dirs → abort with re-list note

## Phase 3 — Measure

- [ ] 3.1 Emit fully-measured scratch tables:
      `python3 scripts/regenerate-shard-manifest.py --timings-dir $WORK/<id>
      [x8] --manifest $WORK/measured-legs.tsv --write`
      (redirected manifest — committed files untouched)
- [ ] 3.2 Floor check: all 7 arm labels MUST be measured (`src=measured`) —
      an arm at floor halts for diagnosis; list non-arm floor rows for the
      runbook entry
- [ ] 3.3 Observed spread: per run, per-leg suite-time sums from artifacts;
      per-leg wall clocks via two-stage jobs-API (`gh api .../jobs` → `jq`,
      never `gh --jq --arg`); compare worst leg vs ~28-min bound and vs the
      43-51 min pre-split baseline

## Phase 4 — Re-price (incumbent-preserving)

- [ ] 4.1 Build `$WORK/seed-durations.tsv` = committed table with the 7 arm
      rows' ms replaced by measured medians (plan Phase 3 awk shape)
- [ ] 4.2 Dry-run `--durations $WORK/seed-durations.tsv`; read incumbent-diff
      (moved/new/gone) + predicted legs
- [ ] 4.3 `--write`; verify committed diff is bounded (7 arm rows + floor
      re-derivations + manifest re-seat) (AC-2, AC-3)
- [ ] 4.4 Run verification set: `scripts-shard-manifest.test.sh`,
      `regenerate-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`,
      `scripts-shard-runtime-coverage.test.sh`,
      `scripts/test-all-fast-tier-budget.test.sh` — all green (AC-5);
      same-suite arms on distinct legs (AC-6)

## Phase 5 — Record + report

- [ ] 5.1 Runbook `## Measured history` entry: 8 run ids, per-run worst-leg
      suite-time + wall, per-run spread, arm medians before/after,
      post-reprice predicted worst leg vs ~28-min bound, floor count, #11648
      drift evidence (AC-4)
- [ ] 5.2 Same edit: fix the `Re-deriving leg composition` download command
      `-n 'suite-timings-*'` → `-p 'suite-timings-scripts-*'`
- [ ] 5.3 Post measured always-on medians as evidence comment on #11648
- [ ] 5.4 Final diff audit vs AC-8 (only the named files + planning artifacts)

## Notes

- If `soleur:engineering:cto` rules for the full `--timings-dir --write`
  instead of the seed path (decision-challenges row 1), Phase 4 changes
  shape: the fast-tier budget suite reds until #11648's demotion folds in —
  replan that phase rather than silently shipping the red.
