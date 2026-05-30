---
lane: procedural
plan: knowledge-base/project/plans/2026-05-30-feat-cloud-init-inngest-pin-drift-guard-plan.md
---

# Tasks: cloud-init inngest-bootstrap pin drift-guard (#4675)

## Phase 1 — Drift-guard assertion (RED → GREEN)

- [x] 1.1 Write the failing assertion first: add a drift check to
  `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` that compares the pin to a
  deliberately-wrong expected value; confirm it FAILs (cq-write-failing-tests-before).
- [x] 1.2 Implement pin extraction:
  `grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" | head -1 | sed 's/.*://'`.
- [x] 1.3 Implement latest-tag extraction:
  `git -C "$SCRIPT_DIR" tag --list 'vinngest-v*' | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`
  (do NOT depend on `--show-toplevel`; use `git -C "$SCRIPT_DIR"`).
- [x] 1.4 Add the 3-branch assertion: no-tags → SKIP (no FAIL); pin==latest → PASS;
  pin!=latest → FAIL with a message naming both values + the fix location.
- [x] 1.5 Add the pin-consistency sub-check: all 3 `soleur-inngest-bootstrap:vX.Y.Z` refs
  share one tag (`DISTINCT==1`).
- [x] 1.6 Run `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → green
  (with tags fetched: drift PASSes; without: SKIPs).

## Phase 2 — CI wiring (the load-bearing step)

- [x] 2.1 In `.github/workflows/infra-validation.yml` `deploy-script-tests` job, add
  `with: { fetch-depth: 0, fetch-tags: true }` to its `actions/checkout` (keep pinned SHA).
- [x] 2.2 Add an explicit `run: bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  step alongside the other 4 infra tests.
- [x] 2.3 Validate workflow YAML (`actionlint`; `bash -c` the extracted run snippet).

## Phase 3 — Comment + verification

- [x] 3.1 Append a sentence to cloud-init.yml's pin comment (L453-461) noting drift is now
  enforced by the test via Infra Validation; do NOT change the pin value; keep AC2 phrases
  (`MUST be bumped`, `NOT the inngest-cli version`) intact.
- [x] 3.2 Negative proof: temporarily edit one pin ref to `v1.1.10` → test FAILs (drift +
  consistency); capture output for PR body; revert.
- [x] 3.3 Decide inline whether to soften the hardcoded `v1.1.11` regexes in AC1/AC4 to a
  shape match (`v[0-9]+\.[0-9]+\.[0-9]+`) so the dynamic guard owns the exact-value check.

## Phase 4 — Ship

- [ ] 4.1 Push branch; open PR with `Closes #4675`; paste negative-proof output.
- [ ] 4.2 QA/review; merge.
