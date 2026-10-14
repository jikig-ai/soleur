---
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-28-feat-registry-host-off-ghcr-plan.md
issue: 8714
---

# Tasks — #8714 step 5.3b-iii (registry host + deploy verifier off ghcr.io)

## PR 2a — enabling (branch feat-8714-53biii-off-ghcr)

### 1. Setup

- 1.1 Check open code-review overlap for the 2a paths (ci-deploy.sh, ci-deploy.test.sh, github.js,
  plugin-version-fallback.test.ts, new builder, new workflow).

### 2. RED

- 2.1 `apps/web-platform/infra/zot-image-oci-archive.test.sh` has these rows, and each is RED
  because the script is absent:
  - tampered blob;
  - manifest ≠ D;
  - reproducible;
  - `verify` good/tampered (first and second blob);
  - a different valid layer count.
- 2.2 `ci-deploy.test.sh` has two cosign rows, RED on the ghcr literal:
  - the ref is not ghcr.io and is `@sha256:`-pinned;
  - the gcr.io failure strings classify as `cosign_absent`.
- 2.3 `plugin-version-fallback.test.ts` has a row where the prerelease newest is skipped for the
  version and the changelog.

### 3. GREEN

- 3.1 Builder `zot-image-oci-archive.sh` (`build`, `verify`), reading D and the version from
  `zot-registry.tf`. Locally, T == `05b171f2…`.
- 3.2 In `ci-deploy.sh`, `COSIGN_IMAGE` becomes the gcr.io ref (same digest) and the classifier
  regex is extended. Update the ci-deploy.test.sh literal.
- 3.3 `github.js`: `!r.prerelease`.
- 3.4 `.github/workflows/zot-image-mirror.yml` `publish`:
  - triggers: push main (paths) and `workflow_dispatch`;
  - `contents: write`, with concurrency that never cancels;
  - it creates or uploads a missing asset and runs `verify` on an existing one;
  - the release is a prerelease with `--latest=false`, and its body names it an infra mirror
    artifact.

### 4. Verify

- 4.1 Suites: the builder test, ci-deploy.test.sh, `bun test plugins/soleur/test/plugin-version-fallback.test.ts`.
  actionlint.
- 4.2 Review, compound, ship. Hold the merge until #9071 is MERGED. `Ref #8714`.
- 4.3 Post-merge:
  - AC-A4: publish run, asset digest == T;
  - AC-A5: docs data excludes `zot-image-*`;
  - AC-A6: apply-deploy-pipeline-fix delivery, then `IMAGE_VERIFY: ok` after delivery.

## PR 2b — consuming (branch from main after 2a + #9120 merge)

### 5. RED

- 5.1 `zot-image-fetch.test.sh`:
  - verdict rows ok(C), ok(D), sha_mismatch (no load), download_failed, load_failed,
    id_mismatch, config_invalid, a stdout-polluting load stub, and state file written;
  - rendered-template rows: no non-comment ghcr.io; order sinkhole < fetch < ZOTEOF run; fetch
    not inside `doppler run`; one zot run with image `"$ZOT_IMAGE_ID"`; hosts template append.
- 5.2 Budget test row: missing mirror literal → exit 2.
- 5.3 Preflight P6 rows: absent → refuse; digest ≠ T → refuse; API error → refuse; match (not the
  first asset) → CLEAR.
- 5.4 Heartbeat rows:
  - `.Config.Image` `sha256:C`/`sha256:D` → D12; foreign → unknown;
  - `zot_image_fetch` state or `not_run`;
  - `ghcr_blocked` 1/0/unknown;
  - `zot_last_err` stays last.

### 6. GREEN

- 6.1 `zot-registry.tf`:
  - locals T/C (amd64) and the derived version, D, release and URL;
  - the map entries;
  - the amd64 precondition.
- 6.2 `registry-userdata-budget.sh` reads the new literals. Re-measure the budget.
- 6.3 `cloud-init-registry.yml`: the env file, the fetch script, the sinkhole entry, the fetch
  runcmd entry, the ZOTEOF wiring, and the heartbeat fields.
- 6.4 `scripts/registry-replace-preflight.sh` P6.
- 6.5 `zot-image-mirror.yml` `rehearse`:
  - PR plus dispatch, on ubuntu-24.04, with a two-store matrix;
  - rebuild == T and C == config before the sinkhole;
  - render the env and fetch files from the real template and fetch the real URL;
  - zot `/v2/` answers.
- 6.6 `rule-audit.yml`: the asset digest probe.
- 6.7 `registry-boot-guard.test.sh`: the field enumeration.

### 7. Docs

- 7.1 ADR-096 amendment and ADR-169 amendment.
- 7.2 C4 `model.c4` edges and descriptions. Run `c4-count-parity.test.sh` and the C4 tests.
- 7.3 `zot-image.provenance.md`: bump procedure, recovery, never delete.
- 7.4 Runbook: the `zot_image_fetch` verdict table, the recovery path, P6.

### 8. Verify and ship

- 8.1 Targeted suites:
  - fetch, the budget script and its test, registry-render-delta;
  - staleness plus its mutation test, registry-boot-guard;
  - the preflight test, the verdict test, the C4 tests.
- 8.2 On the PR head, `rehearse` (both legs), `infra-validation` and `test` are green.
- 8.3 Review, compound, ship.
  - Before merging: predict that the dispatcher delivers and that P6 is CLEAR.
  - Hold while any apply-web-platform-infra.yml run is queued or in progress.
- 8.4 Post-merge:
  - AC-L1: dispatcher → replace run success;
  - AC-L2: Better Stack boot evidence;
  - AC-L3: P6 CLEAR;
  - AC-L4: tick 5.3b-iii, evidence comment, file the web-host deny follow-up.
