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
# ROTATION (the route accepts the current AND the previous token, so the web hosts do not
# have to restart in lockstep):
#   1. copy the current value to EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS in Doppler soleur/prd;
#   2. terraform apply -replace=random_id.egress_audit_ingest_token  (mints the new current);
#   3. redeploy the app and restart Vector so both pick up the new current token;
#   4. clear EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS once both have restarted.
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
