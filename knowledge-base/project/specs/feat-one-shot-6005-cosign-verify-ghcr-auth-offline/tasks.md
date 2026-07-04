# Tasks — fix(supply-chain): cosign verify private-GHCR auth + cosign 3.x offline (#6005)

lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-fix-cosign-verify-private-ghcr-auth-offline-plan.md
Closes #6005. ENFORCE flip OUT OF SCOPE.

## Phase 0 — Preconditions (verify before coding)
- [ ] 0.1 `docker run --rm $COSIGN_IMAGE verify --help` → confirm `--offline`, `--trusted-root`, `--new-bundle-format` recognized on v3.1.1 container; paste output into spec (CLI-verify gate).
- [ ] 0.2 Generate `trusted_root.json` (`cosign initialize`) on a connected machine; run a real OFFLINE verify of the signed web-v0.188.1 digest with `--offline=true --new-bundle-format=false --trusted-root <file>` + identity-regexp/OIDC-issuer + a GHCR credential; capture evidence.
- [ ] 0.3 Confirm `COSIGN_IDENTITY_REGEXP` (ci-deploy.sh:41) still matches the live signature (no drift since #5933).
- [ ] 0.4 Confirm `DOPPLER_TOKEN` in ambient webhook env at verify time (cloud-init.yml:312) → pre-verify `doppler secrets get` feasible.

## Phase 1 — Credential provisioning (IaC)
- [ ] 1.1 Mint scoped `read:packages` credential (Decision D1) — /work attempts Playwright first (D5); route to named human gate only if reached.
- [ ] 1.2 Add `doppler_secret` for `GHCR_READ_TOKEN` (+ `GHCR_READ_USER`) in `apps/web-platform/infra/*.tf` (mirror github-app.tf), dev+prd; `variables.tf` `TF_VAR_*` no default. Confirm value in `prd_terraform` before `*.tf` merge (auto-apply sequencing).
- [ ] 1.3 Add host `docker login ghcr.io` to cloud-init writing `/home/deploy/.docker/config.json` (deploy:deploy, 600, `--password-stdin`), before the first pull (fresh-boot parity).

## Phase 2 — trusted_root.json (repo + image build)
- [ ] 2.1 Commit `apps/web-platform/infra/cosign-trusted-root.json` with provenance + rotation-cadence header.
- [ ] 2.2 Bake into deploy image (`COPY`) OR cloud-init `write_files` — stable `--trusted-root` mount source across fresh+running hosts.
- [ ] 2.3 Add committed refresh script + deliberate-PR rotation note (no runtime TUF fetch).

## Phase 3 — Rework cosign verify (ci-deploy.sh)
- [ ] 3.1 Ensure docker config available to cosign container (host login OR scoped `DOCKER_CONFIG` from pre-verify `doppler secrets get`).
- [ ] 3.2 Replace `docker run --rm $COSIGN_IMAGE verify --offline …` with the 3.x set: `--network host` (or ghcr.io allowlist per D3) + `-v config.json:ro` + `-v trusted_root.json:ro` + `--offline=true --new-bundle-format=false --trusted-root=…` + existing identity/issuer flags. Exact set per Phase 0 probe.
- [ ] 3.3 Ensure host `docker pull` (:909, :1366) runs after the host login (private pull succeeds).
- [ ] 3.4 Fix stale comments (:34-35 header, :499-501 "public GHCR / no auth").
- [ ] 3.5 Preserve WARN/ENFORCE semantics exactly; `IMAGE_VERIFY_MODE` default stays `warn`.

## Phase 4 — WARN telemetry reaches Sentry
- [ ] 4.1 Set `SENTRY_*` before `verify_image_signature` runs (pre-verify `doppler secrets get` of the 3 vars, or move env-load earlier) — verify_result event must reach Sentry (soak-gate visibility).
- [ ] 4.2 Add a loud, no-SSH failure event for the host pull itself (auth/denied) — not journald-only.

## Phase 5 — C4 + ADR + tests
- [ ] 5.1 `model.c4:238-240` "Public GHCR" → private; run c4-code-syntax + c4-render tests.
- [ ] 5.2 Amend ADR-082 (private credential model + hr-github-app-auth-not-pat exception + trusted_root decision).
- [ ] 5.3 Extend `ci-deploy.test.sh` mock-cosign: new flag/mount/egress trace assertions; existing WARN-never-blocks / ENFORCE-blocks / inspect-fallback stay green.
- [ ] 5.4 File WARN→ENFORCE follow-up issue (`Ref #6005`, re-eval = clean soak).

## Acceptance (see plan §Acceptance Criteria)
Pre-merge: non-deprecated flag set + mounts + resolved egress; Phase 0 offline probe evidence in PR body; default still `warn`; ci-deploy.test.sh green; C4 fixed; ADR-082 amended; SENTRY_* before verify; `TF_VAR_*` no default + Doppler dev/prd; ENFORCE follow-up filed; `Closes #6005`.
Post-merge: infra apply clean; real signed deploy authenticates + verify PASSES offline (journald `IMAGE_VERIFY: ok`, no Sentry verify_result failure), data pulled via webhook/Sentry not SSH.
