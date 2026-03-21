# Cloudflare Tunnel for webhook-based deploys.
# Eliminates the need for SSH from GitHub Actions runners (see #749).
# Only the deploy webhook routes through the tunnel; app traffic and
# admin SSH stay on their existing paths (A record + admin_ips firewall).

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "bridge" {
  account_id = var.cf_account_id
  name       = "soleur-telegram-bridge"
  config_src = "cloudflare"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "bridge" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.bridge.id

  config {
    ingress_rule {
      hostname = "deploy-bridge.${var.app_domain_base}"
      service  = "http://localhost:9000"
    }
    # Catch-all rule (required by Cloudflare)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Cloudflare Access: protect the deploy endpoint with a service token.
# GitHub Actions sends CF-Access-Client-Id and CF-Access-Client-Secret
# headers alongside the HMAC signature for defense in depth.

resource "cloudflare_zero_trust_access_application" "deploy_bridge" {
  zone_id          = var.cf_zone_id
  name             = "Deploy Webhook - soleur-telegram-bridge"
  domain           = "deploy-bridge.${var.app_domain_base}"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_service_token" "deploy_bridge" {
  account_id = var.cf_account_id
  name       = "github-actions-deploy-bridge"
}

resource "cloudflare_zero_trust_access_policy" "deploy_bridge_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.deploy_bridge.id
  name           = "Allow GitHub Actions deploy"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.deploy_bridge.id]
  }
}

output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.bridge.tunnel_token
  sensitive = true
}

# DNS CNAME routing deploy-bridge.soleur.ai through the tunnel.
resource "cloudflare_record" "deploy_bridge" {
  zone_id = var.cf_zone_id
  name    = "deploy-bridge"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bridge.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

output "access_service_token_client_id" {
  value     = cloudflare_zero_trust_access_service_token.deploy_bridge.client_id
  sensitive = true
}

output "access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.deploy_bridge.client_secret
  sensitive = true
}
