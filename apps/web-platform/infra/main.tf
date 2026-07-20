terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "web-platform/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 does not support S3 conditional writes, so there is NO terraform state
    # lock on this backend. The shared GitHub Actions concurrency group
    # `terraform-apply-web-platform-host` (identical literal in BOTH
    # apply-web-platform-infra.yml and apply-deploy-pipeline-fix.yml) is the SOLE
    # serializer preventing concurrent applies from clobbering this state object
    # (#4844). Do NOT drop that group believing R2 locks — it does not.
    use_lockfile = false
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    # Phase 0.3-resolved exact versions (see inngest.tf comment). Bump via
    # `terraform init -upgrade` + commit the lockfile diff.
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.21"
    }
    betteruptime = {
      source  = "BetterStackHQ/better-uptime"
      version = "~> 0.20"
    }
    # PR-H (#3244) — github_actions_secret resource for the kb-drift cron
    # workflow's DOPPLER_TOKEN_KB_DRIFT publish. Provider write surface is
    # limited to that one resource type in this root.
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    # CI SSH keypair generation (see ci-ssh-key.tf) — closes the L7 gap
    # left by PR #4181's L3-only CF Tunnel SSH bridge.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  # >= 1.7, not 1.6: seo-config-rules.tf uses `for_each` inside an `import` block,
  # which landed in Terraform 1.7.0 ("import: for_each can now be used to expand the
  # import block", v1.7.0 CHANGELOG). Plain `import` is 1.5. CI pins 1.10.5 so CI
  # never exercised the floor; an operator on 1.6.x hit a parse error the constraint
  # promised would not happen.
  required_version = ">= 1.7"
}

provider "doppler" {
  doppler_token = var.doppler_token_tf
}

provider "betteruptime" {
  api_token = var.betterstack_api_token
}

# PR-H (#3244) — GitHub provider for Actions-secret publishing (kb-drift).
# #4150 + #4144 — switched from PAT auth (var.github_actions_token, deleted) to
# App-installation auth. The soleur-ai App (id 3261325, org-wide installation
# 122213433 on jikig-ai) declares `secrets:write` in its permissions; the
# integrations/github provider exchanges App-credentials for a short-lived
# installation token at each `terraform plan/apply`. Net narrowing vs.
# long-lived PAT. See AGENTS.core.md hr-github-app-auth-not-pat.
# autonomy-considered: reuse-applied (App credentials already in prd_terraform).
provider "github" {
  owner = "jikig-ai"
  app_auth {
    id              = var.github_app_id
    installation_id = "122213433"
    pem_file        = var.github_app_private_key
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cf_api_token
}

# Separate provider for zone-settings APIs (HSTS / security_header).
# The default cf_api_token lacks Zone Settings:Edit; rather than expanding
# its scope, this alias uses a narrow token that only grants Zone Settings
# on soleur.ai. See cloudflare-settings.tf and #2527.
provider "cloudflare" {
  alias     = "zone_settings"
  api_token = var.cf_api_token_zone_settings
}

# Separate provider for Cloudflare Rulesets APIs. The default cf_api_token
# holds none of the ruleset permissions; this alias uses a token scoped to
# them on soleur.ai.
#
# The AUTHORITATIVE permission set is the `cf_api_token_rulesets` description
# in variables.tf (the scope ledger) — do not maintain a second enumeration
# here; this list had already drifted two phases behind it. What follows is
# only the phase-to-file consumer mapping. Current consumers:
#   - cache.tf                    (http_request_cache_settings)  — #2542
#   - bot-allowlist.tf            (http_request_firewall_custom) — #2662
#   - seo-rulesets.tf             (http_request_dynamic_redirect; absorbed the
#     2026-05-18 acme-challenge ruleset as Rule 10) — #3296
#   - seo-bulk-redirects.tf       (ACCOUNT-level http_request_redirect +
#     redirect list — needs Account Rulesets:Edit + Account Filter Lists:Edit,
#     the widen tracked in #5092) — #3367
#   - seo-config-rules.tf         (http_config_settings — Email Obfuscation off
#     on the marketing hosts; needed a Config Rules:Edit widen, 2026-07-20 GSC
#     "Not found (404)" on /cdn-cgi/l/email-protection)
#
# Decision rule for the next phase added here: ADR-130. Summary — a permission
# in the SAME API family (the zone/account rulesets endpoints) widens THIS
# token; a distinct API surface (R2 object storage, zone settings) mints a
# narrow alias. The ADR weighs both axes (least-privilege AND the Terraform
# root-var hazard) and records #5092 honestly as a scope ESCALATION to
# account-level rather than as clean supporting precedent. Read it before
# minting or widening — the rule is not "always widen".
provider "cloudflare" {
  alias     = "rulesets"
  api_token = var.cf_api_token_rulesets
}

# Separate provider for Bot Management APIs. Cloudflare's "Block AI bots"
# feature (which blocks GPTBot/ClaudeBot/CCBot/etc. at the zone edge)
# operates outside the standard WAF phase pipeline — a
# `cloudflare_ruleset` `skip` action in http_request_firewall_custom or
# http_request_firewall_managed does NOT bypass it. The feature is
# controlled by the `ai_bots_protection` field on the bot_management
# endpoint. See cloudflare_bot_management.soleur_ai and #2662.
provider "cloudflare" {
  alias     = "bot_management"
  api_token = var.cf_api_token_bot_management
}

# Separate provider for Cloudflare R2 (object storage). The default cf_api_token is scoped
# "Tunnel, Access, DNS, Notifications" and lacks Workers R2 Storage:Edit (verified 2026-07-18
# by a live 403 on GET /accounts/<id>/r2/buckets). This alias uses a narrow token scoped to
# Workers R2 Storage:Edit only. Current consumer:
#   - workspaces-luks-header.tf (cloudflare_r2_bucket.workspaces_luks_header) — #6649 / #6604
provider "cloudflare" {
  alias     = "r2"
  api_token = var.cf_api_token_r2
}
