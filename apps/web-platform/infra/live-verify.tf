# live-verify.tf — synthetic prod verification principal (#5452)
#
# The live-verification harness (apps/web-platform/scripts/live-verify/) drives
# the DEPLOYED app under a dedicated synthetic Supabase principal to catch the
# realtime/server-commit-timing bug class that mock e2e structurally cannot
# (the #5391/#5421/#5436 broken-fix cycle). Per hr-tf-variable-no-operator-mint-default,
# the principal's password is Soleur-generated (no operator-mint variable) and
# published to Doppler prd; the seed script (seed-live-verify-user.sh) reads it
# to create/upsert the synthetic auth user.
#
# Rotation (leak response):
#   terraform apply -replace=random_password.live_verify_user
#   then: doppler run -p soleur -c prd -- bash scripts/seed-live-verify-user.sh
#   then: auth.admin sign-out-all for the synthetic UID (revokes live sessions).
#
# special=false keeps the value JSON/shell-safe in the seed script's admin-API
# curl body; length 40 alphanumeric is ~238 bits of entropy.

resource "random_password" "live_verify_user" {
  length  = 40
  special = false
}

resource "doppler_secret" "live_verify_user_password" {
  project    = "soleur"
  config     = "prd"
  name       = "LIVE_VERIFY_USER_PASSWORD"
  value      = random_password.live_verify_user.result
  visibility = "masked"
  # NO ignore_changes — rotation is operator-explicit via -replace (mirrors
  # random_id.github_webhook_secret in github-app.tf).
}
