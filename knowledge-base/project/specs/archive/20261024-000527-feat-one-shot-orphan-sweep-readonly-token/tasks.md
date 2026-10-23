# Tasks — feat-one-shot-orphan-sweep-readonly-token

Plan: `knowledge-base/project/plans/2026-10-23-fix-orphan-sweeps-read-only-token-and-failure-email-plan.md`

## Phase 0 — Guard rows first (RED)
- 0.1 Add R7 (no read/write Hetzner credential in any `*-orphan-sweep` job, population derived, floor >= 2) to `plugins/soleur/test/token-drift-workflow-causes.test.sh`; run it RED against the current workflow.
- 0.2 Add R8 (each sweep job emails on `failure()`, bounded, `continue-on-error`) the same way; RED.
- 0.3 Add the mutation rows of both matrices (7 + 5) and the harness rows H1-H4.

## Phase 1 — Convert both sweep jobs
- 1.1 Drop `environment:`; add main-only `if:`; bound checkout.
- 1.2 Replace the loader step with the pinned Doppler install step.
- 1.3 Replace `TOKEN="${HCLOUD_TOKEN:-}"` with the bounded, rc-checked, masked, shape-checked read of `HCLOUD_TOKEN_READONLY`.
- 1.4 Add step timeouts; keep `DOPPLER_TOKEN` in the rung-2 step.
- 1.5 Rewrite the stale comment above the sole-copy job.

## Phase 2 — Failure email
- 2.1 Rung-2: `id: notify_channel` on the existing email step; add the de-duplicated failure email. (SUPERSEDED in review: no `notify_channel` id, no de-duplication; the failure email is `failure()` alone.)
- 2.2 Inngest: add the failure email.

## Phase 3 — Floor and runbook
- 3.1 Raise the suite floor to the realized `PASS + FAIL`; comment history and guard literal agree.
- 3.2 Runbook: rows, count note (re-measure G1j), notification paragraph.

## Phase 4 — Verify
- 4.1 Run the six affected suites and the census; actionlint.
- 4.2 PR body: measured / not measured, dated; `Ref #9927`, `Ref #10112` only.
