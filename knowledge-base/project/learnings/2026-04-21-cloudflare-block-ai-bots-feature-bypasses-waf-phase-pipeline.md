---
category: integration-issues
tags: [cloudflare, bot-management, ruleset, waf, terraform, ai-crawlers, aeo]
date: 2026-04-21
module: apps/web-platform/infra
problem_type: integration-issue
---

# Learning: Cloudflare "Block AI bots" feature bypasses the WAF phase pipeline; terraform plan is structurally insufficient for cloudflare_ruleset PRs

## Problem

Post-merge apply of PR #2740 (AI crawler WAF allowlist, `cloudflare_ruleset` in `http_request_firewall_custom`) required **four** distinct code fixes before the functional goal of issue #2662 (20 documented AI crawler UAs return 200/301 instead of 403 on `soleur.ai`) was achieved. All four failures were invisible to `terraform validate` and `terraform plan` locally and in CI; each surfaced only at `terraform apply` time — or worse, only after apply succeeded.

The highest-impact finding, only visible after the custom ruleset was fully deployed and working as designed: **CF's zone-level "Block AI bots" feature operates outside the WAF phase pipeline**. A `cloudflare_ruleset` `skip` action in `http_request_firewall_custom` or `http_request_firewall_managed` **cannot bypass it**. The feature lives on the `/zones/{id}/bot_management` endpoint as `ai_bots_protection: "block"` and must be set via a separate `cloudflare_bot_management` resource.

## Environment

- Module: `apps/web-platform/infra`
- CF provider: cloudflare/cloudflare v4.52.7 (pinned)
- CF plan: Free (soleur.ai)
- Date: 2026-04-21

## What terraform plan missed (and how each surfaced)

**1. SDK enum vs API enum drift — `uablock` vs `uaBlock`**

`cloudflare-go` v0.115.0 `RulesetActionParameterProductValues()` enumerates lowercase `"uablock"`. The Terraform provider uses this enum to validate configuration — `terraform validate` and `terraform plan` both pass. The CF API, however, requires camelCase `"uaBlock"` and rejects lowercase at apply time:

```
Error: error creating ruleset Allowlist documented AI crawler user-agents
skip action parameter product 'uablock' is invalid (20119)
```

PR #2740's plan file literally documented "Casing matters" and listed `uablock` — the code inherited CF SDK drift.

**2. Plan-tier entitlement — `matches` regex requires Business/WAF Advanced**

```hcl
expression = "... or (lower(http.user_agent) matches \"(^|[^a-z])ccbot([^a-z]|$)\") or ..."
```

Passes `terraform validate` and `terraform plan`. Rejected at apply on Free plan:

```
Error: not entitled: the use of operator Matches is not allowed,
a Business plan or a WAF Advanced plan is required
```

The `contains` operator is available on all plans. Substring-collision trade-off for `ccbot` is documented inline and tightening back to regex is a trivial follow-up once the zone upgrades.

**3. Provider post-apply inconsistency — CF auto-injects `logging { enabled = true }`**

First `terraform apply` succeeded at the CF API layer (resource created, ID returned, in tfstate). Provider then reported:

```
Error: Provider produced inconsistent result after apply
  .rules[0].logging: block count changed from 0 to 1.
```

Resource was tainted; next `plan` proposed `destroy + create replacement`. Fix: declare `logging { enabled = true }` in the resource block so the provider's pre-apply expectation matches CF's post-apply response. `terraform untaint` + re-apply then converged to a clean plan.

**4. "`waf=off` ⇒ Managed Ruleset is a no-op" was false**

PR #2740's security-sentinel review finding F2 dropped `http_request_firewall_managed` from the skip phases with this reasoning:

> On Free plan with waf=off the Managed Ruleset is a no-op today, and pre-authorizing its skip for UA-asserting-AI traffic would exempt spoofed clients from any future zone-wide CF emergency rule the moment waf flips on.

Post-apply `curl` probe showed 13/20 crawlers still 403 with `server: cloudflare`. The remaining blocker lives in `http_request_firewall_managed`, fired regardless of `waf=off`. Re-added the phase skip. Then 7/20 still passed, 13/20 still 403 — identical — because the actual blocker is even earlier in the pipeline.

**5. (Root cause of #4): "Block AI bots" zone feature outside the WAF phase pipeline**

`/zones/{id}/bot_management` GET:

```json
{
  "enable_js": true,
  "fight_mode": false,
  "ai_bots_protection": "block",
  "crawler_protection": "enabled",
  "is_robots_txt_managed": false,
  ...
}
```

`"ai_bots_protection": "block"` is the Security → Settings → Bot traffic → "Block AI bots" dashboard toggle. Cloudflare implements this as a zone-edge feature that runs before (or in parallel to) the rulesets pipeline; `cloudflare_ruleset` skip actions, regardless of phase or product scope, do not affect it. Flipping to `"disabled"` via `cloudflare_bot_management.soleur_ai` resource unblocked all 20 crawlers immediately.

Key empirical signal: which UAs were 403 vs 301 exactly matched CF's published "AI training crawler" list (GPTBot, ClaudeBot, CCBot, anthropic-ai, PerplexityBot, Amazonbot, Bytespider, cohere-ai, DuckAssistBot, YouBot, OAI-SearchBot, ChatGPT-User, Perplexity-User). UAs not on that list (Google-Extended, Meta-ExternalAgent, Applebot-Extended, Diffbot) passed even with "Block AI bots" on.

## Solution

Split across two resources in `apps/web-platform/infra/`:

- `bot-allowlist.tf` — `cloudflare_ruleset.allowlist_ai_crawlers` in `http_request_firewall_custom`, skipping `bic/hot/securityLevel/uaBlock` products + `http_ratelimit` + `http_request_firewall_managed` phases for the 20 documented AI crawler UAs. Uses `contains`-only match expressions. Declares `logging { enabled = true }`.

- `bot-management.tf` — `cloudflare_bot_management.soleur_ai` with `ai_bots_protection = "disabled"`, `fight_mode = false`, `enable_js = true`. Uses new narrow token `CF_API_TOKEN_BOT_MANAGEMENT` scoped to Bot Management:Edit on `soleur.ai` only. Provider alias `cloudflare.bot_management` in `main.tf`.

Two complementary layers of defense:

1. `bot-management` disables the zone-wide "Block AI bots" feature — necessary because it can't be skipped.
2. `bot-allowlist` retains UA-scoped skip of legacy security products + managed phase for the 20 documented crawlers, so if any **other** CF-managed rule starts blocking UA-asserting-AI traffic in the future, our specific allowlist still fires.

## Why this was expensive (5+ `apply` iterations against prod)

`terraform plan` is structurally insufficient for `cloudflare_ruleset` PRs. The CF provider validates against SDK enums (not API enums), does not probe plan-tier entitlements, and does not exercise the round-trip (apply-then-refresh) that exposes auto-injected blocks. `terraform apply` against a non-prod target (ideally a throwaway Free zone with a long TTL on plan-level security settings) is the only way to catch these pre-merge.

The "Block AI bots" finding was even more expensive because it was shipped-and-merged as "part of the custom ruleset rollout", requiring the functional curl table to be run against prod to detect that the rollout had achieved only a partial unblock. A pre-merge functional gate would have caught it before the issue was closed.

## Prevention

Three rules proposed for AGENTS.md as a result of this session:

- **`cq-cloudflare-ruleset-requires-applied-verification`** — PRs modifying `cloudflare_ruleset` must include either (a) a successful `terraform apply` preview against a non-prod zone, or (b) a pre-merge functional verification of the user-visible outcome the ruleset is meant to achieve (e.g., the `curl`-all-UAs table for a crawler allowlist). `plan` pass is necessary but NOT sufficient. Rationale: four separate apply-time failure modes documented above.
- **`cq-cloudflare-ruleset-skip-action-requires-logging-block`** — every `cloudflare_ruleset` rule with `action = "skip"` must declare `logging { enabled = true }`. CF's managed phases auto-enable logging on skip actions; omitting the block triggers post-apply inconsistency and tainting.
- **`cq-cloudflare-block-ai-bots-not-skippable`** — the "Block AI bots" zone feature (`ai_bots_protection`) operates outside the WAF phase pipeline; `cloudflare_ruleset` skip actions cannot bypass it. Any work targeting AEO/AI-crawler visibility MUST use `cloudflare_bot_management` resource, not a custom ruleset alone.

Proposed workflow rule (to replace the failure mode "merged on plan, fixed over multiple applies"):

- **`wg-infra-functional-verification-as-shipping-gate`** — when a PR creates external resources intended to change observable traffic behavior (unblocking crawlers, changing redirect chains, adding/removing cache edges), a black-box functional probe (curl, dig, etc.) is a pre-merge shipping gate, not a post-merge follow-through. Codified in `/ship` Phase 5.5 detection list.

## Session Errors

- **Route-to-dashboard reflex on a configurable field.** Initial instinct after finding "Block AI bots" in Security settings was to route to the CF dashboard for a click-toggle + file a follow-up to codify. `strings <provider-binary> | grep ai_bots_protection` would have revealed the `cloudflare_bot_management` resource in 2 seconds. Fixed: check provider binary grep BEFORE proposing any dashboard step, per `hr-all-infrastructure-provisioning-servers`.
- **Incorrect assumption in prior review feedback (PR #2740 F2 security-sentinel).** Dropped `http_request_firewall_managed` from skip phases based on "waf=off ⇒ no-op". Reinstated this session after empirical disproof. Root cause was reasoning from `waf` setting alone instead of enumerating active features under Security → Bots and the zone's Managed ruleset rules.

## Related Issues

- Root issue: #2662 (AEO P0-1, AI crawler edge unblock)
- Source PR: #2740 (custom WAF ruleset — shipped with all 4 latent failure modes above)
- Follow-through issue: #2748 (this cleanup)
- Related learnings:
  - `knowledge-base/project/learnings/2026-03-21-cloudflare-api-token-permission-editing.md` (token scope expansion without rotation)
  - `knowledge-base/project/learnings/integration-issues/2026-04-10-cloudflare-dashboard-react-select-playwright-workaround.md` (dashboard automation)
  - `knowledge-base/project/learnings/2026-04-18-cloudflare-default-bypasses-dynamic-paths.md` (similar CF-enum-drift class)

## Tags

category: integration-issues
module: apps/web-platform/infra
