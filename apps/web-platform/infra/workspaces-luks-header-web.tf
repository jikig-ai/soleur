# apps/web-platform/infra/workspaces-luks-header-web.tf
#
# #9377 (ADR-263 R4 narrowing) — the WEB-HOST-CLASS header-escrow bucket and the secrets delivered
# to web hosts born through the fresh-boot path (hcloud_server.web[*], cloud-init). Before this file
# a fresh host's token read prd_workspaces_luks, which also holds web-1's escrow credential pair, so
# a leak from a fresh host exposed web-1's header bucket. A fresh host now reads
# prd_workspaces_luks_web (doppler_config.workspaces_luks_web, workspaces-luks-fresh-boot.tf) and
# escrows into its OWN bucket with its OWN bucket-scoped R2 pair.
#
# THE PASSPHRASE IS INDEPENDENT (#9377 decision A1). WORKSPACES_LUKS_KEY below comes from its OWN
# random_password.workspaces_luks_web, NOT from random_password.workspaces_luks (web-1's). A holder of
# the web-class token no longer reads web-1's passphrase through this config; a web-class leak yields
# the web-class passphrase only. This NARROWS the exposure, it does not prove isolation: both configs
# sit in one Doppler project, both passphrases live in one Terraform state, and one provider token
# writes both. The pre-split fresh-boot token still reads web-1's config until it is retired (#9377),
# so the statement holds for NEW web-class births only. Because the passphrases are independent, a
# future luksChangeKey on web-1 is no longer a two-host re-key. The only copies of the web-class
# passphrase are this Doppler secret and the Terraform state; the escrowed header cannot open a volume
# alone. NEVER `-replace` either password: a rotated value is cut from the old one with no surviving copy
# of the old one, so the volume is unopenable on the next boot. prevent_destroy below is the plan-time
# layer and the push-apply HALT (luks_passphrase_rotations) is the CI layer; the supported way to rotate a
# populated volume is a header re-key followed by an intentional state change under review.
#
# RETIRING THE WEB-CLASS CONFIG is NOT a push-apply change. Removing random_password.workspaces_luks_web or
# doppler_secret.workspaces_luks_web_key from this file plans a `delete` (or a `forget` for a `removed {}` block)
# at an address the push-apply's rotation HALT (luks_passphrase_rotations) counts, and that HALT has no
# acknowledgement path, so every push-apply would stop until a person used [skip-web-platform-apply] on each merge.
# Retirement needs a dedicated, operator-run state change, planned and reviewed on its own. Likewise a `create` at
# these addresses is legal ONLY until the first web-class volume is formatted: the HALT lets a first create through
# because it cannot tell it from state loss, and after the first format a `create` here would mint a passphrase
# that opens nothing.
#
# SEPARATE FILE by design: workspaces-luks.test.sh's A11 guard is file-scoped to workspaces-luks.tf,
# workspaces-luks-header.test.sh pins workspaces-luks-header.tf, and #9348 edits workspaces-luks.tf. A new
# file escapes all three, so workspaces-luks-header-web.test.sh replicates the cardinality and
# no-`config = "prd"` guards and adds the web-1-config exclusion.
#
# What lives here: the bucket, the web-class passphrase and three doppler_secrets (key, bucket name, S3 endpoint).
# What does NOT live here: the R2 S3 access-key-id + secret-access-key. Same constraint as
# workspaces-luks-header.tf (learning 2026-05-18-cla-evidence-r2-s3-creds-not-derived.md): a
# bucket-scoped R2 API token's S3 pair is not derivable from a cloudflare_api_token attribute, and no
# Terraform input carries it (hr-tf-variable-no-operator-mint-default). The pair is minted separately
# and written into prd_workspaces_luks_web; until it exists the provisioner records escrow=missing,
# which withholds the soak marker and pages a person (Sentry stage workspaces_luks_provision_escrow, #9377), and the
# birth routes refuse to start without the pair's names (scripts/web-host-escrow-preflight.sh, which runs
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

# The web-class passphrase (#9377 decision A1): generated independently of web-1's random_password.workspaces_luks,
# so no value in this file or its Doppler copy derives from web-1's. Same generator shape as web-1's (40 chars,
# no special characters: every consumer treats the value as a shell-safe token). prevent_destroy turns a replace
# or destroy into a plan-time error; it does not cover an `update` of the Doppler copy or a state `forget`, which
# the push-apply's luks_passphrase_rotations counter stops. No ignore_changes and no keepers: nothing may pin
# or perturb the value outside review.
resource "random_password" "workspaces_luks_web" {
  length  = 40
  special = false

  lifecycle {
    prevent_destroy = true
  }
}

# The passphrase a web-class host reads at first boot and at every reopen (workspaces-luks-provision.sh,
# workspaces-luks-reopen.sh, luks-monitor.sh). In-graph: the value IS random_password.workspaces_luks_web, so the
# Doppler copy cannot drift from the generator. `masked` like every other copy of it.
resource "doppler_secret" "workspaces_luks_web_key" {
  project    = "soleur"
  config     = doppler_config.workspaces_luks_web.name
  name       = "WORKSPACES_LUKS_KEY"
  value      = random_password.workspaces_luks_web.result
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
