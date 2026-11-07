# Part-2 staging convert on the THROWAWAY hostname lb-staging.soleur.ai
# (cf-lb-a-record-gaplessness-verify.md Part 2). Mirrors the GA overlay's exact v4
# resource shapes (apps/web-platform/infra/cloudflare-lb.tf) so the empirical verdict
# transfers: retain the A record, overlay monitor + pool + LB, fallback_pool_id = the
# same web-1 pool (B1). NOTHING here may name app.soleur.ai — the cf-lb-overlay gate
# pins name == "lb-staging.soleur.ai" on the LB.

# web-1's live IPv4, read fresh — never hardcoded, never reached into prod state
# (this root shares no state with the parent; a data source is the only read path).
data "hcloud_server" "web_1" {
  name = "soleur-web-platform"
}

# Throwaway proxied A record mirroring cloudflare_record.app's shape (dns.tf).
resource "cloudflare_record" "lb_staging" {
  zone_id = var.cf_zone_id
  name    = "lb-staging"
  content = data.hcloud_server.web_1.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
}

resource "cloudflare_load_balancer_monitor" "lb_staging" {
  account_id       = var.cf_account_id
  type             = "https"
  description      = "lb-staging throwaway /health probe (epic #11181 F3 Part 2)"
  method           = "GET"
  path             = "/health"
  expected_codes   = "200"
  timeout          = 5
  retries          = 2
  interval         = 60
  consecutive_down = 2
  consecutive_up   = 1
}

resource "cloudflare_load_balancer_pool" "lb_staging" {
  account_id    = var.cf_account_id
  name          = "lb-staging-web-1"
  check_regions = ["WEU"]

  origins {
    name    = "web-1"
    address = data.hcloud_server.web_1.ipv4_address
    enabled = true
    weight  = 1
  }

  monitor = cloudflare_load_balancer_monitor.lb_staging.id

  latitude  = 0
  longitude = 0
}

resource "cloudflare_load_balancer" "lb_staging" {
  zone_id          = var.cf_zone_id
  name             = "lb-staging.soleur.ai"
  default_pool_ids = [cloudflare_load_balancer_pool.lb_staging.id]
  # B1 — fallback pool health is not evaluated, so it serves through the
  # cold-LB unknown-health window (runbook Part 1 row D).
  fallback_pool_id = cloudflare_load_balancer_pool.lb_staging.id
  steering_policy  = "off"
  proxied          = true

  session_affinity = "none"

  description = "epic #11181 F3 Part-2 staging convert (throwaway; torn down after verdict)"
}
