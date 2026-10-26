# Cloudflare Load Balancer overlay-add for app.soleur.ai (ADR-068 §(b), Part 2).
#
# GAPLESS PATH: retain cloudflare_record.app (in dns.tf) untouched and ADD the LB on the
# same hostname. CF serves the LB when active and falls back to the plain A record when the
# LB is disabled — no destroy+recreate of the live record. See runbook
# cf-lb-a-record-gaplessness-verify.md (Verdict conditions 1-4, HARD BLOCKERS B1-B3).
#
# HARD BLOCKERS:
#   B1 fallback_pool_id = web-1 pool (so a disabled LB degrades to web-1, not NXDOMAIN).
#   B2 web-2 structurally absent from default_pool_ids (weight 0 / not in rotation) until
#      the cutover session confirms GIT_DATA_LUKS_CUTOVER_AT soak marker.
#   B3 relay-is-safety: LB weight must not be flipped to web-2 before owner-side relay active.
#
# Zone plan is Free Website; Load Balancing is a separately-billed add-on (~$5/mo, approved).
# Applied via apply-web-platform-infra.yml (R2 backend serializer) — never laptop-local apply.

# Health monitor for the LB origin pool.
resource "cloudflare_load_balancer_monitor" "web" {
  account_id     = var.cf_account_id
  type           = "https"
  description    = "web host /health probe (ADR-068 §(b))"
  method         = "GET"
  path           = "/health"
  expected_codes = "200"
  timeout        = 5
  retries        = 2
  interval       = 60
  # Probe the origin directly over the private net is not possible from CF edge;
  # origin firewall permits CF IPs on 443 (see firewall.tf).
}

# Origin pool: web-1 only. web-2 is deliberately NOT an origin here (B2).
resource "cloudflare_load_balancer_pool" "web_1" {
  account_id = var.cf_account_id
  name       = "web-1"
  # Fallback to itself so a disabled LB degrades to web-1, never NXDOMAIN (B1).
  # (fallback_pool_id is set on the LB resource below.)

  origins {
    name    = "web-1"
    address = hcloud_server.web["web-1"].ipv4_address
    enabled = true
    weight  = 1
  }

  monitor = cloudflare_load_balancer_monitor.web.id

  # Keep the pool out of rotation for web-2 until the soak marker is satisfied.
  latitude  = 0
  longitude = 0
}

# The Load Balancer itself, overlaid on app.soleur.ai. The retained A record
# (cloudflare_record.app in dns.tf) stays as the automatic fallback for a disabled LB.
resource "cloudflare_load_balancer" "app" {
  zone_id = var.cf_zone_id
  name    = "app.soleur.ai"
  # default_pool_ids contains ONLY web-1 (B2: web-2 structurally absent).
  default_pool_ids = [cloudflare_load_balancer_pool.web_1.id]
  fallback_pool_id = cloudflare_load_balancer_pool.web_1.id
  steering_policy  = "off" # single origin today; geo/latency steering added later

  session_affinity = "none"

  description = "ADR-068 §(b) multi-host GA overlay (web-1 only until soak marker)"
}

# NOTE: a proxied A record and an LB can coexist on the same hostname; the LB takes
# precedence while active. cloudflare_record.app is intentionally NOT modified here.
