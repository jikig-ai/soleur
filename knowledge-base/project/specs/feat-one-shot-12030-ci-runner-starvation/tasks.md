# Tasks: ci hosted-runner starvation (#12030)

Plan: knowledge-base/project/plans/2026-11-04-ci-hosted-runner-demand-trim-plan.md

## Phase 1: Evidence and audit

- [x] 1.1 Re-run scripts/ci-demand-census.sh for the 2026-11-03T19:00Z to 22:00Z peak window (retry in two halves on HTTP 502; if it still aborts, label peak figures "sampled"; if the census contradicts the sampled shares, return to the CTO before writing the no-safe-lever sentence)
- [x] 1.2 Re-measure worst leg and p95 of deploy-script-tests over 10 green infra-validation PR runs
- [x] 1.3 Write knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md (cap verification, per-workflow accounting with number bases, cancelled-run lifetime, hour-of-day table, delivered-concurrency finding, lever table with CTO rulings, reproduction command for every number)

## Phase 2: Comment corrections

- [x] 2.1 cron-merge-queue-stall-dispatch.ts: rewrite the two "30-minute window" sentences and the DETECTION LATENCY paragraph with the 120/45 arithmetic (margins before run time); sweep the file for 75-minute, 30-minute window and 75 minutes
- [x] 2.2 infra-validation.yml: grep for suites pinning the 6.7/403 comment text, then a comment-only dated worst-leg/p95 re-measure

## Phase 3: Decision records

- [x] 3.1 ADR-276: append short dated amendment (no safe demand lever beyond S2/S3; residual risk is delivered concurrency; re-evaluation triggers; pointer to the audit) plus a dated stage-status line (via soleur:architecture)
- [x] 3.2 ADR-270: one line "re-verified 2026-11-04" under "### Addendum 2026-11-03 (#12030)" only

## Phase 4: Tracking issues and hand-offs

- [x] 4.1 File deferred-scope-out issue: larger runners for the test aggregator and tail gate jobs (spend; operator decision)
- [x] 4.2 File deferred-scope-out issue: GitHub support ticket for runner under-assignment (attach 2026-11-03T22:52Z sample; include automation-status UNVERIFIED line)
- [x] 4.3 Comment on epic #11556 with the PR-run-cost finding (330 vs about 100 job-min, suites over committed prices)
- [x] 4.4 Link both issues from the audit and the ADR-276 amendment

## Phase 5: Verify

- [x] 5.1 Run the plan Acceptance Criteria commands (grep sweep, comment-only diff proof, vitest, c4-count-parity, test-audit-ruleset-bypass, workflow lint comparison, markdownlint)
- [x] 5.2 Hand to soleur:ship: PR body leads with the no-safe-lever finding, uses Ref #12030, carries the User-Challenge row
