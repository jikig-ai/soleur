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
#   - uaBlock         Any future User-Agent Blocking rules (camelCase per
#                     CF API: lowercase `uablock` is listed in cloudflare-go
#                     v0.115.0 `RulesetActionParameterProductValues()` but
#                     rejected by the API with error 20119 "skip action
#                     parameter product 'uablock' is invalid".)
#   - hot             Hotlink Protection (defense-in-depth)
#   - http_ratelimit                 phase: don't rate-limit AI crawlers
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
#
#   3. (HISTORIC, now SKIPPED — see below.) Originally excluded because
#      `waf=off` + assumed Managed Ruleset no-op. Post-apply probe showed
#      13/20 crawler UAs still 403 while bic/securityLevel/uaBlock/hot were
#      already skipped — confirming Cloudflare's zone-level "Block AI
#      Scrapers and Crawlers" feature is active and implemented via the
#      Managed Free Ruleset, blocking our UAs in this phase. Re-add the
#      phase skip for this narrow UA-matched scope. Emergency-rule bypass
#      risk is bounded to (a) clients spoofing the 20 listed AI UAs AND
#      (b) matching a future zone-wide Log4Shell-style rule — a very
#      narrow intersection vs. the current 100% AI crawler block.
#      Retighten to `skip_rules = [<ai-block-rule-id>]` once the rule ID
#      can be read (current CF_API_TOKEN_RULESETS scope can't enumerate
#      managed-ruleset rules).
resource "cloudflare_ruleset" "allowlist_ai_crawlers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Allowlist documented AI crawler user-agents"
  description = "Skip legacy security products (bic, securityLevel, uaBlock, hot) and the http_ratelimit + http_request_firewall_managed phases for documented AI crawler UAs (GPTBot, ClaudeBot, PerplexityBot, etc.). See issue #2662 and the 2026-04-19 AEO audit."
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
      # `ccbot` would ideally use a word-boundary regex to avoid colliding
      # with UAs like `MyCCBot` / `RogueCCBot`, but the `matches` operator
      # requires a CF Business plan or WAF Advanced (this zone is Free —
      # apply fails with "not entitled"). Accept the plain-substring
      # trade-off: allowlists real CCBot plus any `*ccbot*` spoof. Cost of
      # the false-positive: a spoofed scraper gets BIC/securityLevel
      # bypass it was already reaching the origin for. Retighten to the
      # `(^|[^a-z])ccbot([^a-z]|$)` regex once the zone upgrades past Free.
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
        "uaBlock",
        "hot",
      ]
    }

    # CF auto-enables logging on skip actions in http_request_firewall_custom;
    # declaring it here stops the provider from planning replacement every run
    # and avoids the "provider produced inconsistent result" post-apply bug.
    logging {
      enabled = true
    }
  }
}
