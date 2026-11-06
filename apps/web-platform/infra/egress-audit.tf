# #9545 / ADR-288 — bearer token for the egress audit rollup ingest.
#
# Vector (on each web host) posts closed 15-minute buckets to
# POST /api/internal/egress-audit-ingest on the same host. The route and Vector both read
# this secret from Doppler `soleur/prd` at process start (Vector already runs under
# `doppler run --config prd`, soleur-host-bootstrap.sh), so no unit, drop-in or Terraform
# variable carries it: the value is minted here and nowhere else
# (hr-tf-variable-no-operator-mint-default). The dedicated inngest host uses a different
# Doppler project, never receives it and runs no gateway, so the sink never fires there.
#
# ROTATION (#11920 — the route accepts the current AND the previous token, so the web hosts do not
# have to restart in lockstep; scripts/key-rotate.sh drives all four legs):
#   1. apply-A: terraform apply -replace=random_id.egress_audit_ingest_token (mints the new
#      current) and -replace=doppler_secret.egress_audit_ingest_token_previous with
#      TF_VAR_egress_audit_ingest_token_previous=<the pre-apply read of the old CURRENT> —
#      one apply writes PREVIOUS=old AND CURRENT=new;
#   2. redeploy the app so it reads CURRENT+PREVIOUS, then restart Vector on every web host
#      (the ci-deploy `restart vector` webhook lever — Vector resolves the token via
#      `doppler run` only at process start);
#   3. clear apply: terraform apply -replace=doppler_secret.egress_audit_ingest_token_previous
#      with the variable at its default "" once every host reports a fresh vector restart.
# The empty string is the honest cleared sentinel — the ingest route skips empty values
# (apps/web-platform/server/egress-audit-ingest.ts configuredTokens).
#
# State exposure: like the GitHub webhook secret in github-app.tf the value sits in Terraform
# state. It authenticates a same-host hop only and rotates by one apply; ADR-288 records that
# anything able to read the app environment can forge rows.
resource "random_id" "egress_audit_ingest_token" {
  byte_length = 32
}

resource "doppler_secret" "egress_audit_ingest_token" {
  project    = "soleur"
  config     = "prd"
  name       = "EGRESS_AUDIT_INGEST_TOKEN"
  value      = "eai-${random_id.egress_audit_ingest_token.hex}"
  visibility = "masked"
  # NO ignore_changes — rotation is operator-explicit via -replace.
}

# #11920 — the grace-window PREVIOUS token. Written ONLY by `-replace` inside the rotate
# and clear applies above (never by a routine apply): `ignore_changes = [value]` makes
# targeted applies diff-free on it, so the scheduled drift check sees no noise and a merge
# apply cannot early-clear the grace token — the same lifecycle pattern the four
# inngest_* rotate secrets use, and the derivation
# plugins/soleur/test/terraform-target-parity.test.ts uses to require flag `replace` for
# its gate-table row. The value lands in terraform.tfstate like the CURRENT token's
# (the disclosure above applies verbatim — a same-host-hop credential, ADR-288).
resource "doppler_secret" "egress_audit_ingest_token_previous" {
  project    = "soleur"
  config     = "prd"
  name       = "EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS"
  value      = var.egress_audit_ingest_token_previous
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}
