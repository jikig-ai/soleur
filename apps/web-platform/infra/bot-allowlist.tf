# Allowlist documented AI crawler user-agents at Cloudflare's edge.
#
# Why: Cloudflare's Browser Integrity Check (BIC) and Security Level / IP
# reputation were blocking AI crawlers (GPTBot, ClaudeBot, PerplexityBot, etc.)
# with HTTP 403 on soleur.ai/*, making every AEO investment (FAQPage schema,
# self-contained FAQ answers, citation-ready prose) invisible to AI answer
# engines. See the 2026-04-19 AEO audit §P0-1
# (knowledge-base/marketing/audits/soleur-ai/2026-04-19-aeo-audit.md) and
# issue #2662.
#
# Scope: the skip rule affects ONLY requests whose User-Agent matches one of
# the documented AI crawler tokens. All other traffic retains the full
# bot-fight / BIC / security_level posture unchanged.
#
# Product/phase skip literals are validated against cloudflare-go v0.115.0
# `RulesetActionParameterProductValues()` and `RulesetPhaseValues()` (the
# enums the v4.52.7 Terraform provider validates against). Casing matters:
#
#   - bic             Browser Integrity Check (PRIMARY blocker — heuristic
#                     refuses AI-crawler-style UAs on Free plan)
#   - securityLevel   IP-reputation based challenge/block (camelCase
#                     intentional per CF's enum)
#   - uablock         Any future User-Agent Blocking rules
#   - hot             Hotlink Protection (defense-in-depth)
#   - http_ratelimit                 phase: don't rate-limit AI crawlers
#   - http_request_firewall_managed  phase: future-proof if waf=on later
#
# NOT in this list (intentional):
#
#   1. Bot Fight Mode (BFM). Not skippable via WAF custom rules per CF docs
#      ("you cannot bypass or skip Bot Fight Mode using the Skip action in
#      WAF custom rules or using Page Rules"). BFM is not currently the
#      blocker on this zone; if enabled later, remediation is zone-wide
#      disablement, not extension of this rule.
#
#   2. Super Bot Fight Mode phase `http_request_sbfm`. Pro+ plan only (this
#      zone is Free) AND the phase literal is NOT in the v4.52.7 provider's
#      `RulesetPhaseValues()` enum — adding it would fail `terraform
#      validate`. Revisit on provider-v5 upgrade.
resource "cloudflare_ruleset" "allowlist_ai_crawlers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Allowlist documented AI crawler user-agents"
  description = "Skip legacy security products + bot/ratelimit/managed-WAF phases for documented AI crawler UAs (GPTBot, ClaudeBot, PerplexityBot, etc.). See issue #2662 and the 2026-04-19 AEO audit."
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "skip"
    description = "Allowlist AI crawler UAs (GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, anthropic-ai, claude-web, PerplexityBot, Perplexity-User, CCBot, Google-Extended, GoogleOther, Applebot-Extended, Amazonbot, Bytespider, Meta-ExternalAgent, Meta-ExternalFetcher, cohere-ai, Diffbot, DuckAssistBot, YouBot)"
    enabled     = true

    # Case-insensitive substring match against the User-Agent. Each token is
    # distinct enough that false positives are negligible (no legitimate
    # browser UA contains "gptbot", "claudebot", etc.). Canonical tokens
    # from each vendor's published docs — see plan Research Insights for
    # source URLs.
    expression = join(" or ", [
      "(lower(http.user_agent) contains \"gptbot\")",
      "(lower(http.user_agent) contains \"oai-searchbot\")",
      "(lower(http.user_agent) contains \"chatgpt-user\")",
      "(lower(http.user_agent) contains \"claudebot\")",
      "(lower(http.user_agent) contains \"anthropic-ai\")",
      "(lower(http.user_agent) contains \"claude-web\")",
      "(lower(http.user_agent) contains \"perplexitybot\")",
      "(lower(http.user_agent) contains \"perplexity-user\")",
      "(lower(http.user_agent) contains \"ccbot\")",
      "(lower(http.user_agent) contains \"google-extended\")",
      "(lower(http.user_agent) contains \"googleother\")",
      "(lower(http.user_agent) contains \"applebot-extended\")",
      "(lower(http.user_agent) contains \"amazonbot\")",
      "(lower(http.user_agent) contains \"bytespider\")",
      "(lower(http.user_agent) contains \"meta-externalagent\")",
      "(lower(http.user_agent) contains \"meta-externalfetcher\")",
      "(lower(http.user_agent) contains \"cohere-ai\")",
      "(lower(http.user_agent) contains \"diffbot\")",
      "(lower(http.user_agent) contains \"duckassistbot\")",
      "(lower(http.user_agent) contains \"youbot\")",
    ])

    action_parameters {
      phases = [
        "http_ratelimit",
        "http_request_firewall_managed",
      ]

      products = [
        "bic",
        "securityLevel",
        "uablock",
        "hot",
      ]
    }
  }
}
