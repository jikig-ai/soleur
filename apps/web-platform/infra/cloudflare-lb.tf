# Cloudflare Load Balancer overlay-add for app.soleur.ai (ADR-068 §(b), Part 2).
#
# GAPLESS PATH: retain cloudflare_record.app (in dns.tf) untouched and ADD the LB on the
# same hostname. CF serves the LB when active and falls back to the plain A record when the
# LB is disabled — no destroy+recreate of the live record. See runbook
# cf-lb-a-record-gaplessness-verify.md (Verdict conditions 1-4, HARD BLOCKERS B1-B3).
#
# HARD BLOCKERS:
#   B1 fallback_pool_id = web-1 pool (so a disabled LB degrades to web-1, not NXDOMAIN).
#   B2 web-2 is a gated pool member (weight = var.web2_lb_weight, default 1 = serving, live
#      since the 2026-11-08 serve flip, #12167): the 0→1 flip rode the ga-pool-update serve arm
#      behind the §(c) gate chain + runtime-bind probe. DRAIN is an explicit act: ga-pool-update
#      mode=drain passes -var=web2_lb_weight=0, and ga-overlay passes the same 0 so a fresh GA3 create
#      stays drained (ga-overlay is create-only: it cannot drain a live pool).
#   B3 relay-is-safety: LB weight must not be flipped to web-2 before owner-side relay active.
#
# Zone plan is Free Website; Load Balancing is a separately-billed add-on (~$5/mo, approved).
# Applied via cf-lb-overlay.yml `ga-overlay` arm (R2 backend serializer; the parent
# apply's -target allow-list deliberately excludes this trio) — never laptop-local apply.
# UPDATE semantics ride the `ga-monitor-fix` / `ga-pool-update` arms (same gating).

# Health monitor for the LB origin pool: https/:443 with the Host header the edge itself would send.
# Moved from http/:80 by the ga-monitor-https arm of cf-lb-overlay.yml (ADR-321 R7, #10479) - dispatch only,
# never a push apply, and ONLY after the app's TLS listener (server/origin-tls.ts) is proven bound on BOTH hosts.
#
# WHY IT WAS http/:80 (2026-11-01): the zone's config rule sets `ssl = "flexible"` for app.soleur.ai
# (seo-config-rules.tf), so the edge dials the origin over plain HTTP, and the :443 listener was INERT until an
# Origin CA certificate was loaded. The original type=https create shape failed TCP connect on every origin and
# permanently reported them down, which the B1 self-fallback then hid. Both facts have changed: the certificate is
# in Doppler prd and both hosts log `origin-tls: listening`. The firewall permits CF IPs on :80 and :443 (firewall.tf).
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. A healthy https/:443 pool proves a listener answers TLS on :443 on each
# origin and that Cloudflare's monitor accepts its Origin CA certificate. It does NOT prove the edge-to-origin
# TRAFFIC hop uses TLS: that is still `flexible` for this host until the strict flip (ADR-321 decision 3), and
# the probe (apps/web-platform/infra/origin-tls-probe.sh) reports that separately.
#
# allow_insecure = false: the certificate IS validated. An unvalidated probe would report a listener with ANY
# certificate healthy and prove nothing about the trust R7 requires. Whether Cloudflare's monitor trusts an Origin
# CA certificate is not stated in Cloudflare's monitor documentation (unverified); the dispatch arm therefore
# grades live pool health for BOTH origins after the apply and fails red if either is unhealthy. Evidence that
# would flip this to allow_insecure = true: that red result with both listeners proven by their startup lines -
# a separate, owner-decided change.
#
# header Host: the edge sends Host: app.soleur.ai for real traffic. Cloudflare's docs recommend setting it and do
# not say whether it is also used as the TLS SNI (unverified). The origin listener serves one certificate for any
# SNI, so the handshake does not depend on it.
#
# Rollback is a revert PR plus the `ga-monitor-fix` arm (http/:80, graded by cf_lb_gate_ga_monitor_update).
# Traffic is not at risk either way: both origins serve (web-2 is weight 1) and the B1 fallback serves web-1 if every origin reads down.
resource "cloudflare_load_balancer_monitor" "web" {
  account_id       = var.cf_account_id
  type             = "https"
  port             = 443
  description      = "web host /health probe (ADR-068 §(b), ADR-321 R7; https/:443, Host app.soleur.ai, certificate validated)"
  method           = "GET"
  path             = "/health"
  expected_codes   = "200"
  allow_insecure   = false
  timeout          = 5
  retries          = 2
  interval         = 60
  consecutive_down = 2
  consecutive_up   = 1

  header {
    header = "Host"
    values = ["app.soleur.ai"]
  }
}

# Origin pool: one origin per var.web_hosts entry, in map-key order (web-1, web-2 — today's order, so the
# dynamic block plans no diff), at the host's declared lb_weight (#9421 Part 2a, ADR-327). A drained member
# (weight 0) is health-checked but receives no traffic, so the pool reports truthful per-origin health.
# local.web_lb_gate carries the gated drain/serve input: a gate can only LOWER a host's declared weight
# (min), so `-var=web2_lb_weight=0` still drains web-2 and no gate can raise a host declared at 0.
locals {
  web_lb_gate = { "web-2" = var.web2_lb_weight }
  web_lb_weights = {
    for k, h in var.web_hosts : k => min(h.lb_weight, lookup(local.web_lb_gate, k, h.lb_weight))
  }
  # Hosts that serve with no gated drain/serve input (web-1 today). The pool's precondition allows at most
  # one, so a new key declared at lb_weight = 1 is refused at plan time instead of pooling ungated: it must
  # enter local.web_lb_gate (and the lb-weight-gate chain) first.
  web_lb_ungated = [for k, h in var.web_hosts : k if h.lb_weight > 0 && !contains(keys(local.web_lb_gate), k)]
}

resource "cloudflare_load_balancer_pool" "web_1" {
  account_id    = var.cf_account_id
  name          = "web-1"
  check_regions = ["WEU"]
  # Fallback to itself so a disabled LB degrades to web-1, never NXDOMAIN (B1).
  # (fallback_pool_id is set on the LB resource below.)

  # B2: gated member — weight 0 means health is still checked but no traffic is routed
  # (provider drained semantic); weight 1 serves. var.web2_lb_weight DEFAULTS to 1
  # (variables.tf) = live, so plans that do not name it are clean; DRAIN is an explicit
  # -var=web2_lb_weight=0 (cf-lb-overlay `ga-pool-update mode=drain`; `ga-overlay` passes it for a fresh create), and the
  # 0→1 flip rode `mode=serve` behind the §(c) gate chain + lb-weight-gate-with-marker.sh.
  # lb-weight-gate.test.sh C.3/C.4 pin all of this (through local.web_lb_gate above).
  dynamic "origins" {
    for_each = var.web_hosts
    content {
      name    = origins.key
      address = hcloud_server.web[origins.key].ipv4_address
      enabled = true
      weight  = local.web_lb_weights[origins.key]
    }
  }

  # CTO ruling 2026-11-01: origin-level steering is the real knob (LB-level
  # steering_policy selects BETWEEN pools — one default pool makes it vacuous).
  # "random" is the provider default made explicit; "hash" is client-IP-stable
  # selection = de facto session affinity contradicting session_affinity="none";
  # least_* policies are meaningless at a two-member weighted pool (weights are 1/web2_lb_weight).
  origin_steering {
    policy = "random"
  }

  monitor = cloudflare_load_balancer_monitor.web.id

  latitude  = 0
  longitude = 0

  lifecycle {
    precondition {
      condition     = length(local.web_lb_ungated) <= 1
      error_message = "At most one web host may serve outside the drain gate (local.web_lb_gate); add the new key to the gate before declaring lb_weight = 1."
    }
  }
}

# Page on origin-down: the LB now carries a real health signal (monitor fixed 2026-11-01),
# and a silent origin-down is exactly the incident class that produced this work — it
# must page, not wait for a manual pool-health poll. Applied via the ga-pool-update arm's
# -target set, NOT the routine apply: `filters.pool_id` references the pool, and a
# routine-apply -target on the policy would transitively pull the pool — and the web-2
# origin update — into an unattended apply (the #8705 second-apply-workflow class).
# `load_balancing_health_alert` IS in the account's available_alerts (unlike the
# http_alert_* Enterprise types documented at uptime-alerts.tf).
resource "cloudflare_notification_policy" "web_lb_health" {
  account_id  = var.cf_account_id
  name        = "GA LB pool health (app.soleur.ai)"
  description = "Alert when the GA load balancer's web pool or any origin reports unhealthy (ADR-068 §(b))"
  alert_type  = "load_balancing_health_alert"
  enabled     = true

  filters {
    pool_id      = [cloudflare_load_balancer_pool.web_1.id]
    event_source = ["pool", "origin"]
    # new_health is ["Unhealthy"] only — the documented vocabulary for
    # load_balancing_health_alert is {Unhealthy, Healthy} (CF docs; the shipped
    # "Down" was API-rejected with Error 17108 on run 41504420340).
    # A "Healthy" (recovery) page is deliberately out of scope: flap-vs-sustained
    # recovery paging was never verified — a follow-up may add it after
    # verification.
    new_health = ["Unhealthy"]
  }

  email_integration {
    id = var.cf_notification_email
  }
}

# The Load Balancer itself, overlaid on app.soleur.ai. The retained A record
# (cloudflare_record.app in dns.tf) stays as the automatic fallback for a disabled LB.
resource "cloudflare_load_balancer" "app" {
  zone_id = var.cf_zone_id
  name    = "app.soleur.ai"
  # default_pool_ids contains ONLY web-1's pool; web-2 rides inside it as a gated member (B2).
  default_pool_ids = [cloudflare_load_balancer_pool.web_1.id]
  fallback_pool_id = cloudflare_load_balancer_pool.web_1.id
  steering_policy  = "off" # pool-level knob; one default pool — origin selection lives in the pool's origin_steering
  proxied          = true

  session_affinity = "none"

  # NOTE: this description is deliberately stale (web-2 has served at weight 1 since the 2026-11-08 serve flip):
  # editing an attribute value plans a standing in-place LB update, so it changes together with an intended
  # `ga-pool-update` apply (follow-up issue: stale web-2 weight-0 wording).
  description = "ADR-068 §(b) multi-host GA overlay (web-2 drained at weight 0 until the #6027 window flip)"
}

# NOTE: a proxied A record and an LB can coexist on the same hostname; the LB takes
# precedence while active. cloudflare_record.app is intentionally NOT modified here.
