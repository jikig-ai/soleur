# Better Stack Logs ingest token for the dedicated arm64 Inngest host's Vector shipper (#6197).
#
# The dedicated host (cax11, arm64, 10.0.1.40) runs vector.service under
# `doppler run --project soleur-inngest --config prd`, so BETTERSTACK_LOGS_TOKEN must live in
# the ISOLATED soleur-inngest project's `prd` root config — it currently exists only in
# soleur/prd (the co-located web host reads it there). This mirrors ghcr-read-credential.tf:
# a `doppler_secret` whose value comes from a sensitive, no-default var sourced from Doppler
# `prd_terraform` (Approach B — only the one 24-char token enters terraform.tfstate, NOT the
# ~116-secret soleur/prd map a `data.doppler_secrets` mirror would materialize).
#
# The provider already manages the soleur-inngest project (inngest-host.tf: doppler_project.inngest),
# so it has write access. The boot isolation self-check (cloud-init-inngest.yml) admits this token
# by NAME — deleting it post-cutover FATALs the whole bootstrap (loud fail > silent log blind spot).
#
# Provisioning ORDER (do NOT skip): copy BETTERSTACK_LOGS_TOKEN from soleur/prd into
# soleur/prd_terraform (the TF runner's TF_VAR source) → verify read-only via `doppler secrets get`
# → THEN the additive `inngest_host` dispatch applies this pure-create resource. TF_VAR_betterstack_logs_token
# has NO default (hr-tf-variable-no-operator-mint-default). dev is intentionally NOT provisioned:
# the dark arm64 host reads `--config prd` exclusively (hr-dev-prd-distinct).

resource "doppler_secret" "inngest_betterstack_logs_token" {
  # Reference the TF-managed project + env (NOT string literals) so Terraform builds the
  # dependency edge — the project/config are created by doppler_project.inngest +
  # doppler_environment.inngest_prd (inngest-host.tf), and a literal would let this secret
  # schedule before they exist ("Could not find requested config 'prd'") on a cold apply AND
  # would not be pulled in by a `-target` of the project. Mirrors the sibling dedicated secrets.
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "BETTERSTACK_LOGS_TOKEN"
  value      = var.betterstack_logs_token
  visibility = "masked"

  lifecycle {
    # Value churn (rotation) is managed at the source of truth (Better Stack / Doppler),
    # not this file — mirrors ghcr-read-credential.tf / github-app.tf. The isolation
    # self-check keys on the NAME, so a rotate is safe (the name persists).
    ignore_changes = [value]
  }
}
