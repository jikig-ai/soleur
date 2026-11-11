# Tasks — fix: regen shard manifest (run-health-emit weight row)

Plan: `knowledge-base/project/plans/2026-11-11-fix-run-health-emit-weight-row-plan.md`
Branch: `feat-one-shot-run-health-emit-weight-row`

## Phase 1 — Regenerate the shard manifest (the fix)

- [ ] 1.1 From the worktree root, run `python3 scripts/regenerate-shard-manifest.py --incremental --write`
- [ ] 1.2 Confirm the generator's own summary reports `0 moved, 1 new, 0 no longer registered` — anything else means the incumbent moved: STOP, re-sync `origin/main`, re-run 1.1 (never hand-edit the generated tables; ADR-240)
- [ ] 1.3 Confirm `git status` touches exactly `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`

## Phase 2 — Verify

- [ ] 2.1 `grep -P 'run-health-emit\.test\.sh\t1272\tfloor' scripts/suite-durations.tsv` returns one row (alphabetically between `resolve-regenerable-conflicts.test.sh` and `run-in-pid-namespace.test.sh`)
- [ ] 2.2 `grep -P 'run-health-emit\.test\.sh\t[1-8]$' scripts/suite-shard-legs.tsv` returns one row (leg `2` expected per #12650's identical regen)
- [ ] 2.3 `bash scripts/test-all-corpus-weight-budget.test.sh` exits 0 and prints `ALL PASS` (pre-fix reproduction: it fails with `registration(s) with no committed weight row: plugins/soleur/scripts/run-health-emit.test.sh`)
- [ ] 2.4 `git diff --stat` shows 2 files, +4/−2 (2 rows + 2 `generated-at` header re-stamps); `scripts/suite-weight-exemptions.tsv` untouched

## Phase 3 — Merge-ordering check + commit

- [ ] 3.1 Re-read sibling state: `gh pr view 12650 --json state,title` — if #12650 MERGED first, re-run 1.1 on the synced tree; a `0 new` result means this PR is superseded (close after verifying main's `test-scripts` is green)
- [ ] 3.2 `git add scripts/suite-durations.tsv scripts/suite-shard-legs.tsv` (exact paths — never the `scripts/` directory)
- [ ] 3.3 Commit: `fix: backfill run-health-emit.test.sh weight row (shard-manifest regen)` — PR body notes the #12565 follow-up and the #12650 merge-ordering rule; `semver:patch` label class
- [ ] 3.4 Confirm the PR's own CI run shows all `test-scripts (n/8)` legs green, including the previously red `3/8`

## Notes

- Both TSVs are generated artifacts (ADR-240): conflict resolution is re-running the generator, never a hand-merge.
- Floor weight for an unmeasured suite is `default-weight-ms=1272` — far under the 600s `CORPUS_SUITE_CAP_MS`, so no exemption ledger row is needed.
- The `test-scripts (3/8)` red on main is this plan's reproduction; AC4 is the fix's own discoverability probe (~1.2s local runtime).
