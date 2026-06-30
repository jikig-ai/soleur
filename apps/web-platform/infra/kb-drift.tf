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
#
# Rotation policy (post-#4150):
#   - `random_id.kb_drift_ingest_signing_key`: rotate via
#     `terraform apply -replace=random_id.kb_drift_ingest_signing_key`.
#     Re-roll cascades to `doppler_secret.kb_drift_ingest_signing_key`.
#   - `doppler_service_token.kb_drift`: rotate via
#     `terraform apply -replace=doppler_service_token.kb_drift`. The new
#     `key` value MUST propagate to `github_actions_secret.doppler_token_kb_drift.plaintext_value` —
#     this file deliberately omits `lifecycle.ignore_changes = [plaintext_value]`
#     on that resource so rotation reaches the consumer in the same apply.
#     Mirrors the discipline in inngest.tf:97-104 but with inverse polarity
#     (rotation MUST propagate, not be suppressed).

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

# App-runtime copies of the two secrets the ingest ROUTE reads at request time.
# The walker (Doppler `prd_kb_drift_walker`) SIGNS; the Next.js route running in
# the app runtime (Doppler `prd`) VERIFIES + attributes rows — both sides must
# share the same values or the route fails closed with HTTP 500. The walker's
# blast-radius scope is unaffected: its read-only service token still only sees
# `prd_kb_drift_walker`; these add the verify-side keys to the app's own config.
resource "doppler_secret" "kb_drift_ingest_signing_key_app_runtime" {
  project    = "soleur"
  config     = "prd"
  name       = "KB_DRIFT_INGEST_SIGNING_KEY"
  value      = "kbdrift-${random_id.kb_drift_ingest_signing_key.hex}"
  visibility = "masked"
  # NO ignore_changes — must share rotation polarity with the prd_kb_drift_walker
  # copy above; a `-replace=random_id.kb_drift_ingest_signing_key` rotation has to
  # cascade to BOTH or the verifier freezes while the signer rotates → 401 storm.
}

resource "doppler_secret" "kb_drift_operator_founder_id_app_runtime" {
  project    = "soleur"
  config     = "prd"
  name       = "KB_DRIFT_OPERATOR_FOUNDER_ID"
  value      = var.kb_drift_operator_founder_id
  visibility = "masked"
  # NO ignore_changes — value flows from the variable; an operator update SHOULD
  # propagate at apply. The founder UUID is a stable identity, never auto-rotated.
}

resource "doppler_secret" "kb_drift_ingest_url" {
  project = "soleur"
  config  = "prd_kb_drift_walker"
  name    = "KB_DRIFT_INGEST_URL"
  # app.soleur.ai is the canonical Next.js app host. The apex soleur.ai is the
  # Cloudflare static marketing site and returns 405 Not Allowed for POST.
  # NO ignore_changes — TF must enforce the app.soleur.ai host; a drifted value
  # pointing at the apex silently breaks the walker cron with HTTP 405 (#4210).
  value      = "https://app.soleur.ai/api/internal/kb-drift-ingest"
  visibility = "masked"
}

# Doppler service token minted in-band by Terraform. The workplace-scope
# DOPPLER_TOKEN_TF (provider auth) has scope to create config-scoped service
# tokens. Closes the operator-mint requirement called out in #4150.
# access = "read" — kb-drift cron only reads secrets; do NOT widen to "write".
# autonomy-considered: provider-mint-applied.
resource "doppler_service_token" "kb_drift" {
  project = "soleur"
  config  = "prd_kb_drift_walker"
  name    = "kb-drift-ci-tf"
  access  = "read"
}

# GH Actions secret for the cron workflow. Token value minted in-band by
# `doppler_service_token.kb_drift` above; integrations/github provider
# authenticates via App-installation auth (see main.tf) with secrets:write
# scope on the soleur-ai App. Pre-existing `prd_kb_drift_walker` config is
# still a precondition (see operator note above).
#
# NO ignore_changes on plaintext_value — rotation is
# `terraform apply -replace=doppler_service_token.kb_drift` and the new
# token MUST propagate to the published Actions secret, or the cron would
# continue using a revoked token.
resource "github_actions_secret" "doppler_token_kb_drift" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_KB_DRIFT"
  plaintext_value = doppler_service_token.kb_drift.key
}
