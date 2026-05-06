# Secrets injected via Doppler (nested invocation for R2 backend + TF variables):
#
#   doppler run --project soleur --config prd_terraform -- \
#     doppler run --token "$(doppler configure get token --plain)" \
#       --project soleur --config prd_terraform --name-transformer tf-var -- \
#     terraform plan
#
# Why nested: --name-transformer tf-var replaces ALL key names (AWS_ACCESS_KEY_ID
# becomes TF_VAR_aws_access_key_id). The S3/R2 backend needs plain AWS_ACCESS_KEY_ID.
# The outer call injects plain env vars; the inner call adds TF_VAR_* versions.
# Why --token: The DOPPLER_TOKEN secret (Doppler service token for server injection)
# collides with the CLI's auth token. Passing --token explicitly on the inner call
# ensures the CLI authenticates with the personal token, not the service token.

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "admin_ips" {
  description = "IP addresses allowed to SSH into the server (CIDR notation)"
  type        = list(string)
}

variable "ssh_key_path" {
  description = "Path to the public SSH key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "server_type" {
  description = "Hetzner server type (cx33 = 4 vCPU, 8GB RAM)"
  type        = string
  default     = "cx33"
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "hel1"
}

variable "image_name" {
  description = "Docker image to deploy"
  type        = string
  default     = "ghcr.io/jikig-ai/soleur-web-platform:latest"
}

variable "volume_size" {
  description = "Size of the persistent volume in GB (for /workspaces)"
  type        = number
  default     = 20
}

variable "cf_api_token" {
  description = "Cloudflare API token (Tunnel, Access, DNS, Notifications permissions)"
  type        = string
  sensitive   = true
}

variable "cf_api_token_zone_settings" {
  description = "Cloudflare API token narrowed to Zone Settings:Edit on soleur.ai (HSTS / security_header)"
  type        = string
  sensitive   = true
}

variable "cf_api_token_rulesets" {
  description = "Cloudflare API token narrowed to Cache Rules:Edit + Zone WAF:Edit + Single Redirect Rules:Edit + Transform Rules:Edit on soleur.ai (cloudflare_ruleset resources across http_request_cache_settings, http_request_firewall_custom, http_request_dynamic_redirect, and http_response_headers_transform phases; see cache.tf, bot-allowlist.tf, and seo-rulesets.tf)"
  type        = string
  sensitive   = true
}

variable "cf_api_token_bot_management" {
  description = "Cloudflare API token narrowed to Bot Management:Edit on soleur.ai (cloudflare_bot_management resource; see bot-management.tf)"
  type        = string
  sensitive   = true
}

variable "cf_zone_id" {
  description = "Cloudflare zone ID for soleur.ai"
  type        = string
}

variable "app_domain" {
  description = "Domain name for the web platform"
  type        = string
  default     = "app.soleur.ai"
}

variable "deploy_ssh_public_key" {
  description = "SSH public key for the deploy user (legacy, kept for migration period)"
  type        = string
  default     = ""
}

variable "cf_account_id" {
  description = "Cloudflare account ID (required for Zero Trust tunnel resources)"
  type        = string
}

variable "webhook_deploy_secret" {
  description = "HMAC shared secret for webhook deploy authentication"
  type        = string
  sensitive   = true
}

variable "app_domain_base" {
  description = "Base domain for the application (e.g., soleur.ai)"
  type        = string
  default     = "soleur.ai"
}

variable "doppler_token" {
  description = "Doppler service token for production secrets injection"
  type        = string
  sensitive   = true
}

variable "cf_notification_email" {
  description = "Email address for Cloudflare notification policies"
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key for infrastructure alert emails to ops@jikigai.com"
  type        = string
  sensitive   = true
}
