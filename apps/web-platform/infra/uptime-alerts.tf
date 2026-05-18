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

# ── Cloudflare: zone-level origin-5xx notification policy ──────────────────
#
# Page-level alert on origin 5xx errors for the soleur.ai zone. Catches
# recurrence of the 2026-05-18 cert outage class (Cloudflare 526 = "CF edge
# can't validate origin cert") plus generic origin-side degradation.
#
# Precedent: cloudflare_notification_policy.service_token_expiry at
# tunnel.tf:75-85. Same v4 provider syntax (`email_integration { id = ... }`
# block, NOT v5's `mechanisms = { email = [{ id = "id" }] }` map).
# Cloudflare provider is pinned to `~> 4.0` in main.tf:21-24.
#
# Why http_alert_origin_error and not http_alert_edge_error:
#   - 526 is classified as an origin error in CF's taxonomy (the cert
#     validation failure is on the origin side — CF was reaching out and
#     getting a bad cert back). 526 is the EXACT shape of the 2026-05-18
#     outage. http_alert_edge_error covers CF-internal 5xx (502/520/521 when
#     CF itself can't route), which is rarer and mostly outside our control.
#   - Starting narrow lets us observe the 30-day fire rate before opening up
#     to a noisier channel. Adding edge-error is a clean follow-up if the
#     real-incident mix shows we are missing edge-error events.
#
# filters.zones is REQUIRED by the Cloudflare API for http_alert_origin_error
# (and most http_alert_* types) even though the TF provider schema marks
# `filters` as Optional. Discovered at apply-time when PR #4003's initial
# attempt failed with API error 17103: "Filters selection must be provided
# to create a policy." The expiring_service_token_alert precedent
# (tunnel.tf:75-85) does NOT need filters because that alert type is
# account-scoped, not zone-scoped — do not generalize from it.
#
# Why email_integration only (no Slack / PagerDuty):
#   - Matches the service_token_expiry precedent. Multi-channel routing is an
#     org-wide upgrade, not a per-policy decision. Email is the operator's
#     existing on-call channel for CF alerts.
resource "cloudflare_notification_policy" "soleur_ai_5xx" {
  account_id  = var.cf_account_id
  name        = "soleur.ai origin 5xx rate spike"
  description = "Page-level alert on origin 5xx errors for the soleur.ai zone. Catches recurrence of the 2026-05-18 cert outage class (526 / origin cert validation failures) plus other origin-side degradation. Precedent: cloudflare_notification_policy.service_token_expiry (tunnel.tf:75-85). See PR #3974, PR #3986, issue #3976."
  alert_type  = "http_alert_origin_error"
  enabled     = true

  filters {
    zones = [var.cf_zone_id]
  }

  email_integration {
    id = var.cf_notification_email
  }
}
