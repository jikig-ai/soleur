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
  description = "Hetzner datacenter location (web + git-data hosts). NOT the registry — that has its own var.registry_location so the two can diverge (#6122: the registry lives in nbg1, provisioned during a hel1 capacity outage)."
  type        = string
  default     = "hel1"
  # EU residency (#6453). var.web_hosts pins its per-host location (:94-96) but this
  # scalar — which places the git-data host and is overridable by TF_VAR_location —
  # carried no check at all. Hetzner's /v1/datacenters really does return ash-dc1 (US),
  # hil-dc1 (US) and sin-dc1 (Singapore), so an unvalidated var is one typo away from a
  # non-EU prod host. Config-phase only: no resource is created, modified or destroyed.
  validation {
    condition     = contains(["nbg1", "fsn1", "hel1"], var.location)
    error_message = "location must be an EU Hetzner DC (nbg1/fsn1/hel1) — GDPR residency (CLO T-1, GA-blocking). A non-EU host is rejected before it is created, not after it holds data."
  }
}

variable "registry_location" {
  description = "Hetzner datacenter location for the zot registry host + its volume (#6122). Separate from var.location so the registry can move regions independently. Originally nbg1 (provisioned there during a hel1/eu-central cx23-stock outage). MOVED nbg1→**hel1** (#6288): the OOM remediation needs an 8 GB host, and cx33 (8 GB, ~€8.49/mo) is available in hel1 but not nbg1 (nbg1's cheapest 8 GB was cpx32 ~€35/mo). hel1 is the same eu-central network zone (10.0.1.0/24 spans it) + where the web/git-data/inngest hosts live. The location change is ForceNew on hcloud_volume.registry — the nbg1 store volume is destroyed and a fresh hel1 volume is created; the 35 GB store re-fills from GHCR (zot is a mirror; pulls fall through to GHCR meanwhile)."
  type        = string
  default     = "hel1"
  # EU residency (#6453) — same rule as var.location above, enforced separately because
  # the two deliberately diverge (the registry moved nbg1 -> hel1 independently, #6288).
  # This var is the TARGET of the registry-region-migrate dispatch, i.e. the one location
  # an operator changes by hand, which makes it the likeliest to receive a non-EU value.
  validation {
    condition     = contains(["nbg1", "fsn1", "hel1"], var.registry_location)
    error_message = "registry_location must be an EU Hetzner DC (nbg1/fsn1/hel1) — GDPR residency (CLO T-1, GA-blocking). The zot store mirrors GHCR artifacts; it is rejected before it lands outside the EU."
  }
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
    # web-2 sits in a DIFFERENT DC from web-1's hel1 (DC-failure resilience). A same-DC
    # warm standby gives no protection against a hel1 outage, and a `-replace` recreate
    # DURING a hel1 capacity shortage destroyed web-2 then could not re-place it, wedging
    # every apply-on-merge on `resource_unavailable` (2026-07-13, #6374 follow-on). fsn1 is
    # eu-central (10.0.1.0/24 spans it, network.tf) + EU (CLO T-1). Cross-DC hosts cannot
    # share the location-scoped web_spread placement group — server.tf gates that.
    "web-2" = { location = "fsn1", private_ip = "10.0.1.11" }
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

# --- #6122 (ADR-096) — the self-hosted zot registry host ---
variable "registry_server_type" {
  description = "Hetzner server type for the zot registry host. HOST ARCH IS DERIVED FROM THIS (zot-registry.tf local.registry_arch): cax11 (2 vCPU ARM64/Ampere, 4GB) / cx23 (2 vCPU x86, 4GB) / cx33 (4 vCPU x86, 8GB, ~€8.49/mo net, hel1). A store-and-serve registry never RUNS the amd64 platform images it holds, so arch is functionally neutral. Recorded via ops-advisor. #6288 attempted cx23→cx32 (8 GB) for OOM headroom, but **cx32 does not exist in the Hetzner catalog** (the plan's ~€6.80 figure was for a phantom type) → the registry-host-replace apply DESTROYED the old nbg1 host then failed `server type cx32 not found`. RESOLUTION (operator-chosen, #6288): migrate the registry nbg1→**hel1** and bump cx23→**cx33** (real 8 GB type, only +~€3/mo vs cx23; cheapest ≥8 GB in nbg1 was cpx32 ~€35/mo, ~6×). hel1 is where the rest of the fleet lives; the registry was only in nbg1 due to a since-resolved hel1 stock outage. cx33 is amd64 (does NOT start with `cax`) → local.registry_arch unchanged. The 35 GB zot store is a disposable GHCR MIRROR — the fresh hel1 volume re-fills from GHCR on the next CI dual-push (pulls fall through to GHCR meanwhile, non-release-blocking). THE CAP FOLLOWS THIS VAR — do not assume 7168m: zot's ADR-062 cgroup cap is DERIVED as `memory × 1024 − 1024` (zot-registry.tf local.registry_memory_cap_mb, read from the live Hetzner catalog), so it is 7168m on cx33 and 3072m on any 4 GB type. It was formerly a hardcoded 7168m literal with no edge to this variable, which meant changing this var to a 4 GB type left a cap that can never bind on 4096m of RAM — silently the UNCAPPED-on-cx23 condition that caused #6288. That is fixed; the host also self-reports zot_memory_capped + zot_memory_cap_mb so a gate can no longer assume the cap either."
  type        = string
  # cx33 (x86, 8 GB, hel1) — the real OOM remediation after #6288's cx32 attempt failed (cx32 is
  # not a real Hetzner type; a nonexistent type now fails at PLAN via data.hcloud_server_type.registry
  # instead of destroying the host first). cx33 is the 8 GB member of the same CX Intel line as cx23,
  # ~€8.49/mo net (+~€3/mo vs cx23). Paired with registry_location=hel1 below and the DERIVED cgroup
  # cap (7168m here), it is what #6288 shipped against the boot-scan host-OOM restart-loop.
  #
  # CAVEAT on the 8 GB floor (#6497 / #6463, 2026-07-15): #6288's OOM diagnosis was never confirmed.
  # ADR-062:47 says "no safe a-priori cap exists without a live measurement"; :68 calls the cap "a
  # STARTING value, not a measured peak". The retroactive check that would have settled it
  # (2026-07-09-fix-zot-restart-loop-oom-telemetry-plan.md:238 — peak zot_anon_mb >~3.5 GB confirms
  # the 4 GB host starved zot, well below flags the diagnosis wrong) never ran: the cx32 apply
  # destroyed the host before it booted with the reporter. The remediation is also confounded — it
  # changed RAM (4→8 GB) AND the store (~35 GB → fresh/empty) at once, so zot_restarts=0 was measured
  # on a host whose boot scan had nothing to scan. Live telemetry since: zot_anon_mb is 37 MB steady
  # (peak 47 over 3 days / 4 boots), ~0.5% of the 7168m cap, and it moved only 35→47 MB while the
  # store grew ~12 GB — consistent with zot's dedupe being INLINE over an on-disk BoltDB cache, not
  # an in-memory boot index. Still UNMEASURED: RSS during a boot scan of a LARGE store (every
  # sampled boot scanned a near-empty one). Do not treat 8 GB as evidence-backed; it is precautionary.
  default = "cx33"
}

variable "registry_volume_size" {
  description = "Size of the zot storage block volume in GB (Hetzner minimum is 10 GB), mounted at /var/lib/zot. Holds the OCI blobs for both platform images + backfilled release tags + cosign .sig referrers — never tmpfs (reboot-durable; a wiped registry breaks cold-boot pulls). The web-platform image is ~1.5-2 GB/version and dedupe shares little across versions, so 10 GB filled at ~3 retained versions (#6122). GROWN 30→60 GB (#6247, 2026-07-09): the PRIOR storage.retention keep-set (10 v* + 10 commit-sha + latest + UNBOUNDED sigs, per repo × 2 repos) legitimately exceeded 30 GB — SOLEUR_ZOT_DISK showed resize_ok=true + pcent=100 on a fully-grown 30 GB fs (a genuine capacity limit, NOT a resize regression), so #6246's gc/retention tightening could not reclaim below the KEEP set. Even the tightened set (now 5 v* + 5 commit-sha + latest + bounded sigs) wants durable margin, so 60 GB gives headroom above it. A bump resizes the volume in place (data survives); cloud-init-registry.yml resize2fs grows the fs on the next immutable redeploy."
  type        = number
  default     = 60
}

# --- Epic #5274 Phase 3, Sub-PR 3.D (ADR-068) — LUKS-at-rest cutover volume ---
variable "git_data_luks_volume_size" {
  description = "Size of the FRESH LUKS-at-rest git-data volume in GB (Hetzner minimum 10 GB). The cutover target (git-data-luks.tf / git-data-cutover.sh FRESH_ROOT). >= git_data_volume_size so the plaintext repo tree rsyncs onto it without ENOSPC. Guest-side LUKS: this is a plain hcloud_volume; cryptsetup runs in the guest."
  type        = number
  default     = 10
}

# --- #6178 (ADR-100) — the dedicated single-host Inngest singleton scheduler ---
variable "inngest_server_type" {
  description = "Hetzner server type for the dedicated Inngest host. Arch is DERIVED from this value (local.inngest_arch): cax* (Ampere) → arm64, cpx*/cx*/ccx* → amd64 — mirroring var.registry_server_type. Inngest is a SINGLETON control-plane SCHEDULER (not throughput-bound), so a small 2 vCPU / 4 GB box is ample. Provisions on whichever arch has Hetzner stock: cax11 (arm64, ~€5.99/mo) is cheapest; cpx22 (amd64, ~€19.49/mo) is the current default because cax* was EU-wide out of stock at Phase-2 provision time (#6178). Verify current Hetzner pricing before budget decisions — recorded via ops-advisor."
  type        = string
  default     = "cpx22"

  # #6178: the cloud-init now DERIVES arch from this type (local.inngest_arch) and selects the
  # matching inngest-CLI / Vector / Doppler-CLI download + checksum off it, so BOTH arm64 (cax*)
  # and amd64 (cpx*/cx*/ccx*) boot correctly — mirrors the zot-registry.tf dual-arch host. This
  # guard only rejects an unrecognized prefix (a typo) whose arch cannot be inferred.
  validation {
    condition     = can(regex("^(cax|cpx|cx|ccx)", var.inngest_server_type))
    error_message = "inngest_server_type must be a recognized Hetzner type (cax*=arm64, or cpx*/cx*/ccx*=amd64); arch is derived from the prefix."
  }
}

variable "inngest_redis_volume_size" {
  description = "Size of the dedicated Inngest host's Redis block volume in GB (Hetzner minimum is 10 GB), mounted at /mnt/data. Holds the queue/run-state AOF — never tmpfs (reboot-durable; a wiped AOF loses in-flight step.sleep/queued jobs). 10 GB is ample for the modest queue/run-state."
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

variable "betterstack_logs_token" {
  description = "Write-only Better Stack Logs ingest token (source 2457081, soleur-inngest-vector-prd). Provisioned into the ISOLATED soleur-inngest/prd project by inngest-betterstack-token.tf so the dedicated arm64 Inngest host's vector.service can ship journald->Better Stack Logs (#6197). Published to Doppler soleur/prd_terraform as TF_VAR_betterstack_logs_token (--name-transformer tf-var). NO default (hr-tf-variable-no-operator-mint-default) — the token already exists in soleur/prd; the Phase-0 gate is a read-only copy into prd_terraform."
  type        = string
  sensitive   = true
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

# #6178 — post-cutover web-host scheduling toggle. When true, a freshly-CREATED web
# host bootstraps + enables the co-located inngest-server.service (pre-cutover
# behavior). Default false: scheduling lives on the dedicated soleur-inngest host
# (10.0.1.40, ADR-100). Recreate-onto-false-config is the quiesce mechanism
# (hr-prod-host-config-change-immutable-redeploy); rollback = set true + recreate.
# `type = bool` is LOAD-BEARING: Terraform's `%{ if }` directive HCL-bool-converts its
# operand — the string "false" coerces to boolean false, so the rollback route
# `TF_VAR_web_colocate_inngest="false"` gates OFF correctly (and a non-bool string fails
# closed at plan time). Pinning `type = bool` keeps the variable-boundary contract explicit.
variable "web_colocate_inngest" {
  description = "When true, a freshly-created web host bootstraps + enables the co-located inngest-server.service (pre-cutover). Default false: scheduling lives on the dedicated soleur-inngest host (10.0.1.40, ADR-100, #6178). Recreate is the quiesce mechanism (hr-prod-host-config-change-immutable-redeploy)."
  type        = bool
  default     = false
}
