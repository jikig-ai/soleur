# #8609 / ADR-241 D10 — the isolated home of the soleur-ai runtime App key.
#
# WHY A PROJECT. The key used to live in `soleur/prd`, and every `prd` or `prd_*` reader
# inherits `prd` — including the branch-reachable repository-secret tokens. A branch config
# does not isolate (learnings/security-issues/2026-07-07-doppler-branch-config-does-not-
# isolate-secrets.md); only a separate project does. No `soleur` token can read this one.
#
# WHY THIS FILE HOLDS NO SECRET, NO TOKEN AND NO DATA SOURCE. This root's state
# (`web-platform/terraform.tfstate`) is readable by the Tier-A `prd_terraform` backend keys
# (ADR-241 D3/D4), so anything Terraform mints or reads here is branch-readable. A
# `doppler_secret`, a `doppler_service_token` or a `data "doppler_secret(s)"` on this
# project would put the key, or a token that reads it, straight back where #8609 removes
# it from. The operator puts the key in and mints the host's read token by hand (runbook
# infra-credential-tiers-8209.md, "Runtime App key (#8609)"); the token reaches this root
# only as the Tier-B variable `github_app_runtime_doppler_token`, and only as a hash in
# state (hcloud's user_data hash; the deploy_pipeline_fix trigger hashes the KEYLESS render,
# so no plan context sees the token, census row G6o). Census Guard 6 (tests/scripts/test-infra-privileged-tier-census.sh) enforces all of
# this. Same carrier shape as infra-privileged-environment.tf.
#
# Every resource here is in the push apply's `-target=` list (apply-web-platform-infra.yml).

resource "doppler_project" "github_app_runtime" {
  name = "soleur-github-app"
  # Doppler caps `description` at 255 (scripts/lint-doppler-description-length.py).
  description = "#8609 ADR-241 D10: the soleur-ai runtime GitHub App private key, isolated from every soleur prd/prd_* reader. Read only by the web host's operator-minted token (Tier B). Operator-supplied; never in tfstate."

  lifecycle {
    # Holds the only copy of the live runtime key after R6. A destroy disconnects every user.
    prevent_destroy = true
  }
}

# A TF-created project is born bare (no configs); the environment creates the `prd` root
# config the host's read token is scoped to. Mirrors doppler_environment.infra_privileged_prd.
resource "doppler_environment" "github_app_runtime_prd" {
  project = doppler_project.github_app_runtime.name
  slug    = "prd"
  name    = "Production"

  lifecycle {
    prevent_destroy = true
  }
}

# The parking place for the OLD key between R0 and R7 (GITHUB_APP_PRIVATE_KEY_RETIRED, used
# only for R7's final `401` probe). A branch config, so the host's token — scoped to the
# `prd` ROOT config — cannot read it. The provider has no `doppler_branch_config`; in
# DopplerHQ/doppler 1.21.2 a branch config is a `doppler_config` whose name carries the
# environment prefix (same shape as doppler_config.git_data_prd, git-data-luks.tf).
resource "doppler_config" "github_app_runtime_prd_retired" {
  project     = doppler_project.github_app_runtime.name
  environment = doppler_environment.github_app_runtime_prd.slug
  name        = "prd_retired"

  lifecycle {
    # Destroying it before R7 loses the parked key, and with it the only proof the old key is dead.
    prevent_destroy = true
  }
}
