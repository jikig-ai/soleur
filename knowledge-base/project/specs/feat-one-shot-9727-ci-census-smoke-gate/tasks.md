# Tasks: S1 census script and secret-scan smoke path gate (#9727)

Plan: `knowledge-base/project/plans/2026-10-08-chore-ci-demand-census-and-smoke-path-gate-plan.md`. Branch `feat-one-shot-9727-ci-census-smoke-gate`, draft PR #9772.

## Phase 1: Fixture and RED suites

- 1.1 Create `scripts/fixtures/ci-demand-census/basic/runs.json` and `jobs-<run_id>.json` files (synthetic ids and SHAs, real field names, one two-document jobs file)
  - 1.1.1 One job per classification clause with a distinct power-of-two duration (runner-less with `runner_id` 0 and null, two untimed, a labelled-synthetic skipped job with a runner), an in-progress run with a decoy jobs file, a run with `total_count` 0, a dynamic CodeQL run named per PR, a skipped `smoke` stem plus a `smoke-relevance` job
  - 1.1.2 Hand-compute the golden totals for the suite
  - 1.1.3 Check the fixture against gitleaks (`gitleaks dir scripts/fixtures/ci-demand-census` if installed)
- 1.2 Write `scripts/ci-demand-census.test.sh` (Guard 2 rows 1 to 5, H1, H2, golden tables, live-layer `gh` shim round trip, hostile-name job, `guard-vacuity-floor`-shaped floor, append-only failure ledger)
- 1.3 Write `scripts/secret-scan-smoke-gate.test.sh` (PyYAML extraction of body, env, wrapper and `if:`; `gh` shim with exact endpoint; named subject list and prefix rows as modification and rename source; operand anchor with a known-positive control; hostile-filename fixture; Guard 1 rows 1 to 7, H1, H2; mutants run against copies with a landing check)

## Phase 2: Census script

- 2.1 Implement `scripts/ci-demand-census.sh` (live mode in one-hour sub-windows with C1 before any jobs call, fixture mode, one aggregator, summary output with `STEM` ran/skipped/runnerless columns, input validation and output sanitisation, CI refusal, exit codes 0/2/3)
- 2.2 Write the header comment (denominator, lower bounds, closed-window `date -u` recipe, 1000-result cap, developer-shell-only rate limit note)
- 2.3 Run live over 2026-10-07T13:04:00Z to 2026-10-07T19:04:00Z and keep the output as the baseline

## Phase 3: Smoke gate

- 3.1 Add `smoke-relevance` (with `CHANGED_FILES` completeness check, output written last) to `.github/workflows/secret-scan.yml`; add `needs:` and the exact `if:` (including the `result != 'success'` arm) to `smoke-tests`
- 3.2 Add the `SUBJECT_RE` rationale comment and reword the permissions header
- 3.3 Bump `scripts/pr-fanout-ledger.txt` secret-scan row 6 to 7 with the consequence text
- 3.4 Add the runbook paragraph to `knowledge-base/engineering/operations/secret-scanning.md` and the CODEOWNERS line for the gate suite
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
- 6.4 Scratch canary with two revert commits (no force-push): narrow `SUBJECT_RE` to see `smoke=false` and ten skipped rows, add an early `exit 1` to see the matrix run; revert both
- 6.5 Merge through the queue or auto-merge (the PR edits workflows, so the agent `--admin` path reports UNTRUSTED-CI)

## Phase 7: Post-merge

- 7.1 Run the census over a closed post-merge window (sub-windowed, so 6 hours or more is fine); attach it and the baseline to #9727 inside a code fence with `gh issue comment 9727 --body-file`
- 7.2 Report the net criterion (smoke plus smoke-relevance minutes per PR run down at least 80%), the ran/skipped/queue-cancelled split and the coverage ratio from the `STEM` rows; confirm the false-arm canary on the first PR that touched no subject path (or the 48-hour fallback)
- 7.3 Comment on #9730 that concurrency sampling belongs to S5
