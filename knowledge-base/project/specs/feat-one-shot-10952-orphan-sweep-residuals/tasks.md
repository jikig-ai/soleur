# Tasks: orphan-sweep residuals (#10952)

Plan: `knowledge-base/project/plans/2026-10-24-fix-orphan-sweep-residuals-plan.md`. Epic refs: `Ref #9927`, `Ref #10112` only; `Closes #10952`.

## Phase 0 — Setup and measurements (read-only)

- 0.1 Read the R7/R8/R9 sections of `plugins/soleur/test/token-drift-workflow-causes.test.sh` (`SWEEP_JOB_KEYS`, the `curl` shim and its modes, the suite's hard floor and prose ledger).
- 0.2 Verify what a by-id volume GET returns from a token that cannot see the volume, and whether a Hetzner project-identity endpoint exists; record date and source.
- 0.3 Confirm labels exist (`infra-drift`, `action-required`, `priority/p1-high`, `priority/p2-medium`).
  - 0.3b Run every literal command the plan prescribes once (discoverability grep, count derivations, path checks).
  - 0.3c Measure whether an unrouted MISSED monitor emails anyone and whether `sentry_cron_monitor` supports a muted flag.
  - 0.3d File follow-up issues (a) route the monitor and (b) sole-copy follow-ups on #10430; note (c) duplicate scratch-config issues.
- 0.4 Measure current derived counts (monitors 65, distinct slugs 20).

## Phase 1 — Aggregator (item 1), tests first

- 1.1 (RED) R10 rows, evaluator-backed status table, mutation rows; raise `R78_MIN` and the hard floor with its prose ledger.
- 1.2 (GREEN) Add job `orphan-sweeps-checkin` and its comment block to `.github/workflows/scheduled-terraform-drift.yml`.
- 1.3 Add `sentry_cron_monitor.scheduled_orphan_sweeps` and the unrouted entry citing follow-up (a).
  - 1.3.1 Ledgers: README, audit-script literals, `NON_INNGEST_MONITORS`, `model.c4`, regenerate `model.likec4.json`, heartbeat `action.yml` header.
  - 1.3.2 Run `c4-count-parity`, routing-parity, `function-registry-count`, `sentry-monitors-audit` and alert-reference-gate suites.

## Phase 2 — Identity proof (item 2), tests first

- 2.1 (RED) R9 harness: anchor shim branch honouring `-o` and `-w`, `sleep` shim, scoped `-f` assertion, anchor cases, required row (d); extend N1 to an exact count of 3 copies.
- 2.2 (GREEN) Inline anchor block in both sweep steps, `identity=` published before `exit 1`, conditional failure-email subject and body.
- 2.3 Confirm R7/R8 green and the step worst case under the unchanged 6-minute bound.

## Phase 3 — Labels (item 4)

- 3.1 (RED) Label rows with the stubbed-`gh` recorder; raise the hard floor.
- 3.2 (GREEN) Labels on create in both orphan filers.

## Phase 4 — Runbook

- 4.1 Fix the two sweep rows and the residuals paragraph in `infra-credential-tiers-8209.md`; add the aggregator row.

## Phase 5 — ADR-241 (item 3)

- 5.1 Append the dated 2026-10-24 entry (line-anchored, zero deleted lines, C1 residual recorded, pointer to the aggregator comment block).

## Phase 6 — Gate and ship

- 6.1 Run the local affected gate before marking the PR ready.
- 6.2 Finish follow-up issues with dates and milestone.
- 6.3 PR body: closing keyword rules, Measured / Not measured table with dates, unrouted-monitor and MISSED statements.
- 6.4 After merge: confirm the Sentry apply converged and read the monitor by name.
