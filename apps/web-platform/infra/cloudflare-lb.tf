# Cloudflare Load Balancer overlay-add for app.soleur.ai (ADR-068 §(b), Part 2).
#
# GAPLESS PATH: retain cloudflare_record.app (in dns.tf) untouched and ADD the LB on the
# same hostname. CF serves the LB when active and falls back to the plain A record when the
# LB is disabled — no destroy+recreate of the live record. See runbook
# cf-lb-a-record-gaplessness-verify.md (Verdict conditions 1-4, HARD BLOCKERS B1-B3).
#
# HARD BLOCKERS:
#   B1 fallback_pool_id = web-1 pool (so a disabled LB degrades to web-1, not NXDOMAIN).
#   B2 web-2 is a DRAINED pool member (weight = 0): health-monitored but zero serving
#      weight until the #6027 maintenance window flips 0→1 after the
#      GIT_DATA_LUKS_CUTOVER_AT soak marker (the §(c) gate chain + runtime-bind probe).
#   B3 relay-is-safety: LB weight must not be flipped to web-2 before owner-side relay active.
#
# Zone plan is Free Website; Load Balancing is a separately-billed add-on (~$5/mo, approved).
# Applied via cf-lb-overlay.yml `ga-overlay` arm (R2 backend serializer; the parent
# apply's -target allow-list deliberately excludes this trio) — never laptop-local apply.
# UPDATE semantics ride the `ga-monitor-fix` / `ga-pool-update` arms (same gating).

# Health monitor for the LB origin pool. Probes the REAL CF→origin path: the zone's
# config rule sets `ssl = "flexible"` for app.soleur.ai (seo-config-rules.tf), so the
# edge dials the origin over plain HTTP. cloud-init publishes the app container on host
# :80 only (`-p 0.0.0.0:80:3000`); nothing listens on :443 — a type=https monitor (the
# 2026-11-01 create shape) fails TCP connect and permanently reports every origin down,
# which the B1 self-fallback then hides. An http/:80 GET /health replicates the request
# shape traffic actually takes. The origin firewall permits CF IPs on BOTH :80 and :443
# (firewall.tf) — permit ≠ listener.
resource "cloudflare_load_balancer_monitor" "web" {
  account_id       = var.cf_account_id
  type             = "http"
  port             = 80
  description      = "web host /health probe (ADR-068 §(b); http/:80 matches the Flexible-SSL edge path — origin has no :443 listener)"
  method           = "GET"
  path             = "/health"
  expected_codes   = "200"
  timeout          = 5
  retries          = 2
  interval         = 60
  consecutive_down = 2
  consecutive_up   = 1
}

# Origin pool: web-1 serving at weight 1, web-2 drained at weight 0 (B2) — a drained
# member is health-checked but receives no traffic, so the pool reports truthful
# per-origin health for BOTH hosts pre-flip without web-2 serving a single request.
resource "cloudflare_load_balancer_pool" "web_1" {
  account_id    = var.cf_account_id
  name          = "web-1"
  check_regions = ["WEU"]
  # Fallback to itself so a disabled LB degrades to web-1, never NXDOMAIN (B1).
  # (fallback_pool_id is set on the LB resource below.)

  origins {
    name    = "web-1"
    address = hcloud_server.web["web-1"].ipv4_address
    enabled = true
    weight  = 1
  }

  # B2: drained member — weight 0 means health is still checked but no traffic is
  # routed (provider drained semantic). The 0→1 flip is the #6027 window act, gated
  # by the §(c) gate chain + lb-weight-gate-with-marker.sh — never a config edit.
  origins {
    name    = "web-2"
    address = hcloud_server.web["web-2"].ipv4_address
    enabled = true
    weight  = 0
  }

  # CTO ruling 2026-11-01: origin-level steering is the real knob (LB-level
  # steering_policy selects BETWEEN pools — one default pool makes it vacuous).
  # "random" is the provider default made explicit; "hash" is client-IP-stable
  # selection = de facto session affinity contradicting session_affinity="none";
  # least_* policies are meaningless at a {1,0} drained shape.
  origin_steering {
    policy = "random"
  }

  monitor = cloudflare_load_balancer_monitor.web.id

  latitude  = 0
  longitude = 0
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
    new_health   = ["Down"]
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
  # default_pool_ids contains ONLY web-1's pool; web-2 rides inside it drained (B2).
  default_pool_ids = [cloudflare_load_balancer_pool.web_1.id]
  fallback_pool_id = cloudflare_load_balancer_pool.web_1.id
  steering_policy  = "off" # pool-level knob; one default pool — origin selection lives in the pool's origin_steering
  proxied          = true

  session_affinity = "none"

  description = "ADR-068 §(b) multi-host GA overlay (web-2 drained at weight 0 until the #6027 window flip)"
}

# NOTE: a proxied A record and an LB can coexist on the same hostname; the LB takes
# precedence while active. cloudflare_record.app is intentionally NOT modified here.
