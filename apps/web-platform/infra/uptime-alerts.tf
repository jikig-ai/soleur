# BetterStack uptime + Cloudflare origin-5xx notification — alerting half of
# the 2026-05-18 cert outage post-mortem (PR-β). The fix half landed in PR
# #3974 (initial codification of the ACME-aware HTTPS upgrade) and PR #3986
# (inline of the carve-out into the seo_page_redirects ruleset). Issue #3976
# was the operator runbook for cert recovery. The Sentry half of the alerting
# stack lives at apps/web-platform/infra/sentry/uptime-monitors.tf — these two
# resources are the second-source (BetterStack — independent vendor for
# vendor-isolation) and the page-level error-rate alert (Cloudflare native).
#
# Plan: knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md
#
# Why this lives in the main web-platform root (not the sentry root): the
# betterstackhq and cloudflare providers are declared here (main.tf:35-49,
# 21-24). Sentry's own resources live in the sentry/ subroot because that's
# where the jianyuan/sentry provider is declared (sentry/versions.tf:8-11).
# Reuses two existing roots — does NOT create a new one, per
# hr-every-new-terraform-root-must-include-an.

# ── BetterStack: multi-region apex uptime monitor ───────────────────────────
#
# Second-source apex check — independent vendor from Sentry. If Sentry itself
# is degraded (status.sentry.io or our specific org subdomain), this monitor
# still pages. Same logic as the inngest heartbeat (inngest.tf:108-138) and
# the inngest policy (inngest.tf:140-156) — paid-tier features gated on
# var.betterstack_paid_tier (defaults false → email-only on free tier).
#
# Why apex only (not www / not the deep path / not the ACME probe):
#   - The 4 Sentry monitors give us per-URL coverage already. BetterStack is
#     here for VENDOR ISOLATION, not URL coverage. One probe is enough to
#     prove "soleur.ai is reachable" when Sentry is the one that's broken.
#   - Free-tier BetterStack caps the workplace at 10 monitors. Headroom matters.
#
# Why check_frequency = 180 (3 min) vs Sentry's 300s (5 min): denser probe
# trades a tiny BetterStack-bill bump (free-tier sub-minute checks are paid;
# 3-minute is free-tier-allowed per BetterStack pricing snapshot 2026-05) for
# faster mean-time-to-detect during a real outage. Sentry stays at 5min
# because four probes at 5min == one probe at 75s mean across the four; the
# combined cadence is already dense.
#
# follow_redirects = true: apex 301s to www post-PR #3974 (Rule 10 of
# cloudflare_ruleset.seo_page_redirects). Without follow_redirects, this
# monitor would falsely succeed on the 301 alone without verifying the www
# origin is actually serving 200. With it, the monitor only succeeds if the
# full chain apex -> 301 -> www -> 200 returns 200.
#
# verify_ssl = true: belt-and-suspenders against the exact failure class this
# whole PR exists to alert on. If the apex cert expires, the probe fails
# BOTH on status (because the TLS handshake doesn't complete) AND on the
# ssl_expiration warning (BetterStack alerts 7 days before expiry by default
# when set — we omit the field; default is "alert on expiry-day", which is
# acceptable since Sentry + this monitor's regular failure would already be
# firing by then; setting it would be defense-in-depth but adds tuning surface).
resource "betteruptime_monitor" "soleur_apex" {
  monitor_type       = "status"
  url                = "https://soleur.ai/"
  pronounceable_name = "soleur dot ai apex"

  check_frequency     = 180
  request_timeout     = 10
  confirmation_period = 60
  recovery_period     = 60
  follow_redirects    = true

  email = true
  call  = false
  sms   = false
  push  = false

  # Literal name of the only team in the workplace — see inngest.tf:120-129
  # for the case-sensitivity quirk and the rationale for hardcoding vs
  # promoting to a variable.
  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true
  paused     = false
}

# Conditional escalation policy — mirrors betteruptime_policy.inngest
# (inngest.tf:140-156). count-gated on the same paid-tier flag so a free-tier
# operator does not see an apply-time error attempting to create a paid feature.
resource "betteruptime_policy" "uptime" {
  count = var.betterstack_paid_tier ? 1 : 0

  name           = "soleur-uptime-policy"
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

# ── Cloudflare zone-level origin-5xx notification policy: NOT shipped ──────
#
# PR #4003 originally declared a `cloudflare_notification_policy` with
# alert_type = "http_alert_origin_error" to catch CF-526-class origin cert
# outages at the edge. Three apply attempts produced three different errors:
#   1. PR #4003 — no filters block → API error 17103 (filters required).
#   2. PR #4015 — filters.zones only → 17103 again (zones alone insufficient).
#   3. PR #4018 — filters.zones + filters.slo → API error 17200: "account is
#      not entitled to create policies for the alert type".
#
# Resolution: none of the http_alert_* types
# (http_alert_origin_error / http_alert_edge_error / advanced_http_alert_error)
# are in the account's available_alerts list. They are Enterprise-tier
# features and the soleur account does not have them. Confirmed via:
#   GET /accounts/{cf_account_id}/alerting/v3/available_alerts
#
# The post-mortem scenario this policy was meant to alert on — 526 origin
# cert validation failures — is already covered by:
#   - `sentry_uptime_monitor.soleur_apex` (5-min interval, 3-fail trip)
#   - `sentry_uptime_monitor.soleur_www`
#   - `sentry_uptime_monitor.soleur_acme_probe` (ACME-carve-out regression alarm)
#   - `betteruptime_monitor.soleur_apex` (3-min multi-region, vendor-isolated)
# A 526 either fails the TLS handshake or returns a 5xx — both fire the
# uptime monitors. The CF-native policy was belt-and-suspenders, not load-bearing.
#
# Operator follow-up: if/when the CF plan is upgraded to a tier that includes
# http_alert_origin_error, re-introduce this resource with the v4 syntax
#   filters { zones = [var.cf_zone_id]; slo = ["99.9"] }
# documented in PR #4018 before deletion.
