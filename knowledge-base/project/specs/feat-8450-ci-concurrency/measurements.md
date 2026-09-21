# Measurements — CI concurrency ceiling (#8450)

Canonical before/after record. The PR body links here; do not duplicate numbers
in the body.

## Timestamp-semantics pin (precondition for the probe)

Measured 2026-09-21 against live API data; this falsifies the plan's original
run-level metric and the reviewers' job-level conflation concern alike:

- `run_started_at == created_at` on every one of 30 recent runs sampled —
  run-level `created_at → run_started_at` measures registration only and is
  **vacuous** as a queue-wait metric. Do not use it.
- `job.created_at` is stamped when the job becomes runnable — for a
  `needs:`-gated job it equals the upstream job's `completed_at`
  (`deploy.created_at == migrate.completed_at` on run 35555748979). Therefore
  `job.started_at − job.created_at` is **pure runner-acquisition wait**; no
  upstream-compute conflation.
- While a job is `status=queued`, the API pre-populates `started_at` equal to
  `created_at` — the field is only meaningful on completed/in_progress jobs.
  Sample finished jobs only.

**Probe metric (corrected):** per-job `started_at − created_at` on the
deploy-arm jobs (`migrate`, `deploy`) of `web-platform-release.yml` runs
filtered `--event workflow_run` (excludes the push-arm release-only runs).

## Baseline (pre-change, 2026-09-21)

### Queued snapshot ~08:32 UTC

`gh api repos/jikig-ai/soleur/actions/runs?status=queued&per_page=100`:
~30+ runs queued, oldest created 08:01 UTC (~30 min at sample). Single PR heads
dispatch ~18 runs each (PRs #8453/#8454/#8474 batches visible).

### Saturated-window queue waits (job `started_at − created_at`)

CI run 35570460536 (created 06:54, succeeded 08:26):

| job | queued wait |
|---|---|
| detect-changes | 45.7 min |
| test (required aggregator) | 25.0 min |
| critical-css-gate | 26.4 min |

### Deploy-arm (`web-platform-release.yml`, `--event workflow_run`)

8 recent successful runs — job-level queue waits for `migrate`/`deploy`/
`live-verify` were 0–4 s except one `migrate` at 49 s. The deploy arm registers
and runs in quiet windows today; the tail lands on the *critical path to merge*
(CI jobs above), and on deploy arms dispatched during saturated windows
(the 30–75 min issue-reported baseline).

## Post-upgrade (pending)

`UPGRADE_NOT_BEFORE`: **TBD** — set to the `gh api orgs/jikig-ai --jq
.plan.name` == `team` verification timestamp (operator-upgrade-steps.md Step 2).

Soak probe: `scripts/followthroughs/actions-queue-tail-8450.sh` — pass =
≥5 deploy-arm runs postdating `UPGRADE_NOT_BEFORE` with p95 queue wait < 15 min.
