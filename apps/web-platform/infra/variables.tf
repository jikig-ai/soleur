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

# --- Epic #5274 Phase 3 (ADR-068) — multi-host web cluster -------------------
# Keyed map of web hosts. `web-1` is the PRE-EXISTING host; its config MUST match
# current state (location=hel1, server_type=cx33, private_ip=10.0.1.10) so the
# for_each `moved` migration is 0-destroy — changing web-1's location/server_type
# would force-REPLACE the live prod host (single-user incident). Keys are IMMUTABLE
# post-migration (`moved`-block for_each keys; never rename). EU-location-pinned for
# GDPR residency (CLO T-1, GA-blocking).
variable "web_hosts" {
  description = "Web-host cluster (multi-host /workspaces, ADR-068 Phase 3). web-1 = pre-existing host; keys immutable post-migration; EU-location-pinned (CLO T-1)."
  # (The former `monitored` per-host flag was removed with the #5933 per-host uptime
  # probe/monitor — uptime is now monitored at app.soleur.ai, see uptime-alerts.tf.)
  type = map(object({
    location    = string
    private_ip  = string
    server_type = optional(string, "cx33")
  }))
  default = {
    "web-1" = { location = "hel1", private_ip = "10.0.1.10" }
    "web-2" = { location = "hel1", private_ip = "10.0.1.11" }
  }
  validation {
    condition     = alltrue([for h in values(var.web_hosts) : contains(["nbg1", "fsn1", "hel1"], h.location)])
    error_message = "web_hosts location must be an EU Hetzner DC (nbg1/fsn1/hel1) — GDPR residency (CLO T-1, GA-blocking). A non-EU web host or placement group is rejected before web-2 serves."
  }
  validation {
    condition     = alltrue([for h in values(var.web_hosts) : can(regex("^10\\.0\\.1\\.[0-9]{1,3}$", h.private_ip))])
    error_message = "web_hosts private_ip must be a host address in the 10.0.1.0/24 private subnet (network.tf)."
  }
}

# --- Epic #5274 Phase 2 PR B (ADR-068) — git-data host -----------------------
# No no-default operator-mint TF_VAR is added: the transport key is tls-generated
# (tls_private_key.git_transport, git-data.tf) and the betterstack/doppler tokens
# already exist (hr-tf-variable-no-operator-mint-default).

variable "git_data_server_type" {
  description = "Hetzner server type for the git-data host (cax11 = 2 vCPU ARM64/Ampere, 4GB RAM). ARM64: git/sshd are ARM-native. Verify current Hetzner pricing before budget decisions."
  type        = string
  default     = "cax11"
}

variable "git_data_volume_size" {
  description = "Size of the git-data bare-repo block volume in GB (Hetzner minimum is 10 GB). The bare repos + the per-(workspace,worktree) fence sidecar/lock live here — never tmpfs (reboot-durable fence)."
  type        = number
  default     = 10
}

# --- Epic #5274 Phase 3, Sub-PR 3.D (ADR-068) — LUKS-at-rest cutover volume ---
variable "git_data_luks_volume_size" {
  description = "Size of the FRESH LUKS-at-rest git-data volume in GB (Hetzner minimum 10 GB). The cutover target (git-data-luks.tf / git-data-cutover.sh FRESH_ROOT). >= git_data_volume_size so the plaintext repo tree rsyncs onto it without ENOSPC. Guest-side LUKS: this is a plain hcloud_volume; cryptsetup runs in the guest."
  type        = number
  default     = 10
}

variable "kb_drift_operator_founder_id" {
  description = "Operator founder Supabase users.id UUID — KB-drift ingest rows are attributed to this user. Sourced from Doppler prd_terraform (TF_VAR_kb_drift_operator_founder_id). No default: fail closed rather than mint a placeholder identity."
  type        = string
  sensitive   = true
}

variable "cf_api_token_zone_settings" {
  description = "Cloudflare API token narrowed to Zone Settings:Edit on soleur.ai (HSTS / security_header)"
  type        = string
  sensitive   = true
}

variable "cf_api_token_rulesets" {
  description = "Cloudflare API token narrowed to Cache Rules:Edit + Zone WAF:Edit + Single Redirect Rules:Edit + Transform Rules:Edit on soleur.ai, PLUS (post-#5092 widen) account-level Account Rulesets:Edit + Account Filter Lists:Edit for Bulk Redirects (cloudflare_ruleset/cloudflare_list resources across http_request_cache_settings, http_request_firewall_custom, http_request_dynamic_redirect, http_response_headers_transform, and account http_request_redirect phases; see cache.tf, bot-allowlist.tf, seo-rulesets.tf, and seo-bulk-redirects.tf)"
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

variable "cf_account_id" {
  description = "Cloudflare account ID (required for Zero Trust tunnel resources)"
  type        = string
}

variable "webhook_deploy_secret" {
  description = "HMAC shared secret for webhook deploy authentication"
  type        = string
  sensitive   = true
}

variable "cf_access_client_id" {
  description = "CF Access service-token client ID for the deploy webhook endpoint"
  type        = string
  sensitive   = true
}

# #4829 — CI-context private key for the infra_config_handler_bootstrap SSH
# bridge. NULL in the operator-local apply path (which uses agent = true against
# the operator's own ssh-agent); set to Doppler prd_terraform/DEPLOY_SSH_PRIVATE_KEY
# (produced by ci-ssh-key.tf) and passed as TF_VAR_ci_ssh_private_key when the
# bridge is applied from the GitHub Actions runner over the Cloudflare Tunnel.
# No operator mint: the value is the terraform-generated tls_private_key.ci_ssh
# (hr-tf-variable-no-operator-mint-default).
variable "ci_ssh_private_key" {
  description = "CI-context SSH private key for the infra-config handler bootstrap bridge (Doppler DEPLOY_SSH_PRIVATE_KEY). Null in operator-local applies (agent-based); set only in CI."
  type        = string
  default     = null
  sensitive   = true
}

variable "cf_access_client_secret" {
  description = "CF Access service-token client secret for the deploy webhook endpoint"
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

variable "sentry_dsn" {
  description = "Sentry DSN baked into cloud-init so the fresh-boot fatal emit fires WITHOUT depending on doppler (which may itself be the broken stage). Semi-public (already in the client bundle). Injected via TF_VAR_sentry_dsn from Doppler prd_terraform SENTRY_DSN; empty default keeps bare `terraform validate` working. NOTE: the doppler fallback only applies AFTER doppler is installed — the pre-extraction fresh-boot stages (pkg_audit/doppler_dl, #6090) depend SOLELY on this baked value, so an empty DSN there silently reverts to a zero-emit abort. The web-2-recreate job's 'Extract backend credentials' step asserts this is non-empty before -replace so that coverage cannot regress unnoticed."
  type        = string
  default     = ""
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

variable "resend_receiving_api_key" {
  description = "Resend receiving/full-access API key for inbound-mail body fetch (RESEND_RECEIVING_API_KEY). Distinct from the send-scoped resend_api_key — least-privilege per #5480. Operator-minted at resend.com/api-keys; value from Doppler prd_terraform via TF_VAR_resend_receiving_api_key. No default (hr-tf-variable-no-operator-mint-default)."
  type        = string
  sensitive   = true
}

variable "supabase_access_token" {
  description = "Supabase account-scoped Management-API PAT (sbp_…) used by scheduled-inngest-health.yml to read pg_stat_activity on the dedicated inngest project (ref pigsfuxruiopinouvjwy) for connection-pool monitoring (#5562). Out-of-band-minted at supabase.com/dashboard/account/tokens; value from Doppler prd_terraform via TF_VAR_supabase_access_token. Published to a GH Actions secret via github_actions_secret.supabase_access_token (inngest.tf), NOT operator gh secret set. No default (hr-tf-variable-no-operator-mint-default)."
  type        = string
  sensitive   = true
}

# --- Inngest IaC (PR-F follow-up, #3960) -------------------------------------
# 3 new variables (down from plan's 7). Inngest signing/event keys are
# TF-generated via random_id (see inngest.tf); no operator mint required.
# CTO two-alias intent met via resource naming + explicit `config = "..."`.

variable "doppler_token_tf" {
  description = "Doppler workplace-scope personal token used by the doppler provider to write to both `prd` and `dev` configs. Operator-minted at dashboard.doppler.com/workplace/<ID>/tokens/personal."
  type        = string
  sensitive   = true
}

variable "betterstack_api_token" {
  description = "Better Stack global API token (Read & write) for the betteruptime provider. Operator-minted at betterstack.com/settings/global-api-tokens."
  type        = string
  sensitive   = true
}

variable "betterstack_paid_tier" {
  description = "When true, provision a betteruptime_policy with escalation steps. Free tier defaults to false (heartbeat + email only)."
  type        = bool
  default     = false
}

# --- PR-H (#3244) — GitHub App + KB-drift -----------------------------------
# Post-#4150: client_id / client_secret / github_actions_token /
# doppler_token_kb_drift variables were deleted. See plan
# knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md
# Provider switched to App-installation auth (main.tf); kb-drift Doppler
# token now minted in-band by `doppler_service_token` resource (kb-drift.tf).
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token).

variable "github_app_id" {
  description = "GitHub App ID for Soleur-Concierge. Mirrored from `prd` to `prd_terraform` so the App-auth `provider \"github\"` block can resolve it (see main.tf)."
  type        = string
  sensitive   = true
}

variable "github_app_private_key" {
  description = "PEM-encoded RSA private key for the GitHub App. Mirrored from `prd` to `prd_terraform` for the App-auth provider. One-shot download at App creation; cannot be re-downloaded."
  type        = string
  sensitive   = true
}

# #6005: scoped read:packages credential (machine account) for the now-PRIVATE GHCR
# packages. NO default (hr-tf-variable-no-operator-mint-default) — the operator mints
# it and writes the value into Doppler `prd_terraform` (the TF_VAR source) BEFORE this
# file's doppler_secret resources apply. See ghcr-read-credential.tf for the ordered
# runbook + the deliberate hr-github-app-auth-not-pat exception (ADR-087).
variable "ghcr_read_user" {
  description = "GitHub machine-account login that owns the scoped read:packages PAT (the docker login -u value). Published to Doppler soleur/prd as GHCR_READ_USER."
  type        = string
  sensitive   = true
}

variable "ghcr_read_token" {
  description = "Fine-grained read:packages PAT scoped to the jikig-ai soleur-web-platform + soleur-inngest-bootstrap packages, on a machine account. Published to Doppler soleur/prd as GHCR_READ_TOKEN; consumed by ci-deploy.sh (host pull + cosign .sig fetch auth) + cloud-init fresh-boot login. NO default."
  type        = string
  sensitive   = true
}
