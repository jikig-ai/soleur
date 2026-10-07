## Problem

Stage 1 of the #9721 hosted-runner demand plan (plan: `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md`, ADR-276 proposed). Every later stage needs a reproducible before/after job-minute number, and the first measurement pass was 26% off because jobs that never got a runner (`runner_id` 0) were counted as running.

## Scope

1. A small census script that implements the plan's Measured-state method: `gh api --paginate` to a file, `jq -s` to flatten, runner-bound non-skipped jobs only, totals per workflow and event, `CI` per-family per-run minutes, and one job-count self-check against the runs listing. Register its suite and confirm with `bash scripts/lint-orphan-test-suites.sh`.
2. Optional, droppable: path-gate the secret-scan `smoke-tests` matrix on `pull_request` (lever 4a, up to 134 job-minutes per 6h window, a 1.8% gross upper bound). Premises corrected by plan review: the matrix runs only on `pull_request` today (no `schedule` arm exists), so a weekly arm must be added with its own test or the "weekly full coverage" claim dropped; the gate must run unconditionally on non-PR events (no diff base there); a new `smoke-relevance` job raises the declared count and needs a `scripts/pr-fanout-ledger.txt` bump.

User-Impact: none for users; touches CI only (`.github/workflows/secret-scan.yml` PR run, `scripts/ci-demand-census.sh`)
Fix-Size: 250 lines / 6 files

Needs its own Guard Contract for the smoke gate (property, assembly, a mutation matrix of at least three rows) in its own plan.

Discoverability test (handed over by the plan's Observability block): `bash scripts/ci-demand-census.sh --fixture <dir> --summary` prints a `TOTAL_JOB_MINUTES` line.

Exit: the census is attached to this issue (#9727); smoke minutes down at least 80% on PRs that miss the subject paths.

Rollback: revert (the census script is additive; the smoke gate is a non-required, PR-only job).

Re-evaluation: after the plan PR #9722 merges; census attached to this issue afterwards.

Refs #9721
