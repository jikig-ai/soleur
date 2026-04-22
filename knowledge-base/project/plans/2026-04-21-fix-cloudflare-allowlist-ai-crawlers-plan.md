# Fix: Cloudflare 403 blocks GPTBot/ClaudeBot/PerplexityBot on soleur.ai

- **Issue:** #2662 (P0, `domain/marketing`, milestone "Phase 3: Make it Sticky")
- **Source:** `knowledge-base/marketing/audits/soleur-ai/2026-04-19-aeo-audit.md` §P0-1
- **Branch:** `feat-one-shot-cloudflare-allowlist-ai-crawlers`
- **Files to edit:** none (new file only)
- **Files to create:** `apps/web-platform/infra/bot-allowlist.tf`
- **Type:** `fix(infra)` / `semver:patch`

## Enhancement Summary

**Deepened on:** 2026-04-21
**Sections enhanced:** Overview, Hypotheses, Implementation Phases 2 + 4, Risks, Research Insights
**Research sources used:** Context7 (Cloudflare Terraform provider), direct GitHub source inspection (cloudflare-go v0.115.0 `rulesets.go`), Cloudflare API (live zone settings probe), 3 prior institutional learnings (Context7 version mismatch, CF v4/v5 naming, CF API token Playwright editing), Cloudflare docs (skip options, BFM skippability, verified bots).

### Key improvements discovered during deepen pass

1. **Product-enum casing correction (CRITICAL — would fail `terraform validate`):** The initial plan used camelCase `uaBlock`, `rateLimit`, `zoneLockdown`. The authoritative source (cloudflare-go `rulesets.go`, consumed by Terraform provider v4.52.7) defines these enum values as lowercase: `uablock`, `ratelimit`, `zonelockdown`. Only `securityLevel` stays camelCase (intentional — verified from source). Context7 returned the wrong casing; direct source inspection caught it.
2. **`http_request_sbfm` is NOT in the v4 provider `phases` enum (CRITICAL).** The Cloudflare public docs page `waf/custom-rules/skip/options/` lists it, but the pinned v4.52.7 provider's `RulesetPhaseValues()` slice does NOT include it. Including it in `action_parameters.phases` would fail `terraform validate` with "value not in allowed list". The initial plan included SBFM as "defense-in-depth for future plan upgrade" — this was incorrect for the current provider pin. Removed; noted as a follow-up when the repo upgrades to provider v5 or adopts the Cloudflare Plugin Framework-based resource.
3. **Terraform validate preflight added to Phase 2.** Per `2026-04-10-context7-terraform-provider-version-mismatch.md`, Context7 docs routinely drift from pinned provider versions. The Phase 2 deliverable now includes a mandatory `terraform validate` step immediately after writing `bot-allowlist.tf` and BEFORE committing.
4. **v4 block syntax confirmed (no change, but now explicitly verified):** `cloudflare_ruleset.rules` is a `ListNestedBlock` in v4 — use `rules { ... }` block syntax, NOT `rules = [ { ... } ]` list-attribute syntax. Context7 returned the v5 list syntax; repo precedent (`cache.tf`) and direct source inspection confirmed v4 uses blocks.
5. **Playwright token-editing Phase 1 workaround escalated:** If Phase 1 needs to expand the `CF_API_TOKEN_RULESETS` scope via the CF dashboard, the React Select comboboxes there are flaky with standard Playwright clicks. The workaround (`pressSequentially` + JS-dispatch `mouseDown`) from `2026-04-10-cloudflare-dashboard-react-select-playwright-workaround.md` is pre-linked in Phase 1.
6. **Issue corpus verification:** `gh issue view 2662` confirms OPEN, P0, `domain/marketing`, milestone "Phase 3: Make it Sticky". Plan references are consistent with live state.

### New considerations surfaced

- If the repo later upgrades to Cloudflare provider v5, the resource rename is `cloudflare_ruleset` (unchanged for this resource type — renames hit `cloudflare_record` → `cloudflare_dns_record`, but `cloudflare_ruleset` keeps its name). However, `rules` syntax changes from block to list-attribute (`rules = [...]`), and the enum for `phases` may include `http_request_sbfm`. The v5 migration plan for this file is ~5 lines of edits; not in scope here.
- The Cloudflare dashboard provides a one-click "Block AI bots" managed toggle (separate from Bot Fight Mode). This zone does not currently have it enabled (verified via `/settings` probe — no such setting surfaced). If a future operator flips that toggle in the dashboard, this allowlist rule (`http_request_firewall_custom`, runs first in the pipeline) should still short-circuit the downstream AI-block via the `http_request_firewall_managed` phase skip already included. Explicitly documented in Risks.

## Overview

`soleur.ai/` (the Eleventy docs site proxied by Cloudflare → GitHub Pages origin) returns HTTP 403 to AI-crawler user agents (`GPTBot`, `ClaudeBot`, `PerplexityBot`, `WebFetch`-class) while browsers get HTTP 200 (→ 301 to `www.soleur.ai`). Every AEO investment (FAQPage schema, self-contained FAQs, citation-ready answers) is invisible to AI answer engines until this is fixed.

The fix adds a Cloudflare **custom firewall ruleset** (phase `http_request_firewall_custom`) with a single `skip` rule that allowlists documented AI crawler UAs by bypassing the legacy security products that are blocking them (Browser Integrity Check, Security Level / IP reputation, User-Agent blocking, Hotlink Protection) plus the bot/ratelimit phases. The scope is **allowlist-only, AI-UA-only** — the bot-fight posture for all other traffic remains unchanged.

## Hypotheses (L3 → L7 triage)

Issue #2662 is a 403-blocking symptom. Applying the L3→L7 diagnostic order per AGENTS.md `hr-ssh-diagnosis-verify-firewall`:

| Layer | Hypothesis | Verification | Status |
|---|---|---|---|
| L3 (Hetzner firewall) | Origin firewall drops AI-UA traffic | N/A — `soleur.ai` apex resolves to GitHub Pages (`185.199.108-111.153`), NOT the Hetzner origin (see `dns.tf` `cloudflare_record.github_pages`). Hetzner firewall in `firewall.tf` guards only `app.soleur.ai`. | **Ruled out** |
| L4 (TLS / CF edge routing) | Edge certificate or SNI fails | `curl -sI -A "GPTBot/1.0" https://soleur.ai/` returns `HTTP/2 403` with `server: cloudflare` and a `cf-ray` header. TLS completed; CF responded. | **Ruled out** |
| L7 (Cloudflare application layer) | CF blocks on UA signature or IP reputation | Zone setting audit (see Research Insights) shows `browser_check=on`, `security_level=medium`, `waf=off`, `bot_fight_mode` is undefined at the `/settings` endpoint. Free plan. | **Confirmed** |

**Root cause is L7, Cloudflare edge.** Specifically:

1. **Browser Integrity Check (BIC)** — `browser_check=on`. BIC blocks requests whose headers look like "spammy bots" (short UAs without full browser headers, missing `Accept-Language`, etc.). AI crawler UAs trip this heuristic. BIC is a **legacy security product** that IS skippable via the `bic` product in `skip` action_parameters on Free plans.
2. **Security Level (IP reputation)** — `security_level=medium`. Threat scores ≥ medium trigger Managed Challenges or Blocks for known-botnet IPs. OpenAI/Anthropic crawler IPs occasionally appear on Project Honeypot lists. Skippable via product `securityLevel`.
3. **Bot Fight Mode** — Not currently a confirmed cause (the zone setting endpoint reports `bot_fight_mode` as undefined on Free plan). BFM is **NOT skippable** via WAF custom rules (Cloudflare docs: "You cannot bypass or skip Bot Fight Mode using the Skip action in WAF custom rules or using Page Rules"). If BFM is later enabled via dashboard, only disabling it zone-wide would unblock — but the current audit does not indicate BFM is the culprit.
4. **Super Bot Fight Mode (SBFM)** — Pro+ plans only. Not relevant on Free. The `http_request_sbfm` skip phase was considered for defense-in-depth but is **NOT in the pinned v4.52.7 provider's phase enum** (see Research Insights: "Cloudflare skip-action enums — two sources, one mismatch"). Including it would fail `terraform validate`. Revisit when the repo upgrades to provider v5 and/or the zone upgrades to Pro.

The fix targets (1) and (2) directly, which are the plan-compatible, skippable products. The rule also includes the bot/ratelimit phases for future-proofing.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Allowlist AI crawler UAs in the Cloudflare WAF ruleset" | `waf=off` on this zone (managed WAF is OFF). The block is NOT from the WAF. | Target `http_request_firewall_custom` phase (still a ruleset) with `skip` action on **legacy products** (`bic`, `securityLevel`, `uablock`, `hot` — enum casing verified from cloudflare-go source) and phases (`http_ratelimit`, `http_request_firewall_managed` — `http_request_sbfm` is NOT in v4 enum). The language "WAF ruleset" in the issue is close enough — the fix IS a Cloudflare ruleset in the WAF family. Clarify in the PR body. |
| "Do NOT weaken bot fight globally" | Bot Fight Mode is not currently identified as the blocker. BFM cannot be skipped via custom rules anyway. | The fix is strictly additive: a new allowlist ruleset. It does NOT disable BFM, BIC, security_level, or any existing posture for non-AI traffic. Browsers, malicious bots, and non-AI crawlers retain the same protection. |
| "Terraform via apps/web-platform/infra/" | Confirmed. Existing `cloudflare_ruleset` precedent in `cache.tf`. Existing narrow CF API token alias pattern in `main.tf` (`zone_settings`, `rulesets`). | Use the **existing `cloudflare.rulesets` provider alias** (CF_API_TOKEN_RULESETS). This token already has `Cache Rules:Edit` — we need to extend its scope to include `Zone WAF:Edit` (a.k.a. "Account WAF" or "Zone Firewall") so it can write `http_request_firewall_custom` rules. No new Doppler secret needed. See "Post-merge operator steps". |

## Implementation Phases

### Phase 1: Provider-permission preflight (investigation)

Before writing any Terraform, confirm which CF API token scope is needed to PATCH `http_request_firewall_custom` rulesets. The existing `CF_API_TOKEN_RULESETS` is documented as "Cache Rules:Edit on soleur.ai" (see `main.tf`). Custom firewall rulesets may need a different scope ("Zone Firewall:Edit" / "Zone WAF:Edit").

- [x] Read `apps/web-platform/infra/main.tf` to confirm current `cf_api_token_rulesets` variable binding.
- [x] Run `curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $CF_API_TOKEN_RULESETS" | jq` to confirm the token is active and see its scopes (the CF API does not return scope details, so this is a liveness probe).
- [x] Attempt a **read** of `http_request_firewall_custom` entrypoint with the current `CF_API_TOKEN_RULESETS`:

    ```bash
    CF_TOKEN=$(doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain)
    ZONE=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
    curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE}/rulesets/phases/http_request_firewall_custom/entrypoint" \
      -H "Authorization: Bearer ${CF_TOKEN}" | jq -r '.success, .errors'
    ```

    If `.success == true` (even with empty rules), the token can at least read this phase. If `.success == false` with code 10000, the token needs permission expansion.

    **Result 2026-04-21:** `{"success": false, "errors": [{"message": "request is not authorized"}]}`. `terraform plan` still succeeds (refresh of existing rulesets is permitted); the scope expansion is only required at apply time for the CREATE call.

- [ ] If permission expansion is needed, automate via Playwright MCP per runbook `knowledge-base/project/learnings/2026-03-21-cloudflare-api-token-permission-editing.md`. The target token name is `soleur-terraform-rulesets` (or whatever name is shown in the CF dashboard for the `CF_API_TOKEN_RULESETS` Doppler secret). Add permission: **Zone > Zone WAF > Edit** on zone `soleur.ai`. Per the 2026-03-21 learning, **editing permissions on an existing CF API token does NOT rotate the token value** — Doppler secret remains valid.
- [ ] **Playwright flakiness warning** — the CF dashboard "Add permission" form uses React Select comboboxes that frequently fail standard `browser_click` with "element outside of viewport". Before trying to click, read `knowledge-base/project/learnings/integration-issues/2026-04-10-cloudflare-dashboard-react-select-playwright-workaround.md` and apply the `pressSequentially` + JS-dispatch `mouseDown` + keyboard-navigation pattern documented there. Do NOT fight the click; use the workaround from the start.

- [x] If a narrower, separated scope is preferred (follow `cq-cloudflare-provider-alias-for-narrow-scope`), create a **new** Doppler secret `CF_API_TOKEN_ZONE_FIREWALL` in config `prd_terraform` and add a third `provider "cloudflare" { alias = "zone_firewall" }` in `main.tf` backed by it. Decision during implementation, default: **extend the existing `rulesets` token scope** (one fewer Doppler secret, one fewer provider alias, same blast radius since only one consumer will use the new permission). — **Chose default (extend existing).**

**Decision gate:** Before writing `bot-allowlist.tf`, pick one of the two provider options and record the decision in this plan file with a timestamp.

**Decision recorded 2026-04-21:** Extend existing `cloudflare.rulesets` provider alias (Path A). Verified via live API probe: `CF_API_TOKEN_RULESETS` returns `{"success": false, "errors": [{"message": "request is not authorized"}]}` when reading `http_request_firewall_custom/entrypoint`; `CF_API_TOKEN` returns 10000 Authentication error. Scope expansion required on the existing `rulesets` token (add `Zone WAF:Edit` on zone `soleur.ai`). Token value does not rotate on permission edit (per `2026-03-21-cloudflare-api-token-permission-editing.md`). Rationale: mental model "this alias manages cloudflare_ruleset resources" stays consistent; both consumers (`cache.tf`, `bot-allowlist.tf`) are ruleset resources; one fewer Doppler secret, one fewer provider alias.

### Phase 2: Write the allowlist ruleset (new file: `apps/web-platform/infra/bot-allowlist.tf`)

Create a single new Terraform file that adds one zone-scoped `cloudflare_ruleset` in phase `http_request_firewall_custom` with one `skip` rule.

**Design rationale for a separate file:**

- Keeps the bot-allowlist concern cohesive in one file (easy `grep` for future maintainers).
- Mirrors the existing pattern of `cache.tf` (one cloudflare_ruleset per concern per file).
- Simplifies future extensions (adding new AI UAs) without conflating with cache rules.

**Resource sketch (Cloudflare provider v4 block syntax to match repo convention):**

```hcl
# Allowlist documented AI crawler user-agents at Cloudflare's edge.
#
# Why: Cloudflare's Browser Integrity Check (BIC) and Security Level / IP
# reputation were blocking AI crawlers (GPTBot, ClaudeBot, PerplexityBot, etc.)
# with HTTP 403 on soleur.ai/*, making every AEO investment (FAQPage schema,
# self-contained FAQ answers) invisible to AI answer engines. See the
# 2026-04-19 AEO audit §P0-1 (knowledge-base/marketing/audits/soleur-ai/) and
# issue #2662.
#
# Scope: the skip rule affects ONLY requests whose user-agent matches one of
# the documented AI crawler tokens. All other traffic retains the full bot /
# BIC / security_level posture.
#
# Product/phase skip list (literal values verified against cloudflare-go
# v0.115.0 `RulesetActionParameterProductValues()` and `RulesetPhaseValues()`,
# the enums the v4 Terraform provider validates against — casing matters):
# - bic             Browser Integrity Check (the primary blocker — heuristic
#                   refuses AI-crawler-style UAs)
# - securityLevel   IP-reputation based challenge/block (AI crawler IPs
#                   occasionally appear on Project Honeypot lists); camelCase
#                   is intentional per CF's enum
# - uablock         Any future User-Agent Blocking rules that might
#                   inadvertently match an AI UA (lowercase per enum)
# - hot             Hotlink Protection (defense-in-depth; does not currently
#                   trigger but harmless to skip for AI fetches)
# - http_ratelimit  Don't apply per-IP rate limits to AI crawlers as a group
# - http_request_firewall_managed  Managed WAF ruleset phase (currently
#                                  waf=off but future-proof — if we flip
#                                  waf=on later the allowlist stays intact
#                                  without a follow-up)
#
# Two things are NOT in this list:
#
# 1. Bot Fight Mode (BFM). BFM cannot be skipped via WAF custom rules per
#    Cloudflare docs. BFM is not currently identified as the blocker on this
#    zone. If BFM is enabled later and causes 403s, the remediation is to
#    disable BFM zone-wide, not to extend this rule.
#
# 2. Super Bot Fight Mode (SBFM) phase `http_request_sbfm`. SBFM requires
#    Pro+ plan (this zone is Free). The phase literal is also NOT in the
#    v4 Terraform provider's RulesetPhaseValues() enum — adding it would
#    fail `terraform validate`. The public CF docs list `http_request_sbfm`
#    as a skip phase, but the v4 provider hasn't wired it. Revisit on
#    provider-v5 upgrade (and on Pro-plan upgrade).

resource "cloudflare_ruleset" "allowlist_ai_crawlers" {
  provider    = cloudflare.rulesets # or .zone_firewall per Phase 1 decision
  zone_id     = var.cf_zone_id
  name        = "Allowlist documented AI crawler user-agents"
  description = "Skip legacy security products + bot/ratelimit/managed-WAF phases for documented AI crawler UAs (GPTBot, ClaudeBot, PerplexityBot, etc.). See issue #2662 and the 2026-04-19 AEO audit."
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "skip"
    description = "Allowlist AI crawler UAs (GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, anthropic-ai, PerplexityBot, Perplexity-User, CCBot, Google-Extended, Applebot-Extended, Amazonbot, Bytespider, Meta-ExternalAgent, cohere-ai, Diffbot, DuckAssistBot)"
    enabled     = true

    # Expression: match the User-Agent against documented AI crawler tokens.
    # Using lower(http.user_agent) contains "<lowercase-token>" for
    # case-insensitive matching without per-variant enumeration. The token
    # list below is the canonical set from the respective vendor docs as of
    # 2026-04-21 (see Research Insights for sources).
    expression = join(" or ", [
      "(lower(http.user_agent) contains \"gptbot\")",            # OpenAI training
      "(lower(http.user_agent) contains \"oai-searchbot\")",     # OpenAI ChatGPT search
      "(lower(http.user_agent) contains \"chatgpt-user\")",      # OpenAI on-demand fetch
      "(lower(http.user_agent) contains \"claudebot\")",         # Anthropic training
      "(lower(http.user_agent) contains \"anthropic-ai\")",      # Anthropic legacy
      "(lower(http.user_agent) contains \"claude-web\")",        # Anthropic on-demand fetch
      "(lower(http.user_agent) contains \"perplexitybot\")",     # Perplexity training
      "(lower(http.user_agent) contains \"perplexity-user\")",   # Perplexity on-demand fetch
      "(lower(http.user_agent) contains \"ccbot\")",             # Common Crawl (feeds LLM datasets)
      "(lower(http.user_agent) contains \"google-extended\")",   # Google Bard/Gemini opt-in
      "(lower(http.user_agent) contains \"googleother\")",       # Google generic research/AI
      "(lower(http.user_agent) contains \"applebot-extended\")", # Apple Intelligence opt-in
      "(lower(http.user_agent) contains \"amazonbot\")",         # Alexa/Amazon AI
      "(lower(http.user_agent) contains \"bytespider\")",        # ByteDance / Doubao
      "(lower(http.user_agent) contains \"meta-externalagent\")",# Meta Llama training
      "(lower(http.user_agent) contains \"meta-externalfetcher\")", # Meta on-demand fetch
      "(lower(http.user_agent) contains \"cohere-ai\")",         # Cohere
      "(lower(http.user_agent) contains \"diffbot\")",           # Diffbot
      "(lower(http.user_agent) contains \"duckassistbot\")",     # DuckDuckGo AI
      "(lower(http.user_agent) contains \"youbot\")",            # You.com AI
    ])

    action_parameters {
      # Skip all of the following phases of the ruleset engine.
      #
      # Phase enum values are validated against cloudflare-go
      # RulesetPhaseValues() via the v4 Terraform provider. Verified exact
      # literals from source (cloudflare-go v0.115.0, rulesets.go):
      #   - "http_ratelimit"                (legacy rate-limiting phase)
      #   - "http_request_firewall_managed" (CF Managed WAF Ruleset phase)
      #
      # "http_request_sbfm" is NOT in the v4 provider's phase enum and would
      # fail `terraform validate`. When the repo upgrades to provider v5,
      # revisit: SBFM exists only on Pro+ plans and would still no-op on
      # Free, but the phase literal may become valid to list.
      phases = [
        "http_ratelimit",
        "http_request_firewall_managed",
      ]

      # Skip all of the following legacy security products.
      #
      # Product enum values are validated against cloudflare-go
      # RulesetActionParameterProductValues(). Verified exact literals from
      # source (casing is quirky — "securityLevel" is camelCase while the
      # others are lowercase; this is intentional per CF's internal naming):
      #   - "bic"            Browser Integrity Check (PRIMARY blocker)
      #   - "securityLevel"  IP-reputation challenge/block
      #   - "uablock"        User Agent Blocking rules
      #   - "hot"            Hotlink Protection
      products = [
        "bic",
        "securityLevel",
        "uablock",
        "hot",
      ]
    }
  }
}
```

**Why `contains` and not `matches regex`:** `contains` is simpler, deterministic, and every UA listed is a distinct enough token that false-positive matches are negligible (e.g., no legitimate browser UA contains "gptbot"). Case-folding via `lower()` handles UA casing variations.

**What's NOT included (and why):**

- No `cf.verified_bot` expression branch. CF's verified-bot detection on Free plan is informational only (BFM excludes verified bots by default but we can't rely on it on Free without Super Bot Fight Mode). Explicit UA match is more reliable and auditable.
- No IP-CIDR allowlist. AI crawler IP ranges change; UAs are the vendor-documented identifier. If a vendor later publishes a signed-bot program (Web Bot Auth, RFC 9421), revisit with `cf.bot_management.verified_bot` once we upgrade to Pro.

**Mandatory Phase 2 exit step — `terraform validate` preflight:**

Per institutional learning `2026-04-10-context7-terraform-provider-version-mismatch.md`, every new Cloudflare resource must pass `terraform validate` immediately after drafting — before commit, before plan, before review. Context7 and generic docs routinely return enum casings or attributes that don't match the pinned v4.52.7 provider. This step is the catch-net.

- [x] From `apps/web-platform/infra/`, run:

    ```bash
    cd apps/web-platform/infra
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform validate
    ```

- [x] Expected: `Success! The configuration is valid.` — **Result 2026-04-21: passed** (no enum or syntax drift).
- [x] If validate fails with `expected ... to be one of [...] but got ...` on `products` or `phases`, the enum casing is wrong — cross-reference against `rulesets.go` in `cloudflare-go v0.115.0` (the dependency version shown in `.terraform.lock.hcl` for `cloudflare/cloudflare@4.52.7`). — N/A.
- [x] If validate fails with an unknown-block error on `rules {}` or `action_parameters {}`, the syntax may have been written as v5 list-attribute (`rules = [...]`). v4 uses nested blocks. — N/A.

### Phase 3: Extend Phase 1 permission findings into Terraform (if a new provider alias was chosen)

Only applies if Phase 1 chose the "new provider alias" option.

- [ ] Add `variable "cf_api_token_zone_firewall"` to `variables.tf`.
- [ ] Add `provider "cloudflare" { alias = "zone_firewall" ... }` to `main.tf`.
- [ ] Add the new secret to Doppler config `prd_terraform` (the `doppler run --name-transformer tf-var` wraps this into `TF_VAR_cf_api_token_zone_firewall` automatically).
- [ ] Reference `provider = cloudflare.zone_firewall` on the new ruleset resource.

### Phase 4: Terraform plan + verification

- [x] Run `cd apps/web-platform/infra && terraform init -upgrade` (to pick up the new resource). — **Done 2026-04-21.**
- [x] Run the repo-standard doppler-wrapped plan (per `cq-when-running-terraform-commands-locally`):

    ```bash
    cd apps/web-platform/infra
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform plan -out=tfplan
    ```

- [x] Review plan output: expect `1 to add` (the new `cloudflare_ruleset.allowlist_ai_crawlers`), `0 to change`, `0 to destroy`. Any `change`/`destroy` on existing resources is a red flag — investigate before apply. — **Result 2026-04-21: `1 to add, 0 to change, 0 to destroy`.**
- [x] Sanity-check the planned rule: `terraform show tfplan | grep -A 30 "allowlist_ai_crawlers"`. — **Done; resource sketch matches expectations.**

### Phase 5: Apply (operator, explicit per-command ack)

Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`, prod-scoped `terraform apply` requires explicit per-command go-ahead from the operator. This is a **post-merge** step.

- [ ] Operator runs (after merge, from the infra directory):

    ```bash
    cd apps/web-platform/infra
    doppler run --project soleur --config prd_terraform -- \
      doppler run --token "$(doppler configure get token --plain)" \
        --project soleur --config prd_terraform --name-transformer tf-var -- \
      terraform apply tfplan
    ```

- [ ] Do **NOT** pass `-auto-approve`. The native prompt must surface.

### Phase 6: Post-apply verification

- [ ] Verify the rule is live via CF API:

    ```bash
    CF_TOKEN=$(doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain)
    ZONE=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
    curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE}/rulesets/phases/http_request_firewall_custom/entrypoint" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      | jq '.result.rules[] | {id, action, description, enabled, expression: (.expression | .[0:80])}'
    ```

    Expected: one rule with `action: "skip"`, `enabled: true`, description mentions "AI crawler UAs".

- [ ] Verify end-to-end unblock from the command line (zero ambiguity):

    ```bash
    for ua in "GPTBot/1.1" "OAI-SearchBot/1.0" "ChatGPT-User/1.0" \
              "ClaudeBot/1.0" "PerplexityBot/1.0" "CCBot/2.0" \
              "Google-Extended" "Applebot-Extended" "Amazonbot/0.1" \
              "Bytespider" "meta-externalagent/1.1"; do
      code=$(curl -s -o /dev/null -w "%{http_code}" -A "${ua}" https://soleur.ai/)
      echo "${ua}: ${code}"
    done
    # Expected: every line ends in 200 (or 301 if the UA triggers the
    # apex->www redirect that browsers also hit)
    ```

- [ ] Verify browser traffic still works (regression guard):

    ```bash
    curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0" https://soleur.ai/
    # Expected: 301 (redirect to www.soleur.ai) — unchanged from pre-fix behavior
    ```

- [ ] Verify a spammy bot UA is still blocked (sanity check that we did not weaken posture):

    ```bash
    curl -s -o /dev/null -w "%{http_code}\n" -A "curl/7.68.0" https://soleur.ai/
    curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)" https://soleur.ai/
    # Expected: 403 or 200 (depending on whether those specific UAs were ever
    # blocked). The important assertion: the behavior for non-AI UAs is
    # unchanged from pre-fix.
    ```

- [ ] Open CF dashboard **Security → Events** and confirm no spike in blocked-request count on non-AI UAs. Filter to `soleur.ai` zone, last 1h, action != "skip".

- [ ] Close issue #2662 with a comment containing the verification-table output from the curl loop above.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/infra/bot-allowlist.tf` exists and contains exactly one `cloudflare_ruleset` resource named `allowlist_ai_crawlers`.
- [x] The resource uses `phase = "http_request_firewall_custom"` and `kind = "zone"`.
- [x] The `skip` rule's `action_parameters.phases` contains at minimum `["http_ratelimit", "http_request_firewall_managed"]` (NOT `http_request_sbfm` — not in v4 enum).
- [x] The `skip` rule's `action_parameters.products` contains at minimum `["bic", "securityLevel", "uablock", "hot"]` (exact case: `securityLevel` camelCase, others lowercase per cloudflare-go enum).
- [x] `terraform validate` passes in `apps/web-platform/infra/` after the resource is written and before commit. This catches casing / enum drift from Context7.
- [x] The rule's `expression` uses `lower(http.user_agent) contains` matches for at minimum the core five UAs named in the issue: **GPTBot, ClaudeBot, PerplexityBot, CCBot, Google-Extended** (additional UAs from the wider list are expected but not strictly required by the issue).
- [x] **No existing resource is modified destructively** in `terraform plan` (allow additions only; any change to `cloudflare_zone_settings_override`, `cloudflare_ruleset.cache_shared_binaries`, or DNS records is a red flag).
- [x] No new Doppler secret is created **unless** Phase 1 explicitly chose the "new provider alias" path. If so, the secret name matches the `cq-doppler-service-token-config-scope-mismatch` convention. — **No new secret (default path taken).**
- [ ] PR body contains `Closes #2662`.
- [ ] PR body contains a one-line description of the fix under `## Changelog` and a `semver:patch` label.
- [ ] Plan/deepen-plan review (DHH, Kieran, code-simplicity) runs and findings are applied inline.

### Post-merge (operator)

- [ ] Operator runs `terraform apply` (explicit per-command ack; no `-auto-approve`) and it succeeds with `1 resource added, 0 changed, 0 destroyed`.
- [ ] Post-apply `curl -A "GPTBot/1.1" https://soleur.ai/` returns HTTP 200 (not 403).
- [ ] Post-apply `curl -A "ClaudeBot/1.0" https://soleur.ai/` returns HTTP 200.
- [ ] Post-apply `curl -A "PerplexityBot/1.0" https://soleur.ai/` returns HTTP 200.
- [ ] CF Security Events shows no regression in blocked-request counts for non-AI UAs in the hour after apply.
- [ ] Issue #2662 closed with verification output.
- [ ] Terraform state lists the new resource (`terraform state list | grep allowlist_ai_crawlers`) and there are no orphaned resources.

## Test Scenarios

This is an infrastructure-only change (single Terraform resource, no application code), so **the `cq-write-failing-tests-before` TDD gate is exempt** (plan explicitly falls under "infrastructure-only tasks — config, CI, scaffolding" per rule text). Verification is via Phase 6 curl assertions against the live edge. Optional belt-and-suspenders: a bats-free shell-script smoke harness committed under `apps/web-platform/infra/bot-allowlist.test.sh` that reproduces the Phase 6 curl loop is **scope-out** — it duplicates what the verification step does manually and adds a CI-scheduling burden not justified for a one-rule change.

## Risks

1. **Provider token scope gap** — the existing `CF_API_TOKEN_RULESETS` may not have `Zone WAF:Edit` and Phase 1 may need a Playwright-automated permission expansion. **Mitigation:** Phase 1 explicitly verifies scope before writing the resource; runbook exists (`2026-03-21-cloudflare-api-token-permission-editing.md`).

2. **Terraform partial-apply orphan state (`cq-terraform-failed-apply-orphaned-state`)** — if `terraform apply` errors mid-create, the resource may land in tfstate without existing in Cloudflare. **Mitigation:** after any failed apply, run `terraform state list | grep allowlist_ai_crawlers`; if present but CF has no such rule, `terraform state rm cloudflare_ruleset.allowlist_ai_crawlers` before re-planning.

3. **Drift on `@` normalization / phase defaults** — not applicable here (we use `kind = "zone"` and explicit `phase`, not DNS `name = "@"`).

4. **Context7 / provider-version enum drift** — Context7 returned product-enum values in camelCase (`uaBlock`, `rateLimit`, `zoneLockdown`) and included `http_request_sbfm` in the skip `phases` enum. Direct inspection of cloudflare-go v0.115.0 source (`rulesets.go`) — the library the v4.52.7 provider depends on — showed the actual enum uses mixed casing (`bic`, `hot`, `ratelimit`, `securityLevel`, `uablock`, `waf`, `zonelockdown`) and does NOT include `http_request_sbfm`. Applying Context7's values verbatim would fail `terraform validate` with "expected to be one of ... but got ...". **Mitigation:** the plan now uses the source-verified literals; Phase 2 adds a mandatory `terraform validate` preflight; institutional learning `2026-04-10-context7-terraform-provider-version-mismatch.md` is explicitly applied.

5. **Free-plan compatibility of skipped products** — the plan assumes every `products` value is skippable on Free. Verified against Cloudflare docs `waf/custom-rules/skip/options/`: `bic`, `hot`, `ratelimit`, `securityLevel`, `uablock`, `waf`, `zonelockdown` are all listed as valid skip targets across plans (the doc does not plan-gate them). BFM remains non-skippable on all plans — an orthogonal constraint, not a Free-plan limitation.

6. **Dashboard "Block AI bots" managed toggle (operator-flippable out of band)** — Cloudflare offers a one-click managed rule in the dashboard that blocks known AI crawlers. This zone does not currently have it enabled (settings-endpoint probe on 2026-04-21 showed no matching setting). If an operator later enables it via dashboard, it runs inside `http_request_firewall_managed` phase, which this rule already skips — so the allowlist should survive that toggle without a follow-up Terraform edit. **Caveat:** the specific managed ruleset ID for "Block AI bots" may live in a different managed ruleset that is not covered by the `http_request_firewall_managed` phase skip; if that happens, the rule needs the managed ruleset ID added to `action_parameters.rulesets`. Re-verify with a live curl after any managed-rule dashboard change.

5. **Vendor UA token drift** — OpenAI/Anthropic/Perplexity may rename or rotate their UA tokens. **Mitigation:** the list is commented inline with vendor source URLs; when a vendor publishes a new token, edit the file, re-plan, apply. No external drift-detection is needed — the AEO audit will re-surface a block if the list goes stale.

7. **Bot Fight Mode enablement later (out-of-band dashboard change)** — if an operator later enables BFM via dashboard, this allowlist will NOT bypass BFM (docs: BFM is not skippable via custom rules). **Mitigation:** document in the plan and in a comment at the top of `bot-allowlist.tf` that BFM is intentionally out-of-scope. If BFM gets enabled and causes 403s, the fix is to disable BFM zone-wide, which is itself a policy decision.

8. **Ruleset precedence** — Cloudflare's Ruleset Engine executes `http_request_firewall_custom` BEFORE `http_request_firewall_managed` and other phases listed in `phases` skip. The skip takes effect because custom-phase rules run first; they can skip downstream phases but cannot skip the current phase (that's `ruleset = "current"` semantics, not `phases`). **Mitigation:** the fix does not depend on skipping custom-phase rules — BIC and `securityLevel` are products (not rulesets), and the phases listed are all downstream of `http_request_firewall_custom` per the docs enum order. Verified against Cloudflare docs.

## Non-Goals

- **Do NOT disable Bot Fight Mode, BIC, security_level, or any existing zone posture.** Scope is allowlist-only.
- **Do NOT add a global `security_level = "off"` override.** That would weaken protection for all traffic, not just AI.
- **Do NOT modify `robots.txt`.** The current `Allow: /` is correct and aligned with AEO guidance.
- **Do NOT widen `CF_API_TOKEN_RULESETS` to account-level permissions.** Zone-level `Zone WAF:Edit` is sufficient.
- **Do NOT address P1/P2/P3 recommendations from the AEO audit in this PR.** Those are separate issues (#2662 is ONLY the P0).
- **Do NOT implement a bats/vitest/shell-test harness.** Manual curl verification in Phase 6 is sufficient for a single-rule infra change.
- **Do NOT add a Web Bot Auth / RFC 9421 verified-bot branch.** CF's verified-bot handling on Free plan is informational only; revisit on plan upgrade.

## Alternative Approaches Considered

| Approach | Rationale for rejecting |
|---|---|
| Disable BIC zone-wide (`browser_check=off`) | Weakens bot protection for ALL traffic, not just AI crawlers. Contradicts issue directive "Do NOT weaken bot fight globally". |
| Drop `security_level` to `essentially_off` | Same problem — global weakening. Would let IP-reputation-flagged threats through for all traffic. |
| Move soleur.ai apex off Cloudflare to direct GitHub Pages | Loses HSTS preload management, DDoS protection, and the cache-rule infra we already have. Massive scope expansion. |
| Use a Page Rule instead of a Ruleset | Page Rules are legacy and cannot skip BFM (per docs, same limitation as custom rules). The Ruleset Engine is the current supported path. Also, Page Rules are not currently Terraform-managed in this repo. |
| IP-CIDR allowlist for documented AI crawler IPs | AI crawler IPs change frequently and vendors don't always publish stable ranges. UA-based allowlist is the vendor-documented identifier. Revisit post-Pro-upgrade when `cf.bot_management.verified_bot` becomes authoritative. |
| Use `ruleset = "current"` instead of `phases = [...]` | `ruleset = "current"` skips the rest of `http_request_firewall_custom` itself, which is useless here — we have no other custom rules, so nothing to skip in the current phase. We need to skip DOWNSTREAM phases and legacy products. |

## Domain Review

**Domains relevant:** Engineering/Infrastructure (CTO), Marketing (CMO)

### Engineering / Infrastructure (CTO)

**Status:** reviewed (inline, no agent spawn — this is a narrow infra fix with established repo patterns and explicit Cloudflare doc citations)

**Assessment:** The fix follows the established `apps/web-platform/infra/` pattern: one concern per `.tf` file, reuse existing narrow-scope CF provider aliases, doppler-wrapped terraform plan/apply, explicit per-command ack for prod writes. It introduces no new dependencies. The only architectural question was "should this be a new provider alias with its own narrow token, or an extended scope on the existing rulesets token?" — resolved in Phase 1 with a decision gate (default: extend existing token per `cq-cloudflare-provider-alias-for-narrow-scope` only when a genuinely independent concern exists; here the rulesets token has exactly this role).

### Marketing (CMO)

**Status:** reviewed (issue is marketing-domain-labeled; the AEO audit is a CMO-generated artifact)

**Assessment:** This fix is the P0 unblock for the 2026-04-19 AEO audit. The entire AEO strategy (FAQPage schema, self-contained answers, citation-ready prose) is downstream-blocked until AI crawlers can fetch `soleur.ai/*`. Ship this before any of the P1/P2 recommendations are re-opened — those items are invisible without it. No content changes are in scope for this PR.

**Brainstorm-recommended specialists:** none (no brainstorm for this feature; issue body is the spec, cross-referenced to the AEO audit).

### Product/UX Gate

**Tier:** none (infrastructure-only change; no new user-facing page or component file; mechanical escalation does not trigger because no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is touched).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned 27 issues; none name any of `apps/web-platform/infra/cloudflare-settings.tf`, `cache.tf`, `main.tf`, `variables.tf`, `dns.tf`, `firewall.tf`. The new `bot-allowlist.tf` path has no open scope-outs.

## Research Insights

### Cloudflare zone state (probed 2026-04-21)

Raw `/settings` endpoint output for zone `soleur.ai` (5af02a2f394e9ba6e0ea23c381a26b67):

- `plan.legacy_id = "free"` (Free Website)
- `browser_check = on` ← **primary blocker; skippable via `bic`**
- `security_level = medium` ← **secondary blocker; skippable via `securityLevel`**
- `waf = off` (managed WAF is OFF — the issue's "Cloudflare WAF ruleset" phrasing in the fix description needs clarification; see Research Reconciliation)
- `hotlink_protection = off`
- `challenge_ttl = 1800`
- `bot_fight_mode`: undefined at `/settings` endpoint (zone-level BFM setting not surfaced; may be managed via a different endpoint)

Existing rulesets on the zone:

- `http_request_sanitize` — Cloudflare Normalization Ruleset (managed)
- `http_request_firewall_managed` — Cloudflare Managed Free Ruleset (managed, but `waf=off` means it's not enforcing)
- `ddos_l7` — DDoS L7 ruleset (managed)
- `http_config_settings` — default
- `http_request_cache_settings` — `Edge-cache /api/shared/* per origin Cache-Control` (our existing `cache.tf`)

**No existing `http_request_firewall_custom` entrypoint.** Terraform will create it on first apply.

### Verification: 403 pre-fix

```
$ curl -sI -A "GPTBot/1.0 (+https://openai.com/gptbot)" https://soleur.ai/
HTTP/2 403
server: cloudflare
cf-ray: 9efd546d1bcce8ce-CDG
content-length: 25
(body: "Your request was blocked.")

$ curl -sI -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" https://soleur.ai/
HTTP/2 301
server: cloudflare
location: https://www.soleur.ai/
```

Per-UA HTTP code matrix (pre-fix):

- GPTBot: 403
- ClaudeBot: 403
- PerplexityBot: 403
- Browser-UA: 301 (apex → www redirect, expected)

### Cloudflare skip-action enums — two sources, one mismatch

**Source A: Cloudflare public docs (`developers.cloudflare.com/waf/custom-rules/skip/options/`), 2026-04-21.** Lists these `phases`: `ddos_l4`, `ddos_l7`, `http_config_settings`, `http_custom_errors`, `http_log_custom_fields`, `http_ratelimit`, `http_request_cache_settings`, `http_request_dynamic_redirect`, `http_request_firewall_custom`, `http_request_firewall_managed`, `http_request_late_transform`, `http_request_origin`, `http_request_redirect`, `http_request_sanitize`, `http_request_sbfm`, `http_request_transform`, `http_response_cache_settings`, `http_response_compression`, `http_response_firewall_managed`, `http_response_headers_transform`, `magic_transit`, `magic_transit_ids_managed`, `magic_transit_managed`, `magic_transit_ratelimit`. Lists these `products`: `bic`, `hot`, `rateLimit`, `securityLevel`, `uaBlock`, `waf`, `zoneLockdown`.

**Source B: cloudflare-go v0.115.0 `rulesets.go` (the library consumed by Terraform provider v4.52.7), verified live on 2026-04-21.** The actual enum slices differ from Source A:

```
# products (RulesetActionParameterProductValues):
"bic", "hot", "ratelimit", "securityLevel", "uablock", "waf", "zonelockdown"
# Note: "ratelimit" (not "rateLimit"), "uablock" (not "uaBlock"),
#       "zonelockdown" (not "zoneLockdown"); "securityLevel" is camelCase.

# phases (RulesetPhaseValues):
"ddos_l4", "ddos_l7", "http_config_settings", "http_custom_errors",
"http_log_custom_fields", "http_ratelimit", "http_request_cache_settings",
"http_request_dynamic_redirect", "http_request_firewall_custom",
"http_request_firewall_managed", "http_request_late_transform",
"http_request_origin", "http_request_redirect", "http_request_sanitize",
"http_request_transform", "http_response_compression",
"http_response_firewall_managed", "http_response_headers_transform",
"magic_transit"
# Note: NO "http_request_sbfm", NO "http_response_cache_settings",
#       NO "magic_transit_*" variants.
```

**Resolution:** use Source B (the enum actually validated by the installed provider). Source A is accurate for the CF API directly and for newer provider versions; the installed provider pins an older cloudflare-go library that hasn't caught up. This is the specific failure class documented in `2026-04-10-context7-terraform-provider-version-mismatch.md` — generalized to: ANY CF enum retrieved from docs must be cross-checked against `.terraform.lock.hcl` and the pinned library's source before landing in HCL.

**`ruleset = "current"`** — valid singular value that means "skip the remainder of the current ruleset". Incompatible with `rulesets = [...]` and `phases = [...]`. Not used here.

**BFM is NOT skippable.** Cloudflare docs: "you cannot bypass or skip Bot Fight Mode using the Skip action in WAF custom rules or using Page Rules." BFM runs outside the Ruleset Engine. This is the single most important constraint documented in this plan.

### Terraform provider syntax: v4 blocks vs v5 list-attributes

The pinned version is `cloudflare/cloudflare ~> 4.0` (lock file reports `4.52.7`). The v4 schema defines `cloudflare_ruleset.rules` as a `ListNestedBlock` — HCL uses **block syntax**:

```hcl
rules {
  action     = "..."
  expression = "..."
  action_parameters { phases = [...] products = [...] }
}
```

v5 changes this to a list-attribute (`rules = [ { ... } ]`). Context7 MCP's v5 docs leaked into the first-pass plan draft. Precedent in this repo (`apps/web-platform/infra/cache.tf` `cloudflare_ruleset.cache_shared_binaries`) uses v4 block syntax — the final resource MUST match.

### AI crawler user-agent canonical tokens (sources)

| UA token | Vendor | Purpose | Source |
|---|---|---|---|
| `GPTBot` (full: `GPTBot/1.1`) | OpenAI | Training data | <https://platform.openai.com/docs/bots> |
| `OAI-SearchBot` (1.0) | OpenAI | ChatGPT search index | <https://platform.openai.com/docs/bots> |
| `ChatGPT-User` (1.0) | OpenAI | User-requested on-demand fetch | <https://platform.openai.com/docs/bots> |
| `ClaudeBot` (1.0) | Anthropic | Training data | <https://docs.anthropic.com/en/docs/agents-and-tools/web-crawling> |
| `anthropic-ai` | Anthropic | Legacy crawler | Anthropic docs |
| `claude-web` | Anthropic | User-requested fetch | Anthropic docs |
| `PerplexityBot` (1.0) | Perplexity | Search index | <https://docs.perplexity.ai/guides/bots> |
| `Perplexity-User` | Perplexity | User-requested fetch | Perplexity docs |
| `CCBot` | Common Crawl | Public archive (feeds LLM training) | <https://commoncrawl.org/ccbot> |
| `Google-Extended` | Google | Bard/Gemini training opt-in | <https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers> |
| `GoogleOther` | Google | Research/AI generic | Google docs |
| `Applebot-Extended` | Apple | Apple Intelligence training opt-in | <https://support.apple.com/en-us/119829> |
| `Amazonbot` | Amazon | Alexa / Amazon AI | <https://developer.amazon.com/amazonbot> |
| `Bytespider` | ByteDance | Doubao/TikTok AI | ByteDance docs |
| `Meta-ExternalAgent` | Meta | Llama training | <https://developers.facebook.com/docs/sharing/webmasters/crawler> |
| `Meta-ExternalFetcher` | Meta | On-demand fetch | Meta docs |
| `cohere-ai` | Cohere | Cohere models | Cohere docs |
| `Diffbot` | Diffbot | Knowledge graph crawler | <https://docs.diffbot.com/> |
| `DuckAssistBot` | DuckDuckGo | DuckDuckGo AI assistant | DuckDuckGo docs |
| `YouBot` | You.com | You.com search/AI | You.com docs |

### Institutional learnings applied

- `2026-03-21-cloudflare-api-token-permission-editing.md` — Playwright MCP automation pattern for expanding an existing CF API token's scope without rotating the secret (Phase 1 runbook).
- `2026-04-10-cloudflare-dashboard-react-select-playwright-workaround.md` — CF dashboard's React Select combobox workaround (`pressSequentially` + JS-dispatch `mouseDown` + keyboard-nav). Applied as a Phase 1 warning so the operator doesn't waste time fighting standard click failures.
- `2026-04-10-context7-terraform-provider-version-mismatch.md` — **LOAD-BEARING for this plan.** Directly predicted the `uaBlock`/`uablock` and `http_request_sbfm`-not-in-v4 mismatches. Applied via: (a) the mandatory `terraform validate` preflight added to Phase 2, (b) direct source verification against `cloudflare-go v0.115.0 rulesets.go` rather than trusting Context7 output.
- `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` — v4 vs v5 attribute naming table. Applied: HCL uses block syntax (`rules { ... }`), not v5 list-attribute syntax. Explicit verification in the plan's "Terraform provider syntax: v4 blocks vs v5 list-attributes" subsection.
- `2026-04-18-cloudflare-default-bypasses-dynamic-paths.md` — Established precedent that CF defaults ≠ our assumption; verify with doc citation. Applied: every vendor-behavior claim in this plan (phases enum, products enum, BFM skippability, Free-plan compatibility) cites a specific docs URL or source file.
- `cq-cloudflare-provider-alias-for-narrow-scope` — Narrow-token-per-permission pattern. Applied in Phase 1 decision gate.
- `cq-terraform-failed-apply-orphaned-state` — Recovery runbook if Phase 5 apply errors. Applied in Risks.
- `hr-all-infrastructure-provisioning-servers` — All infra goes through Terraform, never dashboard clicks. Applied: even the permission-expansion step (Phase 1) uses dashboard Playwright ONLY because CF does not support API-based token self-editing — verified via the 2026-03-21 learning.
- `hr-menu-option-ack-not-prod-write-auth` — No `-auto-approve` on prod terraform. Applied in Phase 5.

## References

- Issue: <https://github.com/jikig-ai/soleur/issues/2662>
- Source audit: `knowledge-base/marketing/audits/soleur-ai/2026-04-19-aeo-audit.md` §3 P0-1
- Repo Cloudflare precedent: `apps/web-platform/infra/cache.tf`, `apps/web-platform/infra/cloudflare-settings.tf`, `apps/web-platform/infra/main.tf` (provider aliases)
- Cloudflare docs:
  - Skip action options: <https://developers.cloudflare.com/waf/custom-rules/skip/options/>
  - Bot Fight Mode not skippable: <https://developers.cloudflare.com/waf/custom-rules/skip/>
  - Verified bots: <https://developers.cloudflare.com/bots/concepts/bot/verified-bots/>
- Terraform provider: `/cloudflare/terraform-provider-cloudflare` (Context7), v4.x docs for `cloudflare_ruleset`.
