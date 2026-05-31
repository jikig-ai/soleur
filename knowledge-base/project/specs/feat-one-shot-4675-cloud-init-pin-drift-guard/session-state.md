# Session State — feat-one-shot-4675-cloud-init-pin-drift-guard

## Plan
`knowledge-base/project/plans/2026-05-30-feat-cloud-init-inngest-pin-drift-guard-plan.md`
Option 1 (CI drift-guard) per the issue's re-eval criteria.

## Implementation status
- Phase 1 (drift-guard assertion) — DONE
- Phase 2 (CI wiring) — DONE
- Phase 3 (comment + verification) — DONE
- Phase 4 (ship) — in progress

## Key deviation from plan (load-bearing)
The deepen-plan reconciliation table claimed all releases `v1.0.0…v1.1.11` exist as
`vinngest-v*` git tags. **That was false** — the remote topped out at `vinngest-v1.1.10`.
`v1.1.11` was published via two `workflow_dispatch` runs on `main` (2026-05-30
20:27/20:28 UTC, run IDs 26694105828 / 26694132933) **before** the pin-bump commit
`338ac402` (#4669, 20:45 UTC), so it never got a git tag.

A guard asserting `pin == semver-max vinngest-v* tag` would have gone **red on the
correct, currently-deployed state** (`v1.1.11 != v1.1.10`). With operator approval, the
missing tag was backfilled:

- Created annotated tag `vinngest-v1.1.11` → `338ac402` (bootstrap shape inputs
  byte-identical to the build-time tree `338ac402^`, so the tag-triggered rebuild
  reproduces the same image content).
- Pushed to origin; `build-inngest-bootstrap-image.yml` re-ran (idempotent rebuild).
- Also closes a latent `hr-tagged-build-workflow-needs-initial-tag-push` gap and restores
  git tags as the complete published-image source-of-truth.

Now `latest vinngest-v* tag == v1.1.11 == cloud-init pin`, so the guard is GREEN today and
fires only on real drift.

## Decision: softened hardcoded version regexes (Task 3.3)
The existing AC1/AC4 regexes hardcoded `v1\.1\.11`. Softened both to shape-match
`v[0-9]+\.[0-9]+\.[0-9]+`. The new AC6 dynamic guard now owns the exact-value check, and
AC6b (pin-consistency) catches partial bumps — so a future release needs only a single
cloud-init pin bump, never a parallel test-regex edit (the manual-burden class #4675 exists
to eliminate).

## Verification
- GREEN (correct state): `21/21 passed`, rc=0.
- RED (one pin ref → v1.1.10): `19/21 passed`, rc=1 (AC6 drift + AC6b consistency both fire);
  reverted byte-clean.
- All 5 `deploy-script-tests` CI-job scripts pass (rc=0 each).
- cloud-init.yml + infra-validation.yml are valid YAML.
