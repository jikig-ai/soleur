# #6031 / ADR-088 — control-plane GHCR installation-token minter: Doppler plumbing.
#
# The minter (apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts)
# mints a 1h packages:read GitHub App installation token every 20 min and writes it
# to Doppler as GHCR_READ_TOKEN, retiring the interim read:packages PAT (ADR-087 D1,
# #6011). The two consumer read-secrets doppler_secret.ghcr_read_token/_user in
# `prd` are OWNED BY #6011 (ghcr-read-credential.tf, ignore_changes=[value]) — this
# file does NOT re-declare them.
#
# BLAST RADIUS (deepen-plan security + CTO ruling on ADR-088, 2026-07-05):
#   - The minter's WRITE credential is a `prd_ghcr`-SCOPED read/write service token:
#     an isolated leak of the token string (tfstate, dashboard) grants write to that
#     one throwaway config only — never a prd-wide read of GITHUB_APP_PRIVATE_KEY.
#     This at-rest scope bound is the isolation that actually matters and it is free.
#   - The token's `.key` is surfaced into the minter RUNTIME as a plain `prd` secret
#     (GHCR_MINTER_DOPPLER_TOKEN), landing in web-1's container via the EXISTING single
#     `doppler secrets download --config prd` → `--env-file` path (cloud-init.yml:554).
#     Deliberately NOT a second cloud-init `--config prd_ghcr` download (CTO ruling Q1,
#     rejected option A): that would distribute a control-plane-only WRITE credential
#     onto every fresh TENANT host — the exact escalation the #5274 control-plane
#     separation exists to prevent — and add fail-closed risk to the cold-boot path
#     for a credential tenant hosts never use (they only READ GHCR_READ_TOKEN).
#   - CPO SIGN-OFF (threshold single-user-incident, requires_cpo_signoff): `prd` gains
#     a `prd_ghcr`-write credential readable by every `prd` principal (CI, terraform
#     runner, the app process). ACCEPTED because those principals already read the
#     co-resident org-wide-WRITE GITHUB_APP_PRIVATE_KEY (a strictly larger capability),
#     and true control-plane-only injection of BOTH the App key AND this write token is
#     deferred to the #5274 cutover gate (ADR-088 amendment enumerates both).
#
# CROSS-CONFIG READ REFERENCES (NOT in this file — apply-time, mint-first ordered):
#   `prd`.GHCR_READ_TOKEN/GHCR_READ_USER are flipped to `${soleur.prd_ghcr.…}`
#   references via a live Doppler value change (permitted by #6011's
#   ignore_changes=[value]; not a terraform resource attribute). ORDERING INVARIANT
#   (CTO ruling Q2 / plan Phase 0.4a): (1) create prd_ghcr [this apply] → (2) minter
#   writes a VALID GHCR_READ_TOKEN into prd_ghcr and it is verified → (3) ONLY THEN
#   flip the two `prd` secrets to references. Flip-before-populate resolves EMPTY and
#   breaks `docker login` on every host. This flip is the Phase-6 cutover step.
#
# State: doppler_service_token.ghcr_minter.key is Computed + Sensitive — the value
# lands in terraform.tfstate (R2-backed encrypted bucket, same posture as
# doppler_service_token.write). It CANNOT be re-read from the Doppler API after
# create; rotation is `terraform apply -replace=doppler_service_token.ghcr_minter`,
# which propagates the new .key to GHCR_MINTER_DOPPLER_TOKEN in the same apply
# (no ignore_changes on that secret, mirroring doppler-write-token.tf).
#
# autonomy-considered: provider-mint-applied (doppler_config + doppler_service_token).
# dev intentionally NOT provisioned — hosts read `--config prd` only (hr-dev-prd-distinct).

resource "doppler_config" "prd_ghcr" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_ghcr"
}

resource "doppler_service_token" "ghcr_minter" {
  project = "soleur"
  config  = doppler_config.prd_ghcr.name
  name    = "ghcr-minter-write"
  access  = "read/write"
}

# Surfaces the prd_ghcr-scoped write token into the minter runtime via the existing
# single `--config prd` env-file path (CTO ruling Q1, option B). NO ignore_changes:
# a `-replace` rotation of the token must reach the runtime in the same apply.
resource "doppler_secret" "ghcr_minter_doppler_token" {
  project = "soleur"
  config  = "prd"
  name    = "GHCR_MINTER_DOPPLER_TOKEN"
  value   = doppler_service_token.ghcr_minter.key
}
