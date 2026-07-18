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
# into the web-platform app runtime. Minting a dedicated Zone.DNS:Edit-only token means a
# runtime leak of `CF_API_TOKEN_DNS_EDIT` is blast-radius-limited to DNS edits on the one
# zone — it cannot touch tunnels, Access, R2, rulesets, or other zones. This mirrors the
# per-scope narrow-token pattern already used for cf_api_token_rulesets / _bot_management /
# _r2 / _zone_settings (see main.tf provider aliases).
#
# SCOPE
# -----
#   permission group : "DNS Write"  (zone-level; referenced by NAME via the
#                       cloudflare_api_token_permission_groups data source, not a magic ID)
#   resource scope    : com.cloudflare.api.account.zone.<var.cf_zone_id> = "*"  (single zone)
#   ownership         : USER-owned token (v4 `cloudflare_api_token` mints via the CF user
#                       tokens API; the resource has no account_id field — the policy's
#                       `resources` map is what pins it to the one zone).
#   published to      : Doppler soleur/prd as CF_API_TOKEN_DNS_EDIT (the config the
#                       web-platform/Inngest runtime reads).
#
# VALUE IS WRITE-ONLY-ON-CREATE (important caveat)
# ------------------------------------------------
# `cloudflare_api_token.value` is `computed` + `sensitive` and is returned by the CF API
# ONLY at create time (Terraform persists it in state thereafter). The doppler_secret below
# reads that value in the SAME apply graph. `lifecycle { ignore_changes = [value] }` (matching
# the ghcr-read-credential.tf / github-app.tf precedent) prevents refresh-time value churn
# from proposing a no-op Doppler rewrite. To ROTATE: `terraform taint` (or -replace) the
# cloudflare_api_token, then MANUALLY re-apply BOTH resources together and re-verify the
# Doppler value — because ignore_changes suppresses automatic propagation of a new value.
#
# ZERO OPERATOR MINT (hr-tf-variable-no-operator-mint-default)
# ------------------------------------------------------------
# PRIMARY path: the token is minted by Terraform (this file). There is NO
# `variable "cf_api_token_dns_edit"` and no operator hand-mint step in the happy path.
#
# The minting provider is the DEFAULT `cloudflare` provider (api_token = var.cf_api_token).
# Creating an API token requires the "User API Tokens: Edit" (a.k.a. "API Tokens: Edit")
# permission, which `var.cf_api_token` (Tunnel/Access/DNS/Notifications) does NOT list. So
# the CREATE apply of `cloudflare_api_token.gh_pages_cert_reissue_dns_edit` MAY 403. If it
# does, the FALLBACK (operator-visible, still no long-lived secret in code) is:
#   1. Operator mints a Zone.DNS:Edit-on-soleur.ai token in the CF dashboard.
#   2. Store it as CF_API_TOKEN_DNS_EDIT in Doppler soleur/prd (runtime) directly, OR
#      re-run this apply after temporarily granting var.cf_api_token "User API Tokens: Edit".
# Either way the cron function fail-closes gracefully (precondition_blocked, no crash) until
# the secret lands, so an unresolved 403 never breaks the app.
#
# APPLY ROUTING (NOT covered by the push-triggered merge-apply — read before merging)
# -----------------------------------------------------------------------------------
# These two resources are DELIBERATELY NOT added to the `-target=` allow-list in
# .github/workflows/apply-web-platform-infra.yml. Rationale: that allow-list runs on EVERY
# push to main touching infra/*.tf. Because var.cf_api_token almost certainly lacks "User
# API Tokens: Edit", auto-targeting the mint here would 403 on the next push and — since a
# failed `-target` apply fails the whole run — WEDGE every subsequent web-platform infra
# deploy (same class of repo-wide-block footgun as the capacity-shortage `-replace`). To
# avoid that, apply these two out-of-band, JUST-IN-TIME, after confirming/granting the mint
# scope, in a maintenance window:
#
#   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
#     terraform apply \
#       -target=cloudflare_api_token.gh_pages_cert_reissue_dns_edit \
#       -target=doppler_secret.cf_api_token_dns_edit
#
# (The `data.cloudflare_api_token_permission_groups.all` read needs only list scope, which
# any CF token has.) Pre-merge you can still `terraform validate` + `plan` this file with a
# read-limited token — the scope check bites only at apply (narrow-token plan-vs-apply
# asymmetry). If/when the operator decides the mint scope will always be present, this file
# can be promoted into the push allow-list in a follow-up.

# Zone-level permission groups, keyed by NAME → group ID. Preferred over a hard-coded magic
# ID so a CF-side ID rotation doesn't silently break the mint. (For reference, the "DNS
# Write" group has historically been id 4755a26eedb94da69e1066d98aa820be; the data source is
# the source of truth.)
data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "gh_pages_cert_reissue_dns_edit" {
  name = "web-platform-gh-pages-cert-reissue-dns-edit"

  policy {
    effect            = "allow"
    permission_groups = [data.cloudflare_api_token_permission_groups.all.zone["DNS Write"]]
    # Single-zone scope: soleur.ai only. `"*"` = all operations the permission group grants,
    # but confined to this one zone resource.
    resources = {
      "com.cloudflare.api.account.zone.${var.cf_zone_id}" = "*"
    }
  }
}

# Publish the minted token value into the config the web-platform/Inngest runtime reads.
# Mirrors the ghcr-read-credential.tf precedent: config = "prd", ignore_changes = [value].
# dev is intentionally NOT provisioned — the cert-reissue cron runs in prd only.
resource "doppler_secret" "cf_api_token_dns_edit" {
  project = "soleur"
  config  = "prd"
  name    = "CF_API_TOKEN_DNS_EDIT"
  value   = cloudflare_api_token.gh_pages_cert_reissue_dns_edit.value

  lifecycle {
    # Value source of truth on rotation is a deliberate re-apply of BOTH resources (see the
    # "VALUE IS WRITE-ONLY-ON-CREATE" note in the header); ignore_changes prevents refresh-
    # time churn from proposing a spurious Doppler rewrite.
    ignore_changes = [value]
  }
}
