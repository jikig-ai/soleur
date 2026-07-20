# Inngest server IaC (#3960, PR-F follow-up).
#
# Provisions:
#   - 6 random_id resources: INNGEST_SIGNING_KEY / INNGEST_EVENT_KEY ({prd,dev})
#     + INNGEST_MANUAL_TRIGGER_SECRET ({prd,dev}, #4734).
#     Self-hosted Inngest per ADR-030; signing/event keys are operator-chosen randoms
#     (no dashboard issuance flow). 32 bytes => 64 hex chars; SDK accepts the
#     `signkey-<env>-<hex>` shape (see node_modules/inngest/helpers/strings.js).
#     The manual-trigger secret is opaque to the SDK (a bare 64-hex Bearer value
#     consumed by POST /api/internal/trigger-cron — no signkey- prefix needed).
#   - 7 doppler_secret resources (4 Inngest keys + 1 heartbeat URL for prd
#     + 2 manual-trigger secrets {prd,dev}).
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
  # #6178: the amd64 SHA above is the default (co-located web host + amd64 dedicated host).
  # The dedicated inngest host is DUAL-ARCH (local.inngest_arch, inngest-host.tf): on an arm64
  # (cax*) type it downloads the linux_arm64 tarball and verifies against the arm64 checksum
  # below (the amd64 SHA would fail that verify). Both from the same signed checksums.txt v1.19.4:
  #   https://github.com/inngest/inngest/releases/download/v1.19.4/checksums.txt
  inngest_cli_sha256_arm64 = "30a3f01474cb2266c24545cdc83930baeae14232d629c87aeeb8f21118948199"
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

# Manual-trigger Bearer secret (#4734) — opaque 64-hex, consumed by
# POST /api/internal/trigger-cron. Distinct random per env (prd != dev).
resource "random_id" "inngest_manual_trigger_secret_prd" {
  byte_length = 32
}

resource "random_id" "inngest_manual_trigger_secret_dev" {
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
    ignore_changes = [value] # see signing_key_prd above — rotate via `terraform taint random_id.<name>`.
  }
}

resource "doppler_secret" "inngest_event_key_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.inngest_event_key_prd.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # see signing_key_prd above — rotate via `terraform taint random_id.<name>`.
  }
}

resource "doppler_secret" "inngest_event_key_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.inngest_event_key_dev.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # see signing_key_prd above — rotate via `terraform taint random_id.<name>`.
  }
}

# Manual-trigger Bearer secret (#4734) — opaque .hex (no signkey- prefix; the
# value is compared verbatim by the route's timingSafeEqual, not parsed by the
# Inngest SDK).
resource "doppler_secret" "inngest_manual_trigger_secret_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_MANUAL_TRIGGER_SECRET"
  value      = random_id.inngest_manual_trigger_secret_prd.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # see signing_key_prd above — rotate via `terraform taint random_id.<name>`.
  }
}

resource "doppler_secret" "inngest_manual_trigger_secret_dev" {
  project    = "soleur"
  config     = "dev"
  name       = "INNGEST_MANUAL_TRIGGER_SECRET"
  value      = random_id.inngest_manual_trigger_secret_dev.hex
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # see signing_key_prd above — rotate via `terraform taint random_id.<name>`.
  }
}

# ---------------- Durable backend secrets (#5450) ----------------
# Self-hosted Redis password (prd) — the queue/run-state store's auth. Generated
# via random_password (hashicorp/random, already declared for random_id), NOT an
# operator-mint sensitive var (hr-tf-variable-no-operator-mint-default). special
# = false keeps it URL-safe inside the redis://:<pw>@127.0.0.1:6379 URI that
# inngest-server + inngest-redis ExecStart build. prd-only: the durable Inngest
# server is prd-only (dev runs ephemeral local `inngest dev`, no --redis-uri).
resource "random_password" "inngest_redis_password_prd" {
  length  = 48
  special = false
}

resource "doppler_secret" "inngest_redis_password_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_REDIS_PASSWORD"
  value      = random_password.inngest_redis_password_prd.result
  visibility = "masked"

  lifecycle {
    # ROTATE by replacing BOTH resources together (verified #5560):
    #   terraform apply -replace=random_password.inngest_redis_password_prd \
    #                   -replace=doppler_secret.inngest_redis_password_prd
    # A lone `taint random_password` regenerates the value in tfstate but
    # ignore_changes=[value] below SUPPRESSES the doppler_secret update, so Doppler
    # (and the running inngest) keep the OLD password — an incomplete rotation.
    # Re-creating the doppler_secret (the second -replace) writes the new value on
    # create (ignore_changes applies to updates, not create). Redeploy inngest after.
    ignore_changes = [value]
  }
}

# INNGEST_POSTGRES_URI (prd) — provisioned OUT-OF-BAND, NOT a TF resource (mirrors
# the BETTERSTACK_LOGS_TOKEN pattern below). The value is the session-pooler
# (:5432, NEVER transaction :6543 — breaks inngest's sqlc prepared statements)
# connection string for the dedicated EU Inngest Supabase project:
#   project: soleur-inngest-prd  ref: pigsfuxruiopinouvjwy  region: eu-west-1
#   host: aws-0-eu-west-1.pooler.supabase.com:5432  user: postgres.<ref>  db: postgres
# Created 2026-06-17 via the Supabase Management API (#5450; org Jikig AI is on
# Pro → this is a ~$10/mo Micro-compute project, recorded in expenses.md). The
# db password lives ONLY in Doppler prd + the project. It is intentionally not a
# `doppler_secret` resource: the URI embeds a project-side secret TF never minted,
# and a doppler_secret would clobber the real value on first create (ignore_changes
# only engages after the resource is in state). Rotation: rotate the project DB
# password in the Supabase dashboard → re-set INNGEST_POSTGRES_URI in Doppler prd
# (stdin, never argv). Live-verified: inngest v1.19.4 connects + migrates on :5432
# (runbook § Durable backend, verdict 0.5).
#
# SECURITY POSTURE — RLS lockdown (2026-06-29, ADR-030 I8). This project's public
# tables (Inngest's own schema) have RLS enabled + anon/authenticated grants revoked,
# remediating the rls_disabled_in_public advisor finding. Inngest is unaffected: it
# connects as the `postgres` owner over this pooler (owner bypasses non-forced RLS).
# The lockdown is a versioned SQL artifact auto-applied via the Management API, NOT a
# TF resource (same out-of-band rationale as this URI):
#   apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql
#   .github/workflows/apply-inngest-rls.yml  (merge-apply + daily self-heal)

# ---------------- Pooler config + inngest pool footprint (#5558 → #6258) ------
# During the #5558 EMAXCONNSESSION recovery, the dedicated inngest project's
# Supavisor pooler `default_pool_size` was raised 15 → 30 LIVE via the Supabase
# Management API. This is uncommitted out-of-band drift (it lives in the project
# config, not in any repo file) — VERIFIED live 2026-06-18 via the Management API
# (GET https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/config/database/pgbouncer
# → {"default_pool_size":30,"pool_mode":"transaction"}).
#
# SUPERSEDED INVARIANT (#5558/#5559 → corrected by #6258, ADR-105): the prior record
# here claimed the client cap `--postgres-max-open-conns 10` bounded inngest's TOTAL
# connection count under 15. That is FALSE. --postgres-max-open-conns is PER-POOL,
# not total: `inngest start` opens ~P separate Postgres pools (queue/state/history/api),
# each honouring the cap independently, so `10` × ~3 pools ratcheted to ~31 pinned idle
# conns > pool_size 30 → EMAXCONNSESSION under back-to-back cutover-probe scans (#6258).
#
# CURRENT FIX (#6258, ADR-105): bound the TOTAL footprint + drain idle conns at the
# CLIENT — `--postgres-max-open-conns 5 --postgres-max-idle-conns 2
# --postgres-conn-max-idle-time 1` (idle-time in MINUTES). Worst-case total = P×5 ≤ 20
# for P ≤ 4, comfortably under pool_size 30. See inngest-bootstrap.sh.
#
# ⚠ TWO-HOST CORRECTION (#6178, 2026-07-10): the "≤ 20 < 30" budget above is PER
# HOST. During the pre-flip cutover window there are TWO co-located inngest schedulers
# on this SHARED prod pooler — web-1 (10.0.1.10) AND web-2 (10.0.1.11, weight-0 warm
# standby) — so the aggregate ceiling is 2 × P×5 = 40 > pool_size 30. Capping only web-1
# (the deploy.soleur.ai active host) does NOT bound the pair, which is why op=inventory
# still hit EMAXCONNSESSION after web-1 was capped: web-2's co-located inngest was
# UNCAPPED (default ~10/pool) because the ADR-068 deploy fan-out is DORMANT — SOLEUR_
# DEPLOY_PEERS is unset, so `deploy-inngest-image` only reached web-1. Only ONE host is
# ever scanned at a time (op=inventory curls 127.0.0.1:8288 on the active host), so with
# BOTH hosts capped the operating point is one-host-scanning (≤20) + peer-idle-drained
# (≤8) ≈ 28 < 30. Pre-flip remediation: bring web-2 into the fan-out
# (the warm-standby dispatch was DELETED with #6575 and web-2 retired 2026-07-17 — this pre-flip remediation is UNREACHABLE at the current one-host operating point) and redeploy the capped
# image so BOTH schedulers honour open=5/idle=2. Post-flip this is moot — the cutover
# STOPS both co-located inngests; the dedicated host (10.0.1.40) uses its OWN dark
# pooler (soleur-dev), so prod-pooler inngest load goes to ~0.
#
# DECISION (#6258, supersedes #5562): KEEP `default_pool_size` at 30 — do NOT revert to
# 15. The #5562 revert's premise (that the client cap bounds inngest's *total* under 15) is
# falsified by the per-pool model above: tightening the upstream pool to 15 while inngest's
# worst-case burst can approach ~20 would make EMAXCONNSESSION *more* likely, not less. The
# low client-side per-pool cap is the sole lever; the upstream stays 30 (ample headroom).
# The #5562 revert is re-scoped to a follow-up (decision-challenges.md); no live mutation here.
#
# NOTE (#5563 → #6258): the leading-indicator pool probe in
# .github/workflows/scheduled-inngest-health.yml is DECOUPLED from default_pool_size.
# Live verification showed total pg_stat_activity is dominated by Supabase infra
# baseline (Supavisor/PostgREST/pg_net/pg_cron/exporter/walsenders), so counting
# it against default_pool_size false-fires. The probe counts only inngest-attributable
# client backends (role `postgres`, minus the pooler's own Supavisor connections + the
# probe) against inngest's worst-case TOTAL footprint (INNGEST_CLIENT_CAP = P × per-pool
# cap 5 ≤ 20) — independent of whatever default_pool_size is set to.
#
# WHY a comment and not a TF resource: no Supabase provider is declared in
# main.tf, and this pooler attribute lives on the OUT-OF-BAND inngest project
# (ref pigsfuxruiopinouvjwy, see the INNGEST_POSTGRES_URI paragraph above) that
# Terraform never minted. Codifying one pooler attribute would require adding a
# whole provider for an out-of-band project — disproportionate. Mirrors the
# INNGEST_POSTGRES_URI out-of-band-resource pattern.

# ---------------- Supabase Management-API PAT → GH Actions secret (#5562) ------
# scheduled-inngest-health.yml's pool-utilization probe reads pg_stat_activity on
# the dedicated inngest project via the Supabase Management API, authenticated by
# an account-scoped PAT (sbp_…). TF only PUBLISHES the out-of-band-minted PAT to
# the GH Actions secret store (NOT operator `gh secret set`); the value comes from
# the no-default `var.supabase_access_token` (Doppler prd_terraform via
# TF_VAR_supabase_access_token, hr-tf-variable-no-operator-mint-default). The PAT
# is account-scoped because Supabase exposes no project-scoped Management-API
# credential — blast-radius is bounded by GH-secret-store-only storage + a fixed
# read-only query + the workflow's scrub_pat redaction. No lifecycle.ignore_changes
# (mirrors doppler-write-token.tf:47 / kb-drift.tf): rotation = re-set the TF_VAR
# and re-apply. The GitHub write routes through the App-auth `integrations/github`
# provider (main.tf), per hr-github-app-auth-not-pat.
resource "github_actions_secret" "supabase_access_token" {
  repository      = "soleur"
  secret_name     = "SUPABASE_ACCESS_TOKEN"
  plaintext_value = var.supabase_access_token
}

# NOTE: All `doppler_secret` resources in this file carry `ignore_changes = [value]`.
# This means out-of-band rotation via the Doppler UI is INVISIBLE to subsequent
# `terraform plan` runs (the provider skips the value read-back when
# ignore_changes is set). The ONLY supported rotation path is
# `terraform taint random_id.<name> && terraform apply` — operators MUST NOT
# rotate via the Doppler UI or the dashboard will desync from tfstate silently.
# Runbook (knowledge-base/engineering/operations/runbooks/inngest-server.md) documents
# the taint procedure.

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
  # "Your team" is the literal default team name in this Better Stack
  # workplace (the only team — t520508). The TF provider does a
  # case-sensitive name lookup against the workplace's team list; the
  # original "Jean's team" literal was rejected at apply time and corrected.
  # Move to a variable in a follow-up if/when a second team is created.
  # Paused until the operator confirms inngest-server is running on the host
  # (`deploy inngest <image> <tag>` succeeded). Otherwise, the gap between
  # `terraform apply` (heartbeat created → BetterStack starts expecting pings
  # within 30s grace) and the first systemd-timer ping would trigger a false
  # email alert. Unpause via the Better Stack UI OR by flipping this attribute
  # to `false` in a follow-up commit after deploy. Runbook documents both
  # paths. See plan deviation note in inngest.tf header.
  paused     = true
  team_name  = "Your team"
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

# ---------------- Vector observability shipper → Better Stack Logs ----------------
# After ~6 PR cycles of Vector ↔ Sentry envelope-format interop issues
# (#4250 ship → #4257, #4259, #4263, #4267, #4268, #4269, #4271, #4272),
# we pivoted Vector's sink target from Sentry's HTTP envelope endpoint
# to Better Stack Logs, which has a first-class Vector integration.
# Strategic consolidation question tracked in issue #4273.
#
# IaC gap: the `betterstackhq/better-uptime` Terraform provider (v0.20.17)
# does NOT yet expose a `telemetry_logging_source` resource — the
# Telemetry/Logs product is a separate product from Uptime and not yet
# covered by the provider. Provisioned out-of-band 2026-05-21 via
# Playwright MCP automation against the Better Stack dashboard:
#   source name: soleur-inngest-vector-prd
#   source id:   2457081
#   platform:    vector
#   token:       stored in Doppler `prd.BETTERSTACK_LOGS_TOKEN` (24 chars)
# Per hr-vendor-token-extraction-via-playwright-must-use-file-output, the
# token was extracted via `browser_evaluate(filename: ...)` and piped to
# `doppler secrets set --silent` — never entered the conversation
# transcript. Validated via HTTP 202 against in.logs.betterstack.com.
# Migration to proper IaC tracked alongside the consolidation decision in
# issue #4273. Rotation procedure (until IaC catches up): regenerate via
# Better Stack dashboard → re-extract via Playwright → re-Doppler-set.
