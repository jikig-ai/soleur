# Inngest server IaC (#3960, PR-F follow-up).
#
# Provisions:
#   - 4 random_id resources for INNGEST_SIGNING_KEY / INNGEST_EVENT_KEY ({prd,dev}).
#     Self-hosted Inngest per ADR-030; signing/event keys are operator-chosen randoms
#     (no dashboard issuance flow). 32 bytes => 64 hex chars; SDK accepts the
#     `signkey-<env>-<hex>` shape (see node_modules/inngest/helpers/strings.js).
#   - 5 doppler_secret resources (4 Inngest keys + 1 heartbeat URL for prd).
#   - 1 betteruptime_heartbeat (60s period, 30s grace) — free-tier email alerts.
#   - Conditional betteruptime_policy gated by var.betterstack_paid_tier.
#
# Plan deviations vs. 2026-05-18-feat-pr-f-inngest-iac-plan.md (recorded in PR commit):
#   - Inngest 4 secrets are TF-generated via random_id instead of operator-minted
#     variables. Plan [ack] block shrinks 3 → 1.
#   - Doppler provider authenticates via a single workplace-scope personal token
#     (TF_VAR_DOPPLER_TOKEN_TF) instead of two per-config service tokens.
#     CTO's two-alias typo-prevention intent is met via resource naming (_prd/_dev)
#     + explicit `config = "..."` on every doppler_secret. Acceptable for
#     alpha-internal scope (brand-survival threshold = aggregate pattern).
#   - Variables: 7 → 3 (doppler_token_tf, betterstack_api_token, betterstack_paid_tier).

locals {
  # Pinned via Phase 0.3 — bump in this PR diff (visibility preserved).
  # Source: https://github.com/inngest/inngest/releases/tag/v1.19.4
  inngest_cli_version = "v1.19.4"
  inngest_cli_sha256  = "d023b26659275fdbe9348b6518077ce1ea9906a449898e49ddced91bfc6fd757"
}

# ---------------- Inngest signing/event keys (random) ----------------

resource "random_id" "inngest_signing_key_prd" {
  byte_length = 32
}

resource "random_id" "inngest_signing_key_dev" {
  byte_length = 32
}

resource "random_id" "inngest_event_key_prd" {
  byte_length = 32
}

resource "random_id" "inngest_event_key_dev" {
  byte_length = 32
}

# ---------------- Doppler secrets (per-env) ----------------

resource "doppler_secret" "inngest_signing_key_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_SIGNING_KEY"
  value      = "signkey-prod-${random_id.inngest_signing_key_prd.hex}"
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # rotate out-of-band; do not churn on every apply.
  }
}

resource "doppler_secret" "inngest_signing_key_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "INNGEST_SIGNING_KEY"
  value      = "signkey-test-${random_id.inngest_signing_key_dev.hex}"
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "doppler_secret" "inngest_event_key_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.inngest_event_key_prd.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "doppler_secret" "inngest_event_key_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.inngest_event_key_dev.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

# ---------------- Better Stack heartbeat ----------------

resource "betteruptime_heartbeat" "inngest_prd" {
  name      = "soleur-inngest-server-prd"
  period    = 60
  grace     = 30
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Paused until the operator confirms inngest-server is running on the host
  # (`deploy inngest <image> <tag>` succeeded). Otherwise, the gap between
  # `terraform apply` (heartbeat created → BetterStack starts expecting pings
  # within 30s grace) and the first systemd-timer ping would trigger a false
  # email alert. Unpause via the Better Stack UI OR by flipping this attribute
  # to `false` in a follow-up commit after deploy. Runbook documents both
  # paths. See plan deviation note in inngest.tf header.
  paused     = true
  team_name  = "Jean's team"
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies.
    ignore_changes = [paused]
  }
}

resource "betteruptime_policy" "inngest" {
  count = var.betterstack_paid_tier ? 1 : 0

  name           = "soleur-inngest-server-policy"
  incident_token = null
  repeat_count   = 3
  repeat_delay   = 60

  steps {
    type        = "escalation"
    wait_before = 0
    urgency_id  = null
    step_members {
      type = "current_on_call"
    }
  }
}

# ---------------- Heartbeat URL → Doppler (prd-only) ----------------
# Doppler-mediated coupling: TF writes the URL into Doppler prd; the server's
# existing `doppler secrets download` flow at boot/deploy time picks it up.
# Single-pass apply: Terraform's dependency graph wires up automatically.

resource "doppler_secret" "inngest_heartbeat_url_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.inngest_prd.url
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # URL is stable per heartbeat resource lifetime.
  }
}
