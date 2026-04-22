# Cloudflare zone-level bot-management settings for soleur.ai.
#
# Codifies three settings that live outside the standard WAF phase
# pipeline — cloudflare_ruleset skip actions in http_request_firewall_*
# phases cannot bypass them:
#
#   - ai_bots_protection = "disabled"
#
#       CF's zone-level "Block AI bots" feature (Security → Settings →
#       Bot traffic → Block AI bots). When "block", CF returns 403 to
#       UAs it categorizes as AI training crawlers (GPTBot, ClaudeBot,
#       CCBot, anthropic-ai, PerplexityBot, Amazonbot, Bytespider,
#       cohere-ai, DuckAssistBot, YouBot, OAI-SearchBot, ChatGPT-User,
#       Perplexity-User). Incompatible with AEO goals — see issue #2662
#       and the 2026-04-19 AEO audit §P0-1. Our bot-allowlist.tf custom
#       ruleset narrowly allowlists the 20 documented AI crawler UAs
#       across bic / securityLevel / uaBlock / hot products and the
#       http_ratelimit + http_request_firewall_managed phases, which is
#       a tighter scope than zone-wide disablement of "Block AI bots"
#       if and when CF extends what that feature blocks.
#
#   - fight_mode = false
#
#       Mirrors the current dashboard state (Bot Fight Mode: OFF) so
#       `terraform plan` drift-detects any accidental dashboard toggle.
#       Re-enabling BFM would re-block the AI crawler UAs at a different
#       pipeline stage that the custom ruleset in bot-allowlist.tf cannot
#       skip (per CF docs: "you cannot bypass or skip Bot Fight Mode
#       using the Skip action in WAF custom rules or using Page Rules").
#
#   - enable_js = true
#
#       Mirrors the current dashboard state (JS Detections: On). No
#       change; declared so drift is visible.
#
# The resource uses a narrow CF_API_TOKEN_BOT_MANAGEMENT token scoped to
# Bot Management:Edit on soleur.ai only. See main.tf provider alias
# "bot_management" and the variable in variables.tf.
resource "cloudflare_bot_management" "soleur_ai" {
  provider = cloudflare.bot_management
  zone_id  = var.cf_zone_id

  ai_bots_protection = "disabled"
  fight_mode         = false
  enable_js          = true
}
