# Tasks — fix D10 A2 attestation-manifest validation

Plan: `knowledge-base/project/plans/2026-08-09-fix-d10-a2-attestation-manifest-validation-plan.md`
Issue: 7378 · PR: 7379 · Branch: `feat-one-shot-a2-attestation-validate`
Baselines pinned 2026-08-09: restore suite **43 passed / 0 failed**, D10 suite **60 passed / 0 failed**.

## Phase 1 — RED: fixtures and failing tests

- [ ] 1.1 Add a `manifest` arm to the crane stub in `tests/scripts/test-registry-restore-from-ghcr.sh`, keyed `manifest:<ref>` via the existing `emit()`. No permissive default — a missing fixture must still exit 70.
- [ ] 1.2 Add a `blob` arm, keyed `blob:<ref>`. Assert the ref carries a digest; assert `--insecure` was present for sink-directed calls.
- [ ] 1.3 Add `fx_oci_index` helper — synthesized index JSON with one amd64 child and one attestation child (`vnd.docker.reference.type=attestation-manifest`, `platform: unknown/unknown`).
- [ ] 1.4 Add `fx_oci_manifest` helper — synthesized single manifest, plus an attestation-manifest variant whose one layer is `application/vnd.in-toto+json`. Do **not** name these `write_manifest` (taken: it writes the restore-pins manifest).
- [ ] 1.5 New case: positive control — index with in-toto attestation child restores green (red before Phase 3).
- [ ] 1.6 New case: platform-layer blob missing → exit 4.
- [ ] 1.7 New case: attestation blob absent at the sink → exit 4.
- [ ] 1.8 New case: `gzip: invalid header` maps to the new named class, not exit 6.
- [ ] 1.9 Update the 4 existing verification-2 cases + `ok_fixtures()` with single-manifest fixtures so non-index behaviour stays pinned.
- [ ] 1.10 Add index-shape A2 fixtures to `tests/scripts/test-registry-pull-path-health.sh` (its own `crane_stub`, driving the engine via `REGISTRY_RESTORE_CRANE_CMD`).
- [ ] 1.11 Confirm RED: new cases fail for the *expected* reason, not a harness error.

## Phase 2 — GREEN (contract): classify()

- [ ] 2.1 Add a named `LAYERFORMAT` arm to `classify()` in `scripts/registry-restore-from-ghcr.sh` matching `gzip: invalid header`.
- [ ] 2.2 Map `LAYERFORMAT` to **exit 4** (verification failure), never 6. Exit 6 stays reserved for genuinely unnameable shapes.
- [ ] 2.3 Task 1.8 goes green.

## Phase 3 — GREEN (consumer): per-child verification 2

- [ ] 3.1 Add the repo-derivation helper: strip `@digest`, then strip a trailing `:tag` **only** when the colon falls after the last `/` (protects the sink's `host:port`).
- [ ] 3.2 Read `crane manifest $SINK_TLS_FLAG "$dst"` at the **sink**; classify read failures on the existing NETWORK/DENIED/other arms (3/5/4).
- [ ] 3.3 No `.manifests` → single manifest → `crane validate --remote "$dst"` exactly as today. Behaviour unchanged.
- [ ] 3.4 Index → per child: attestation (`vnd.docker.reference.type == "attestation-manifest"` **OR** `platform.architecture == "unknown"`) → read its manifest, then `crane blob <repo>@<digest> > /dev/null` for its config and every layer.
- [ ] 3.5 Index → per child: platform child → `crane validate --remote <repo>@<digest>`.
- [ ] 3.6 Tasks 1.5–1.7 go green; the 4 pre-existing verification-2 cases stay green.

## Phase 4 — Runbook + ADR

- [ ] 4.1 `registry-luks-recut-6929.md`: extend the exit-4 row to name a layer-format mismatch.
- [ ] 4.2 Same file: correct the exit-6 row — no longer reachable via attestation manifests.
- [ ] 4.3 Same file, cold-vehicle section: record that the throwaway-zot rehearsal executed live for the **first time** (run 31333047132) and what it found.
- [ ] 4.4 Amend `ADR-169-what-authorizes-destroying-the-sole-pull-path.md`: A2's blob-completeness obligation is per-child; attestation children verified by presence, not decompression; record the near-miss as evidence for the independence criterion. **No new ordinal.**

## Phase 5 — Verification

- [ ] 5.1 Restore suite ≥ 47 passed / 0 failed.
- [ ] 5.2 D10 suite ≥ 60 passed / 0 failed.
- [ ] 5.3 Revert-check: temporarily restore the whole-ref `crane validate` and confirm the positive control goes RED (proves the test is load-bearing, not vacuous).
- [ ] 5.4 `bash scripts/test-all.sh` green; record which commit the full run covered.
- [ ] 5.5 Scope assertion: `git diff origin/main...HEAD -- tests/scripts/lib/registry-luks-recut-gate.sh tests/scripts/lib/stock-preflight-gate.sh .github/workflows/apply-web-platform-infra.yml` is empty.
- [ ] 5.6 Plan citation sweep prints no BROKEN lines.
