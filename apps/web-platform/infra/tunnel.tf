# Cloudflare Tunnel for webhook-based deploys.
# Eliminates the need for SSH from GitHub Actions runners (see #749).
# Only the deploy webhook routes through the tunnel; app traffic and
# admin SSH stay on their existing paths (A record + admin_ips firewall).

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "web" {
  account_id = var.cf_account_id
  name       = "soleur-web-platform"
  config_src = "cloudflare"
  secret     = random_id.tunnel_secret.b64_std

  # The tunnel was created via API before Terraform state existed.
  # secret: original b64 value is irrecoverable.
  # config_src: forces replacement on import; the live tunnel already
  #   uses remote config, so ignoring is safe (#967).
  # TODO: remove ignore_changes after clean reprovisioning (import artifact)
  lifecycle {
    ignore_changes = [secret, config_src]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "web" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.web.id

  config {
    ingress_rule {
      hostname = "deploy.${var.app_domain_base}"
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

resource "cloudflare_zero_trust_access_application" "deploy" {
  zone_id          = var.cf_zone_id
  name             = "Deploy Webhook - soleur-web-platform"
  domain           = "deploy.${var.app_domain_base}"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id = var.cf_account_id
  name       = "github-actions-deploy"
}

resource "cloudflare_zero_trust_access_policy" "deploy_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.deploy.id
  name           = "Allow GitHub Actions deploy"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.deploy.id]
  }
}

# Alert one week before the deploy service token expires.
# Cloudflare sends expiring_service_token_alert 7 days pre-expiry.
# Note: this alert fires for ALL service tokens in the account (no per-token
# filtering). Currently only one token exists (github-actions-deploy).
resource "cloudflare_notification_policy" "service_token_expiry" {
  account_id  = var.cf_account_id
  name        = "Deploy service token expiring"
  description = "Alert when github-actions-deploy service token approaches expiry"
  alert_type  = "expiring_service_token_alert"
  enabled     = true

  email_integration {
    id = var.cf_notification_email
  }
}

output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
  sensitive = true
}

output "access_service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.deploy.client_id
}

output "access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.deploy.client_secret
  sensitive = true
}
