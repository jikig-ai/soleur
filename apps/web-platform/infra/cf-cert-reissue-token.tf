# Cloudflare DNS-edit-only API token for the #6657 GitHub Pages cert-reissue routine.
#
# PURPOSE
# -------
# The Inngest function `cron-gh-pages-cert-reissue.ts` (web-platform runtime, Doppler
# config `prd`) transiently flips the apex + www `proxied` flag false→true to let GitHub
# Pages complete its public-DNS `dig`-based cert validation (GH Pages checks for the
# 185.199.108-111.153 A records; with CF proxy on it sees 104.x/172.x anycast IPs and the
# cert never provisions — see the "GH Pages domain-config validator" learning). To edit
# those records the runtime needs a Cloudflare token with **Zone.DNS:Edit on the soleur.ai
# zone ONLY**. It reads `process.env.CF_API_TOKEN_DNS_EDIT` + the existing `CF_ZONE_ID`.
#
# WHY A DISTINCT, NARROW TOKEN (not the broad `var.cf_api_token`)
# --------------------------------------------------------------
# `var.cf_api_token` carries Tunnel/Access/DNS/Notifications scope and is NOT injected
# into the web-platform app runtime. A dedicated Zone.DNS:Edit-only token means a runtime
# leak of `CF_API_TOKEN_DNS_EDIT` is blast-radius-limited to DNS edits on the one zone — it
# cannot touch tunnels, Access, R2, rulesets, or other zones. This mirrors the per-scope
# narrow-token pattern already used for cf_api_token_rulesets / _bot_management / _r2 /
# _zone_settings (see main.tf provider aliases + variables.tf).
#
# OPERATOR-MINTED (why NOT a `cloudflare_api_token` resource — hr-tf-variable-no-operator-mint-default)
# ----------------------------------------------------------------------------------------------------
# hr-tf-variable-no-operator-mint-default PREFERS a provider-side mint, but that path is
# UNAVAILABLE here: minting a `cloudflare_api_token` requires the "User API Tokens: Edit"
# (a.k.a. "API Tokens: Edit") permission, which `var.cf_api_token` (Tunnel/Access/DNS/
# Notifications) does NOT carry — a `cloudflare_api_token` apply 403s (CF error 9109). So
# the token is OPERATOR-minted out-of-band and this file only PUBLISHES it, exactly like
# resend.tf's `var.resend_receiving_api_key` and the r2 / rulesets / bot_management narrow
# tokens. The live token is named **"Edit zone DNS"** in the Cloudflare dashboard.
#
# The operator-supplied value lives in Doppler `prd_terraform` as CF_API_TOKEN_DNS_EDIT and
# reaches Terraform as `TF_VAR_cf_api_token_dns_edit` (via `--name-transformer tf-var`; see
# variables.tf). The doppler_secret below republishes it into `prd` — the config the
# web-platform/Inngest runtime reads. If the value is absent the cron fail-closes gracefully
# (precondition_blocked, no crash) until the secret lands, so a missing token never breaks
# the app.
#
# VALUE IS SET-ONCE FROM THE VARIABLE (rotation)
# ----------------------------------------------
# `lifecycle { ignore_changes = [value] }` (matching resend.tf / github-app.tf's
# operator-supplied secrets) prevents refresh-time churn from proposing a spurious Doppler
# rewrite. To ROTATE: operator mints a fresh "Edit zone DNS" token, updates
# CF_API_TOKEN_DNS_EDIT in BOTH Doppler `prd_terraform` (the TF-var source) and `prd` (the
# runtime read) — or re-applies this doppler_secret after temporarily clearing ignore_changes.

# Publish the operator-minted DNS-edit token into the config the web-platform/Inngest
# runtime reads. Mirrors resend.tf / github-app.tf: config = "prd", value = var.*,
# visibility masked, ignore_changes = [value]. dev is intentionally NOT provisioned —
# the cert-reissue cron runs in prd only. This resource IS in the push-triggered
# `-target` allow-list (apply-web-platform-infra.yml): it is a pure Doppler write (needs
# only var.doppler_token, always present), so — unlike the removed cloudflare_api_token
# mint — it cannot 403 and wedge the shared infra apply.
resource "doppler_secret" "cf_api_token_dns_edit" {
  project    = "soleur"
  config     = "prd"
  name       = "CF_API_TOKEN_DNS_EDIT"
  value      = var.cf_api_token_dns_edit
  visibility = "masked"

  lifecycle {
    # dev/prd isolation: config = "prd" pinned explicitly; cannot land in dev without an
    # edit to this file (caught at PR review). Value source of truth on rotation is the
    # operator-updated prd_terraform TF var; ignore_changes prevents refresh-time churn.
    ignore_changes = [value]
  }
}
