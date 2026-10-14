# Tasks: light test-scripts K=7 -> K=8 (Ref #9307)

Plan: knowledge-base/project/plans/2026-10-03-chore-ci-light-test-scripts-shard-k8-plan.md

## 1. Matrix + RED test
- 1.1 Edit .github/workflows/ci.yml test-scripts matrix to 1/8..8/8
- 1.2 Run scripts-shard-manifest.test.sh and confirm RED (n=7 vs 8 legs)
- 1.3 Update ci.yml comment prose (K=7 paragraph, L1077 prediction, L1227, L1250)

## 2. Guard + comments
- 2.1 ROW5 in scripts-shard-totality-mutations.sh: old = 8-value literal, new = drop "8/8"; update comment and RED text
- 2.2 Prose-only updates: scripts-shard-totality.test.sh (L10, L170), mutations ~L739, scripts/test-all.sh ~L5544

## 3. Regenerate TSV pair wholesale
- 3.1 gh pr view 9447; if merged, git rebase origin/main (never merge); on TSV conflict take origin/main versions and regen
- 3.2 Dry-run regenerate-shard-manifest.py with five --timings-dir (runs 37130724002 37116885720 37112007418 37111686980 37109744841), --group light; confirm max leg < 600000 ms
- 3.3 Same command with --write; confirm diff confined to light TSV pair

## 4. Runbook
- 4.1 TL;DR + topology table K=8 and new prediction
- 4.2 Measured-history 2026-10-03 entry
- 4.3 Cost note (one more runner per run + measurement command) in Runner-availability section

## 5. Verify
- 5.1 manifest, totality, lint-orphan-test-suites, ci-leg-balance-9232 tests green; ROW5 run
- 5.2 battery-owed.sh decides the rest (rc 42 skippable); CI is the gate
- 5.3 PR body: Ref #9307, not Closes; scripts/test-all-affected.test.sh untouched
