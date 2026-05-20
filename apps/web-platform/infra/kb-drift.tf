# PR-H (#3244) Phase 5 — KB-drift walker IaC.
#
# Provisions:
#   - 1 random_id for the HMAC signing key (POSTed payload auth between
#     the GH Actions cron and /api/internal/kb-drift-ingest).
#   - 1 doppler_secret in NEW `prd_kb_drift_walker` config — separate
#     config means the Doppler service token issued from this config can
#     only read these two secrets (blast-radius scope).
#   - 1 doppler_secret for KB_DRIFT_INGEST_URL — overrideable per env.
#   - 1 github_actions_secret publishing the Doppler service token as
#     the repo Actions secret DOPPLER_TOKEN_KB_DRIFT (consumed by the
#     `.github/workflows/kb-drift-walker.yml` cron).
#
# OPERATOR NOTE: the `prd_kb_drift_walker` Doppler config must exist in
# the soleur project BEFORE first apply. It is NOT TF-managed today
# because the DopplerHQ/doppler provider's `doppler_environment` resource
# manages environments-and-their-configs as a unit, and the operator's
# existing environment+configs are not under TF management. Create the
# config once via the Doppler dashboard (Project → soleur → New config
# under `prd` environment, name = "prd_kb_drift_walker"); deferred-
# automation issue tracks lifting this to TF.

resource "random_id" "kb_drift_ingest_signing_key" {
  byte_length = 32
}

resource "doppler_secret" "kb_drift_ingest_signing_key" {
  project    = "soleur"
  config     = "prd_kb_drift_walker"
  name       = "KB_DRIFT_INGEST_SIGNING_KEY"
  value      = "kbdrift-${random_id.kb_drift_ingest_signing_key.hex}"
  visibility = "masked"
  # NO ignore_changes — rotation is `terraform apply -replace=random_id.kb_drift_ingest_signing_key`.
}

resource "doppler_secret" "kb_drift_ingest_url" {
  project    = "soleur"
  config     = "prd_kb_drift_walker"
  name       = "KB_DRIFT_INGEST_URL"
  value      = "https://soleur.ai/api/internal/kb-drift-ingest"
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

# GH Actions secret for the cron workflow. Requires `var.github_actions_token`
# with `repo` scope on jikig-ai/soleur. Operator mints the token once and
# stores it in `prd_terraform` Doppler config under TF_VAR_github_actions_token.
resource "github_actions_secret" "doppler_token_kb_drift" {
  repository  = "soleur"
  secret_name = "DOPPLER_TOKEN_KB_DRIFT"
  # Operator-supplied Doppler service token scoped to prd_kb_drift_walker.
  # Mint at: https://dashboard.doppler.com/workplace/{...}/projects/soleur/
  #   prd_kb_drift_walker → Access → Service Tokens → Generate.
  plaintext_value = var.doppler_token_kb_drift

  lifecycle {
    ignore_changes = [plaintext_value]
  }
}
