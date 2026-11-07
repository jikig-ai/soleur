# Bearer token for the legal-acceptance status endpoint, one per Doppler config (#12196, ADR-319 PR-D, ADR-320 scope note).
#
# What it is: the read-only token that GET /api/internal/legal-acceptance/<key> checks (route.ts TOKEN_RE accepts 48 to 256
# characters of [A-Za-z0-9._~+/=-]) and that the ship hold gate sends (plugins/soleur/scripts/lib/bearer-fetch.sh keeps the same
# bound). Its reach is four fields about one founder's decision (status, text_hash, decided_at, row_ok); it never returns the
# free-text note and never writes. That is why it sits outside ADR-320 decision 1: the file was reviewed under decision 4 and
# applied as proposed. Adding a write path, a non-GET method or a wider response re-triggers that review and moves the token
# out of Terraform.
#
# Not here on purpose: LEGAL_ACCEPTANCE_FOUNDER_ID. The operator enters the Supabase auth user uuid per Doppler project and
# checks it against that project's auth.users. Until both values exist and the web app is redeployed, the endpoint answers 503.
#
# State exposure: both random_password.result and doppler_secret.value are written to terraform.tfstate in the R2 state
# bucket, which the Tier-A read pair can read (ADR-241 residual R2); the bucket has no versioning and no lock (ADR-006). The
# Doppler prd config is readable by the agent by design (the hold evaluator reads it). Rotating the value does not repair a
# leak, because the next run writes the new value to the same readable state; a leak is handled by treating the token as
# public and keeping its reach at four read-only fields. If the token ever gains write reach it must leave Terraform.
#
# Rotation: replace the random_password (-replace=random_password.legal_acceptance_verify_token_prd or _dev). There is no
# ignore_changes on the secrets, so the new value reaches Doppler on that run. No dispatch target offers a generic replace for
# a random_password, so this is a local, operator-approved command under Tier-B credentials, not an automated route. A hand
# edit in Doppler is reverted by the next per-merge run and flagged by the scheduled drift check.
#
# special = false is written explicitly: the provider default is true, and a symbol outside the route's class would make the
# endpoint refuse the token and break the shell helper's handling of it. The two configs use two independent generators, so
# dev and prd never share a value (apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts holds all of this against
# the route's bound).
resource "random_password" "legal_acceptance_verify_token_prd" {
  length  = 48
  special = false
}

resource "random_password" "legal_acceptance_verify_token_dev" {
  length  = 48
  special = false
}

resource "doppler_secret" "legal_acceptance_verify_token_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "LEGAL_ACCEPTANCE_VERIFY_TOKEN"
  value      = random_password.legal_acceptance_verify_token_prd.result
  visibility = "masked"
  # NO ignore_changes: rotation is operator-explicit via -replace and must reach Doppler.
}

resource "doppler_secret" "legal_acceptance_verify_token_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "LEGAL_ACCEPTANCE_VERIFY_TOKEN"
  value      = random_password.legal_acceptance_verify_token_dev.result
  visibility = "masked"
  # NO ignore_changes: rotation is operator-explicit via -replace and must reach Doppler.
}
