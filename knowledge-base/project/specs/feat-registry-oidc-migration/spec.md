---
feature: registry-oidc-migration
date: 2026-07-06
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-07-06-registry-oidc-migration-brainstorm.md
supersedes: "#6031"  # the GHCR installation-token minter approach (infeasible: GHCR refuses App tokens)
resolves_question: "#6073"  # can an App token pull GHCR? — answered: no, migrate instead
---

# Spec — Migrate container registry off GHCR to self-hosted zot (Hetzner, R2-backed)

## Problem Statement

Hetzner hosts must `docker pull` private platform images (`soleur-web-platform`,
`soleur-inngest-bootstrap`) at boot/deploy with a **zero-touch, machine-minted credential** (no
user PAT). The chosen mechanism — a control-plane Inngest minter issuing a GitHub App
installation token (ADR-088) — is **infeasible**: GHCR does not accept App installation tokens
for `docker pull` (confirmed GitHub platform limitation, community discussion #171423, no ETA).
The only GHCR credentials that pull are a user classic PAT (browser-only creation → not
automatable) and the Actions `GITHUB_TOKEN` (workflow-only). GHCR therefore cannot deliver a
zero-touch machine identity. The system currently runs on an interim classic PAT with the
minter disabled.

## Goals

- G1: Host pulls succeed with a **short-lived, control-plane-minted** credential — no user PAT on the pull path.
- G2: **Reuse** the existing Inngest minter architecture; swap only the token endpoint/target.
- G3: Preserve the cosign keyless-signing + offline-verification chain **unchanged**.
- G4: Satisfy the restricted-egress firewall (ADR-052/#5046) — registry reachable without new public egress.
- G5: Zero-downtime cutover; no credential gap (interim PAT stays live until zot pull is validated E2E).

## Non-Goals

- NG1: Making GHCR App tokens work (impossible — platform limitation).
- NG2: Escalating to GitHub support as a *blocker* (answer is public; optional informational ticket only).
- NG3: Multi-region / global registry HA beyond in-datacenter resilience (revisit if scale demands).
- NG4: Migrating third-party pinned images (e.g. `ghcr.io/sigstore/cosign` — stays where it is; only our own images move).

## Functional Requirements

- FR1: Stand up **zot** (OCI-native) in-datacenter on Hetzner with **Cloudflare R2** as the storage backend (S3-compatible driver).
- FR2: Configure zot's **OIDC bearer-token workload auth** — zot validates a control-plane-signed JWT (audience/claims TBD at plan time).
- FR3: Re-point the disabled Inngest minter (`cron-ghcr-token-minter.ts`) to mint zot JWTs into Doppler `prd` (replacing `GHCR_READ_TOKEN`/`GHCR_READ_USER`).
- FR4: Update all **push** sites to push to zot: `build-inngest-bootstrap-image.yml`, `reusable-release.yml` (build+push + cosign sign step).
- FR5: Update all **pull** sites to log in to zot: `ci-deploy.sh` (`ghcr_prelude_and_login` + inngest-bootstrap pull + cosign verifier config), `soleur-host-bootstrap.sh`, `cloud-init.yml` (fresh-boot extract + main app pull).
- FR6: Preserve cosign: verify the offline verifier fetches `.sig` from zot with the minted credential; `COSIGN_IDENTITY_REGEXP` (GitHub Actions OIDC) unchanged.
- FR7: Cutover sequence: dual-push (GHCR + zot) → validate zot pull E2E on a host → flip pull sites → retire GHCR push after soak.

<!-- lint-infra-ignore start -->
## Technical Requirements

- TR1: New Terraform: R2 bucket, zot host (Hetzner, ~CAX11), zot config, `doppler_secret` for the zot-mint credential with `lifecycle { ignore_changes = [value] }` (mirror the existing `ghcr-read-credential.tf` pattern). Every new TF var: NO operator-mint default (`hr-tf-variable-no-operator-mint-default`); the TF root must be reachable from `terraform apply` (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
- TR2: Minter keypair/JWKS for zot trust; control-plane signs, zot validates. Security-review the trust model (SECURITY DEFINER of the supply chain).
- TR3: Observability: minter failures + zot health reachable from Sentry/Better Stack without SSH (`hr-no-ssh-fallback-in-runbooks`, `hr-observability-as-plan-quality-gate`). zot-down must alert before it gates a host boot.
- TR4: Break-glass: keep interim GHCR PAT documented as fallback until zot HA is proven; do not revoke early (`decision-challenges.md` incident note).
- TR5: Rotate the exposed classic PAT (overwritten during the 2026-07-05 minter misfire).
- TR6: Retire on completion: `ghcr-read-credential.tf`, `ghcr-minter-doppler-token.tf` (or repurpose to zot), and the GHCR `GHCR_MINTER_DISABLED` gate.

<!-- lint-infra-ignore end -->

## Blast Radius (from repo-research map, 2026-07-06)

- **Push (3):** `.github/workflows/build-inngest-bootstrap-image.yml:131-194`, `.github/workflows/reusable-release.yml:425-432,580-611`, cosign sign `:626-640`.
- **Pull (6):** `apps/web-platform/infra/ci-deploy.sh:535-569` (+ `~1488` inngest pull, `600-601` cosign cfg), `soleur-host-bootstrap.sh:25-30`, `cloud-init.yml:440-452,545`.
- **Credential/IaC:** Doppler `prd` `GHCR_READ_USER`/`GHCR_READ_TOKEN`/`GHCR_MINTER_DOPPLER_TOKEN`; `ghcr-read-credential.tf`, `ghcr-minter-doppler-token.tf`, `variables.tf` (`ghcr_read_user`, `ghcr_read_token`).
- **Minter:** `apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts:83-88` (disabled gate) + test.

## Open Questions (carry to plan)

zot HA / boot-SPOF mitigation · R2-as-zot-backend spike · zot JWT trust model · cosign `.sig` fetch from zot · dual-push vs hard-flip cutover. (See brainstorm Open Questions.)
