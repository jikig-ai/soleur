# apps/web-platform/infra/workspaces-luks-header.tf
#
# #6649 (part of epic #6604 / ADR-119) — the off-host LUKS header-escrow bucket + its
# host-delivery secrets for the /workspaces LUKS cutover freeze path (C4: "the LUKS header
# is an independent terminal limb").
#
# SEPARATE FILE by design: workspaces-luks.tf's A11 guard (workspaces-luks.test.sh) asserts
# file-scoped EXACT cardinality (one doppler_secret / one doppler_service_token / one
# random_password / one hcloud_volume, and config = "prd" nowhere). Adding any escrow
# doppler_secret INTO that file turns A11 RED. This file carries its own parallel
# addition-blind guard in workspaces-luks-header.test.sh.
#
# What lives here:
#   - the R2 bucket the header backup is uploaded to (DISTINCT from soleur-terraform-state —
#     the tfstate bucket holds random_password.workspaces_luks.result in plaintext state, so
#     co-locating the header there would collapse the C4 "different blast radius" property).
#   - the bucket NAME + the S3 endpoint, delivered to web-1 via the pinned prd_workspaces_luks
#     read (mirroring WORKSPACES_LUKS_KEY).
#
# What does NOT live here (learning 2026-05-18-cla-evidence-r2-s3-creds-not-derived.md):
#   - the R2 S3 access-key-id + secret-access-key. Those are a dashboard/Playwright-minted
#     R2 API Token (32-char id + 64-char secret), NOT derivable from any cloudflare_api_token
#     field (sha256(token.value) fails SigV4). They are written into prd_workspaces_luks as a
#     post-merge operator step, masked. See ADR-119 addendum + the PR's post-merge AC.

locals {
  # Path-style R2 S3 endpoint (account-root; the bucket goes in the S3 PATH, not a host
  # suffix). Derived from var.cf_account_id rather than re-hardcoding the account hash — the SAME
  # account owns the tfstate backend (main.tf's `backend "s3"` block hardcodes the hash because a
  # backend cannot interpolate vars/locals), so deriving here avoids ADDING a second literal that
  # could drift; the one backend literal is an unavoidable backend-config constraint, not a drift risk.
  r2_s3_endpoint = "https://${var.cf_account_id}.r2.cloudflarestorage.com"
}

# The default cf_api_token is scoped "Tunnel, Access, DNS, Notifications" and lacks Workers
# R2 Storage:Edit (verified 2026-07-18 by a live 403 on GET /accounts/<id>/r2/buckets — not
# asserted from the var description). So the bucket is created via the dedicated cloudflare.r2
# provider alias (main.tf), whose token var.cf_api_token_r2 must be provisioned into
# prd_terraform BEFORE merge (ADR-065: an unprovisioned no-default var fails the whole apply).
resource "cloudflare_r2_bucket" "workspaces_luks_header" {
  provider   = cloudflare.r2
  account_id = var.cf_account_id
  name       = "soleur-workspaces-luks-header"
  # cloudflare/cloudflare v4.x: `location` (renamed from `location_hint`). WEUR matches the
  # EU residency posture of the encrypted workspace data. Mirrors apps/cla-evidence bucket.tf.
  location = "WEUR"

  lifecycle {
    prevent_destroy = true
  }
}

# The bucket NAME the host reads (workspaces-cutover.sh: WORKSPACES_HEADER_BUCKET). A REFERENCE
# to the resource, never a literal — this is what makes "distinct from tfstate" correct by
# construction (and what the wiring test asserts is a reference, not the literal
# soleur-terraform-state).
resource "doppler_secret" "workspaces_luks_header_bucket" {
  project    = "soleur"
  config     = "prd_workspaces_luks"
  name       = "WORKSPACES_HEADER_BUCKET"
  value      = cloudflare_r2_bucket.workspaces_luks_header.name
  visibility = "masked"
}

# The S3 endpoint the host reads (workspaces-cutover.sh: WORKSPACES_HEADER_R2_ENDPOINT).
resource "doppler_secret" "workspaces_luks_header_r2_endpoint" {
  project    = "soleur"
  config     = "prd_workspaces_luks"
  name       = "WORKSPACES_HEADER_R2_ENDPOINT"
  value      = local.r2_s3_endpoint
  visibility = "masked"
}
