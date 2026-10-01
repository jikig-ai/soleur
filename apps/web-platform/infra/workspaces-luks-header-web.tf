# apps/web-platform/infra/workspaces-luks-header-web.tf
#
# #9377 (ADR-263 R4 narrowing) — the WEB-HOST-CLASS header-escrow bucket and the secrets delivered
# to web hosts born through the fresh-boot path (hcloud_server.web[*], cloud-init). Before this file
# a fresh host's token read prd_workspaces_luks, which also holds web-1's escrow credential pair, so
# a leak from a fresh host exposed web-1's header bucket. A fresh host now reads
# prd_workspaces_luks_web (doppler_config.workspaces_luks_web, workspaces-luks-fresh-boot.tf) and
# escrows into its OWN bucket with its OWN bucket-scoped R2 pair.
#
# WHAT THE SPLIT DOES NOT DO. WORKSPACES_LUKS_KEY below is the SAME passphrase web-1's volume uses (it
# is a reference to random_password.workspaces_luks, so a rotation cannot drift between the two
# configs). A holder of the web-class token still reads web-1's passphrase; the split narrows which
# R2 credential and which bucket that holder reaches, not the shared passphrase (ADR-263 records the
# shared-passphrase residual and its constraint on any future luksChangeKey). NEVER `-replace` the
# password from here.
#
# SEPARATE FILE by design: workspaces-luks.test.sh's A11 guard is file-scoped to workspaces-luks.tf,
# workspaces-luks-header.test.sh pins workspaces-luks-header.tf, and #9348 edits workspaces-luks.tf. A new
# file escapes all three, so workspaces-luks-header-web.test.sh replicates the cardinality and
# no-`config = "prd"` guards and adds the web-1-config exclusion.
#
# What lives here: the bucket and three doppler_secrets (key, bucket name, S3 endpoint).
# What does NOT live here: the R2 S3 access-key-id + secret-access-key. Same constraint as
# workspaces-luks-header.tf (learning 2026-05-18-cla-evidence-r2-s3-creds-not-derived.md): a
# bucket-scoped R2 API token's S3 pair is not derivable from a cloudflare_api_token attribute, and no
# Terraform input carries it (hr-tf-variable-no-operator-mint-default). The pair is minted separately
# and written into prd_workspaces_luks_web; until it exists the provisioner records escrow=missing,
# which withholds the soak marker (the first birth after the split must not precede it, see
# scripts/check-web-host-escrow-config.sh --live).
#
# Provider alias, endpoint local and the 403 note on the default token: see workspaces-luks-header.tf
# (this file reuses local.r2_s3_endpoint and the cloudflare.r2 alias; it declares neither).
#
# autonomy-considered: provider-mint-applied (R2 bucket via the cloudflare.r2 alias + Doppler secrets via
# the TF doppler provider; the R2 pair is the deferred mint, tracked on #9377).
resource "cloudflare_r2_bucket" "workspaces_luks_header_web" {
  provider   = cloudflare.r2
  account_id = var.cf_account_id
  name       = "soleur-workspaces-luks-header-web"
  # WEUR is a PLACEMENT HINT, not a jurisdiction (the workspaces-luks-header.tf paragraph, #7624): this
  # bucket sits on Cloudflare's `default` jurisdiction and custody by Cloudflare, Inc. (US) is a Chapter V
  # transfer wherever the bytes rest. Do NOT cite this line as an EU-residency safeguard.
  location = "WEUR"

  lifecycle {
    prevent_destroy = true
  }
}

# The passphrase a web-class host reads at first boot and at every reopen (workspaces-luks-provision.sh,
# workspaces-luks-reopen.sh, luks-monitor.sh). In-graph: the value IS the existing random_password, so
# the two configs cannot drift on rotation. `masked` like every other copy of it.
resource "doppler_secret" "workspaces_luks_web_key" {
  project    = "soleur"
  config     = doppler_config.workspaces_luks_web.name
  name       = "WORKSPACES_LUKS_KEY"
  value      = random_password.workspaces_luks.result
  visibility = "masked"
}

# The bucket NAME the host escrows into: a REFERENCE to the web-class bucket, never a literal (and never
# the web-1 bucket or the tfstate bucket).
resource "doppler_secret" "workspaces_luks_web_header_bucket" {
  project    = "soleur"
  config     = doppler_config.workspaces_luks_web.name
  name       = "WORKSPACES_HEADER_BUCKET"
  value      = cloudflare_r2_bucket.workspaces_luks_header_web.name
  visibility = "masked"
}

# The S3 endpoint the host escrows through (account-root, path-style; local.r2_s3_endpoint is declared in
# workspaces-luks-header.tf).
resource "doppler_secret" "workspaces_luks_web_header_r2_endpoint" {
  project    = "soleur"
  config     = doppler_config.workspaces_luks_web.name
  name       = "WORKSPACES_HEADER_R2_ENDPOINT"
  value      = local.r2_s3_endpoint
  visibility = "masked"
}
