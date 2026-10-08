# Tasks: S1 census script and secret-scan smoke path gate (#9727)

Plan: `knowledge-base/project/plans/2026-10-08-chore-ci-demand-census-and-smoke-path-gate-plan.md`. Branch `feat-one-shot-9727-ci-census-smoke-gate`, draft PR #9772.

## Phase 1: Fixture and RED suites

- 1.1 Create `scripts/fixtures/ci-demand-census/basic/runs.json` and `jobs-<run_id>.json` files (synthetic ids and SHAs, real field names, one two-document jobs file)
  - 1.1.1 Include a runner-less cancelled job, a skipped job, an untimed job, an in-progress run and a dynamic CodeQL run named per PR
  - 1.1.2 Hand-compute the golden totals for the suite
  - 1.1.3 Check the fixture against gitleaks (`gitleaks dir scripts/fixtures/ci-demand-census` if installed)
- 1.2 Write `scripts/ci-demand-census.test.sh` (Guard 2 rows 1 to 5, H1, golden tables, assertion floor, append-only failure ledger)
- 1.3 Write `scripts/secret-scan-smoke-gate.test.sh` (PyYAML extraction, `gh` shim, named subject list as modification and rename source, operand anchor, Guard 1 rows 1 to 7, H1, H2)

## Phase 2: Census script

- 2.1 Implement `scripts/ci-demand-census.sh` (live and fixture modes, one aggregator, summary output, C1, C2, non-vacuity, exit codes 0/2/3)
- 2.2 Write the header comment (denominator, lower bounds, closed-window `date -u` recipe, 1000-result cap, developer-shell-only rate limit note)
- 2.3 Run live over 2026-10-07T13:04:00Z to 2026-10-07T19:04:00Z and keep the output as the baseline

## Phase 3: Smoke gate

- 3.1 Add `smoke-relevance` to `.github/workflows/secret-scan.yml`; add `needs:` and the exact `if:` to `smoke-tests`
- 3.2 Add the `SUBJECT_RE` rationale comment and reword the permissions header
- 3.3 Bump `scripts/pr-fanout-ledger.txt` secret-scan row 6 to 7 with the consequence text
- 3.4 Add the runbook paragraph to `knowledge-base/engineering/operations/secret-scanning.md`
- 3.5 Run `bash plugins/soleur/test/pr-fanout-ledger.test.sh`, `bash scripts/lint-workflows.sh` and the workflow lints

## Phase 4: Registration

- 4.1 Register both suites in `scripts/test-all.sh` at the end of the `scripts/` block
- 4.2 Classify the gate suite in `scripts/lib/test-affected-paths.sh`
- 4.3 Regenerate shard manifests: `python3 scripts/regenerate-shard-manifest.py --incremental --write`
- 4.4 Run `bash scripts/lint-orphan-test-suites.sh` and the shard-totality suites it names

## Phase 5: ADR amendment

- 5.1 Append `## Amendment 2026-10-08 (S1, #9727)` and the dated `S1 amended` Stage-status line to ADR-276 (status stays `proposed`)
- 5.2 Run `bash scripts/check-adr-ordinals.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh`

## Phase 6: Verify, push, PR

- 6.1 Run every Pre-merge acceptance command in the plan
- 6.2 Commit (trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`), push without force, update PR #9772 (`Closes #9727`, closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`)
- 6.3 Poll CI with the Monitor tool; confirm this PR's `smoke-relevance` reads `smoke=true` and the ten legs run

## Phase 7: Post-merge

- 7.1 Run the census over a closed post-merge window of at least 6 hours; attach it and the baseline to #9727 with `gh issue comment 9727 --body-file`
- 7.2 Record smoke ran versus skipped from the `STEM` rows; confirm the false-arm canary on the first PR that touched no subject path (or the 48-hour fallback)
- 7.3 Comment on #9730 that concurrency sampling belongs to S5
