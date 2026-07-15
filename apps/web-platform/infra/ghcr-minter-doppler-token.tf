# #6031 / ADR-088 — control-plane GHCR installation-token minter: Doppler plumbing.
#
# The minter (apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts)
# mints a 1h packages:read GitHub App installation token every 20 min and writes it
# to Doppler as GHCR_READ_TOKEN, retiring the interim read:packages PAT (ADR-087 D1,
# #6011). The two consumer read-secrets doppler_secret.ghcr_read_token/_user in
# `prd` are OWNED BY #6011 (ghcr-read-credential.tf, ignore_changes=[value]) — this
# file does NOT re-declare them; the minter writes their VALUES at runtime and
# ignore_changes keeps terraform from clobbering the churn.
#
# CONTINGENCY TAKEN — prd-scoped write token (plan Phase 2.2/R2 fallback).
# The original design used a dedicated `prd_ghcr` branch config to bound the write
# token's AT-REST blast radius. That requires Doppler CONFIG INHERITANCE, which this
# workspace's Doppler plan does NOT have ("Doppler Error: Your workplace does not
# have access to config inheritance" — 2026-07-05 apply-web-platform-infra failure on
# `doppler_config.prd_ghcr`). Per the plan's pre-declared fallback, the write token is
# `prd`-scoped instead, and the minter writes GHCR_READ_TOKEN/GHCR_READ_USER directly
# into `prd` (where consumers already read them — no cross-config reference flip).
#
# BLAST RADIUS (security-sentinel sign-off — see ADR-088 amendment):
#   - A `prd`-scoped read/write service token can read AND write EVERY `prd` secret,
#     not just the GHCR keys — a strictly larger AT-REST surface than the (unavailable)
#     prd_ghcr-scoped token would have been. This is the R2 cost the throwaway config
#     was meant to avoid.
#   - ACCEPTED because, per the CTO ruling (2026-07-05), the RUNTIME blast radius is
#     unchanged either way: the org-wide-WRITE GITHUB_APP_PRIVATE_KEY that the minter
#     signs with is ALREADY co-resident in web-1's `prd` container env (cloud-init
#     downloads `--config prd`), a strictly larger capability than "read/write prd
#     secrets". The delta is at-rest exposure of the write token's scope only.
#   - The #5274 control-plane-separation HARD GATE (ADR-088 amendment) already
#     mandates relocating BOTH GITHUB_APP_PRIVATE_KEY AND GHCR_MINTER_DOPPLER_TOKEN
#     off the shared/tenant `prd` env before the first tenant host; this fallback does
#     not enlarge that gate's scope (same two credentials, same relocation).
#
# State: doppler_service_token.ghcr_minter.key is Computed + Sensitive — the value
# lands in terraform.tfstate (R2-backed encrypted bucket, same posture as
# doppler_service_token.write). It CANNOT be re-read from the Doppler API after
# create; rotation is `terraform apply -replace=doppler_service_token.ghcr_minter`,
# which propagates the new .key to GHCR_MINTER_DOPPLER_TOKEN in the same apply
# (no ignore_changes on that secret, mirroring doppler-write-token.tf).
#
# autonomy-considered: provider-mint-applied (doppler_service_token).
# dev intentionally NOT provisioned — hosts read `--config prd` only (hr-dev-prd-distinct).

resource "doppler_service_token" "ghcr_minter" {
  project = "soleur"
  config  = "prd"
  name    = "ghcr-minter-write"
  access  = "read/write"
}

# Surfaces the write token into the minter runtime via the existing single
# `--config prd` env-file path — the `> /etc/default/webhook-deploy` write in
# cloud-init.yml. NO ignore_changes: a `-replace` rotation of the token must
# reach the runtime in the same apply.
resource "doppler_secret" "ghcr_minter_doppler_token" {
  project = "soleur"
  config  = "prd"
  name    = "GHCR_MINTER_DOPPLER_TOKEN"
  value   = doppler_service_token.ghcr_minter.key
}
