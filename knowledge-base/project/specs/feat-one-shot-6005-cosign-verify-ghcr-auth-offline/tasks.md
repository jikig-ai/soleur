# Tasks — fix(supply-chain): cosign verify private-GHCR auth + cosign 3.x offline (#6005)

lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-fix-cosign-verify-private-ghcr-auth-offline-plan.md
Closes #6005. ENFORCE flip OUT OF SCOPE.

## Phase 0 — Preconditions (verify before coding)
- [ ] 0.1 `docker run --rm $COSIGN_IMAGE verify --help` → confirm `--offline`, `--trusted-root`, `--new-bundle-format` recognized on v3.1.1 container; paste output into spec (CLI-verify gate).
- [ ] 0.2 Generate `trusted_root.json` (`cosign initialize`) on a connected machine; run a real OFFLINE verify of the signed web-v0.188.1 digest with `--offline=true --new-bundle-format=false --trusted-root <file>` + identity-regexp/OIDC-issuer + a GHCR credential; capture evidence.
- [ ] 0.3 Confirm `COSIGN_IDENTITY_REGEXP` (ci-deploy.sh:41) still matches the live signature (no drift since #5933).
- [ ] 0.4 Confirm `DOPPLER_TOKEN` in ambient webhook env at verify time (cloud-init.yml:312) → pre-verify `doppler secrets get` feasible.
- [ ] 0.5 (H4) Enumerate every jikig-ai GHCR package the host pulls + confirm visibility. CONFIRMED: web-platform AND inngest-bootstrap BOTH private → credential must cover both.
- [ ] 0.6 (D0) Confirm with operator/CPO that PRIVATE is deliberate (not an accidental flip). If accidental → go public, delete Phase 1 + the credential machinery.

## Phase 1 — Credential provisioning (IaC)
- [ ] 1.1 Mint scoped `read:packages` credential covering BOTH packages / org-level (Decision D1) — /work attempts Playwright first (D5); route to named human gate only if reached.
- [ ] 1.2 Ordered runbook (L1): mint → write Doppler `prd_terraform` → verify present → merge `*.tf` (auto-apply propagates to `soleur/dev`+`prd`). `TF_VAR_ghcr_read_token` no default.
- [ ] 1.3 Add `doppler_secret` for `GHCR_READ_TOKEN` (+ `GHCR_READ_USER`) in `apps/web-platform/infra/*.tf` (mirror github-app.tf), dev+prd.
- [ ] 1.4 cloud-init `docker login ghcr.io` for fresh-boot t=0 (`/home/deploy/.docker/config.json`, deploy:deploy, 600, `--password-stdin`), before the first pull. Running-host login is the per-deploy one in Phase 3.

## Phase 2 — trusted_root.json (repo + cloud-init, NOT baked)
- [ ] 2.1 Commit `apps/web-platform/infra/cosign-trusted-root.json` with provenance + one-line rotation-recipe comment (no refresh script — YAGNI).
- [ ] 2.2 Deliver via cloud-init `write_files` to a stable host path (e.g. `/opt/soleur/cosign-trusted-root.json`). Do NOT `COPY` into the deploy image (H1 circular trust — image is the artifact under verification).

## Phase 3 — Rework cosign verify (ci-deploy.sh) — PIN MECHANISM (H2)
- [ ] 3.1 Add ONE early scoped Doppler fetch before the pull (:909) exporting `GHCR_READ_TOKEN`/`GHCR_READ_USER` + `SENTRY_*` into the SCRIPT env (existing download at :626 runs at ~:993, after verify). Token out of argv/logs.
- [ ] 3.2 Per-deploy `docker login ghcr.io -u $GHCR_READ_USER --password-stdin` BEFORE `docker pull` (:909, :1366) — private pull succeeds + refreshes config.json on rotation (M2).
- [ ] 3.3 Replace cosign `docker run` with Design B: NO `--network host`; `-v config.json:ro` + `-v /opt/soleur/cosign-trusted-root.json:ro` + `--offline=true --new-bundle-format=false --trusted-root=…` + existing identity/issuer flags. Exact set per Phase 0 probe.
- [ ] 3.4 Add `ghcr.io` to `cron-egress-allowlist.txt` (Design B — sandboxed container reaches GHCR).
- [ ] 3.5 Fix stale comments (:34-35 header, :499-501 "public GHCR / no auth").
- [ ] 3.6 Preserve WARN/ENFORCE semantics exactly; `IMAGE_VERIFY_MODE` default stays `warn`.

## Phase 4 — Observability
- [ ] 4.1 SENTRY_*-before-verify is delivered by 3.1's early fetch → verify_result event reaches Sentry (soak-gate visibility). Assert ordering with a test.
- [ ] 4.2 Add a loud, no-SSH failure event for the host pull (auth/denied) — load-bearing given the credential SPOF, not journald-only.
- [ ] 4.3 Add a PROACTIVE credential-expiry alarm (M2) — reactive pull-failure fires too late.

## Phase 5 — C4 + ADR + tests
- [ ] 5.1 `model.c4`: `ghcr` desc "Public"→private (`:238-240`) AND correct/remove the falsified `hetzner → sigstore` verify edge (`:312`, no live sigstore call under offline+pinned-root). Run c4-code-syntax + c4-render tests.
- [ ] 5.2 Amend ADR-082 (owns pull+verify; private credential model both packages; hr-github-app-auth-not-pat exception w/ fresh-boot-t=0 rationale + counter-cost; trusted-root provenance = repo via cloud-init, NEVER image; Design B egress). Add `principles-register.md` AP-row pointer (M3b).
- [ ] 5.3 Extend `ci-deploy.test.sh` mock-cosign: new flag/mount trace assertions (no `--network host`); SENTRY_*-before-verify ordering assertion; existing WARN-never-blocks / ENFORCE-blocks / inspect-fallback stay green.
- [ ] 5.4 File WARN→ENFORCE follow-up issue (`Ref #6005`, re-eval = clean soak).

## Acceptance (see plan §Acceptance Criteria)
Pre-merge: non-deprecated flag set + mounts + resolved egress; Phase 0 offline probe evidence in PR body; default still `warn`; ci-deploy.test.sh green; C4 fixed; ADR-082 amended; SENTRY_* before verify; `TF_VAR_*` no default + Doppler dev/prd; ENFORCE follow-up filed; `Closes #6005`.
Post-merge: infra apply clean; real signed deploy authenticates + verify PASSES offline (journald `IMAGE_VERIFY: ok`, no Sentry verify_result failure), data pulled via webhook/Sentry not SSH.
