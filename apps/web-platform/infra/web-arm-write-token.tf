# --- #6438: dedicated Doppler token for the no-SSH measured-beat ARM gate (ADR-117 automated) ---
# The apply-workflow arm gate (apply-web-platform-infra.yml) arms a web-host heartbeat via ADR-117's
# live-API-verified sequence: PATCH {paused:false} → poll `status` until `up` (a real beat landed) →
# roll back to {paused:true} + fail the apply loud if `up` never arrives within period+grace (a
# paused BS heartbeat exposes NO ping timestamp, so status-transition is the only measurable signal).
# The PATCH is a WRITE to the Better Stack API, whose token (BETTERSTACK_API_TOKEN, in
# soleur/prd_terraform) the provider already uses.
#
# WHY A DEDICATED TOKEN (mirrors inngest-arm-write-token.tf): the arm step reads BETTERSTACK_API_TOKEN
# through THIS handle rather than the general-purpose ci-tf-write / DOPPLER_TOKEN, so the arm write
# path has its own named, revocable Doppler credential. It is READ on Doppler (the account-wide R+W
# lives in the Better Stack token itself, not here).
#
# BLAST RADIUS (P2-E — recorded HONESTLY in the amended ADR-117): Better Stack API tokens are
# ACCOUNT-WIDE read/write with NO per-monitor scope — the ONLY scoping axis is Doppler. And a Doppler
# service token is CONFIG-scoped, so this token exposes the whole soleur/prd_terraform config, not a
# single secret ("exposing only the arm secret" is the intent, bounded by Doppler's config
# granularity, not achieved literally). The arm gate's conditional injection
# (`inputs / state-gated`) + the read-only Doppler access bound the exposure; the account-wide BS
# blast radius is the residual, documented in ADR-117's risk section.
#
# No new operator-mint var (hr-tf-variable-no-operator-mint-default): reuses the existing global
# Better Stack provider token. State storage: `.key` is Computed + Sensitive; recover via -replace
# (mints a new token, orphans the old — revoke via `doppler configs tokens revoke`). NO
# lifecycle.ignore_changes → a -replace rotation propagates the new key to the consumer in the same
# apply.
#
# autonomy-considered: provider-mint-applied (Doppler service token + GitHub repo secret via the TF App).
resource "doppler_service_token" "web_arm_write" {
  project = "soleur"
  config  = "prd_terraform"
  name    = "web-arm-read" # distinct from ci-tf-write; read-only for the measured-beat arm gate
  access  = "read"
}

# Published as a REPO-level github_actions_secret (the TF GitHub App cannot write ENVIRONMENT
# secrets — see doppler_token_inngest_arm's comment for the 403 precedent). Readable by every
# workflow (same class as DOPPLER_TOKEN_WRITE); bounded by the arm step's op/state gate. NO
# lifecycle.ignore_changes → a token -replace propagates here in the same apply.
resource "github_actions_secret" "doppler_token_web_arm" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_WEB_ARM"
  plaintext_value = doppler_service_token.web_arm_write.key
}
