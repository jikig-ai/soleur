# Tasks — feat-one-shot-11294-11711-rotation-audit

Plan: `knowledge-base/project/plans/2026-11-04-feat-random-id-rotation-audit-plan.md`
Issues: #11294 (audit tail), #11711 (rotation census). Agent-side scope only — every rotation/deletion is an Operator Hold.

## 1. Audit findings artifact (`audit-findings-11294.md`)

- 1.1 Inventory every job in `apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml`, `infra-validation.yml`, `inngest-provision-rehearsal.yml`, `cf-lb-overlay.yml`, `key-rotate.yml`, `inngest-key-rotate.yml` that invokes `terraform`; classify streamed / captured / none.
- 1.2 Write the per-job verdict row (mechanism, reached-retained-public-log?, sink, retention window, closing-PR timestamps #11551/#11674/#11930, residual gap window).
- 1.3 Resolve the `drift-check` 89-hit attribution via the ordered hypotheses in the plan (census TSV → git-history scan → `mechanism unresolved — bounded`).
- 1.4 Carry forward the preservation-record deltas (686 deletions, 498+74+234 cleanup, rescan 0) and every `## Known gaps` row.
- 1.5 Record the housekeeping flag verdict (branch `feat-one-shot-11294-redact-random-id-logs` absent in both clones — stale flag).

## 2. Rotation census artifact (`rotation-census-11711.md`)

- 2.1 One row per `random_id`/`random_password` resource — 27 rows across `apps/web-platform/infra` (12+10), `inngest-provision-rehearsal/` (2+2), `rung2-rehearsal/` (0+1).
- 2.2 Fill exposure verdict, route, readiness state, gating issues per row.
- 2.3 Per-secret readiness note: exact `gh workflow run` shape, confirm token, refusing gates today, verification readback, failure shapes.
- 2.4 Ordering note (dev shakedown → dedicated pair via `inngest-key-rotate.yml` → kb_drift → prd manual trigger → webhook last → tunnel separate-last).

## 3. Issue comments

- 3.1 Post ONE comment to #11294 (audit-tail results + holds + artifact pointers).
- 3.2 Post ONE comment to #11711 (census results + holds + artifact pointers). Never close, never edit bodies.

## 4. Final consistency

- 4.1 Re-verify cited issue/PR states.
- 4.2 `git status` shows only files under `knowledge-base/project/{plans,specs}/`.
- 4.3 Self-check grep for secret-shaped values in the new artifacts before commit.

## Operator Holds (recorded, never worked)

- `key-rotate.yml`/`inngest-key-rotate.yml` dispatches; any `terraform -replace`/apply on real state; Doppler writes; remaining log/artifact deletion; the comments/bodies residual decision; closing or editing #11294/#11711; the webhook post-rotation owner step.
