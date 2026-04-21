---
name: cloudflare-waf-ua-allowlist-and-narrow-token-plan-vs-apply
description: Lessons from PR #2740 shipping a Cloudflare AI-crawler UA allowlist (issue #2662) — the plan-vs-apply scope asymmetry on narrow CF tokens, UA substring-match pitfalls, and the provider-alias-description-drift trap when a narrow token gains a second consumer.
type: integration-issues
date: 2026-04-21
pr: 2740
issue: 2662
tags:
  - cloudflare
  - terraform
  - waf
  - narrow-token
  - firewall-ruleset
  - ua-match
---

# Cloudflare WAF UA allowlist: `terraform plan` vs `apply` scope, UA substring collisions, and narrow-token description drift

## Problem

Issue #2662 was a P0 AEO blocker: Cloudflare's Browser Integrity Check was returning HTTP 403 to documented AI-crawler UAs (`GPTBot`, `ClaudeBot`, `PerplexityBot`, etc.) on `soleur.ai/*`, making every FAQPage / citation-ready answer invisible to AI answer engines. Fix landed via a single `cloudflare_ruleset` in phase `http_request_firewall_custom` with one `skip` rule. Three non-obvious things surfaced during implementation, review, and deepen-plan.

## Key insights (generalizable)

### 1. `terraform plan` succeeds on a create-only resource without the write scope; `apply` requires it

The existing narrow token `CF_API_TOKEN_RULESETS` was originally provisioned with `Cache Rules:Edit` (for `cache.tf`). The new firewall-custom ruleset needs `Zone WAF:Edit`. A live API probe confirmed the current token **cannot** read the `http_request_firewall_custom/entrypoint`:

```json
{"success": false, "errors": [{"message": "request is not authorized"}]}
```

But `terraform plan` with the exact same token **still produced a clean `1 to add, 0 to change, 0 to destroy`**. Why: plan only needs to refresh state for resources Terraform already owns; for a resource not yet in state (`cloudflare_ruleset.allowlist_ai_crawlers` is pure `+ create`), plan does NOT probe the CF API for an existing instance — it just drafts the intended POST. The CREATE call, which happens at apply time, is where the `Zone WAF:Edit` permission matters.

**Operational implication:** you can validate a new CF ruleset PR end-to-end pre-merge (validate + plan + review) with a read-limited token. The token scope expansion is genuinely a post-merge operator step; blocking the PR on it gains nothing. Document the scope requirement in the PR body so the operator doesn't hit a surprise at apply time.

**What this does NOT imply:** when your plan shows a `~ change` or `- destroy` on an existing resource in a phase the token can't write to, you will hit the scope error at refresh time, not create time. The plan-succeeds-without-write-scope shortcut only works for pure-add resources.

### 2. UA substring-match via `lower(http.user_agent) contains "<token>"` needs word-boundary anchors for short tokens

The allowlist expression originally used `lower(http.user_agent) contains "ccbot"` for Common Crawl. `ccbot` is only five letters and case-folded; it matches `MyCCBot`, `RogueCCBot`, `payccbot`, and anything else containing that run. On a shared-protection ruleset, a short-token substring match is an abuse-surface: anyone setting `User-Agent: payccbot` bypasses BIC, securityLevel, uablock, and ratelimit.

**Fix:** Cloudflare Rules Engine supports `matches` (regex). Anchor with non-alpha boundaries:

```hcl
"(lower(http.user_agent) matches \"(^|[^a-z])ccbot([^a-z]|$)\")"
```

**When you need to decide:** evaluate each UA token against "is this a common English substring or a unique bot-product name?"

- Unique (substring fine): `gptbot`, `claudebot`, `perplexitybot`, `bytespider`, `amazonbot`, `anthropic-ai`, `diffbot`
- Short/generic (regex needed): `ccbot`, `youbot`, `hot` (never a UA token but the pattern applies to `products` too)
- Borderline: `applebot-extended` (safe because hyphenated), `google-extended` (safe, hyphenated)

**Rule of thumb:** if the token has `<=6 chars` AND is plausibly a substring of an unrelated UA, regex-anchor it. Otherwise substring is fine.

### 3. When a narrow CF provider alias gains a second consumer, its variable description and provider-block comment drift out of sync — and no test catches it

`cf_api_token_rulesets` was introduced for `cache.tf` with description `"Cache Rules:Edit on soleur.ai (cloudflare_ruleset resources)"`. When `bot-allowlist.tf` reused the same alias (the architecturally correct choice per `cq-cloudflare-provider-alias-for-narrow-scope`), the description became stale: the alias now covers BOTH `Cache Rules:Edit` and `Zone WAF:Edit`. The provider-block comment in `main.tf` had the same problem.

There is no automated check for this — `terraform validate` doesn't read variable descriptions, and the Doppler secret key name doesn't encode its permission list.

**Prevention going forward:**

- When reusing a narrow provider alias for a new consumer, edit the variable description AND the provider-block comment in the same PR. Enumerate each consumer's `.tf` file and phase inline.
- Include a `Current consumers:` list in the provider-block comment so adding the third consumer surfaces the second as precedent:

```hcl
# Separate provider for Cloudflare Rulesets APIs (cache rules, firewall
# custom rules). ...
# Current consumers:
#   - cache.tf                 (http_request_cache_settings)  — #2542
#   - bot-allowlist.tf         (http_request_firewall_custom) — #2662
```

## Solution (as shipped in PR #2740)

- One new file: `apps/web-platform/infra/bot-allowlist.tf` with a zone-scoped `cloudflare_ruleset` in phase `http_request_firewall_custom`.
- One `skip` rule, `action_parameters.products = ["bic", "securityLevel", "uablock", "hot"]`, `action_parameters.phases = ["http_ratelimit"]`. **Not** including `http_request_firewall_managed` — see Sharp Edges.
- UA expression joins 20 per-token predicates; all use `contains` except `ccbot`, which uses `matches` with a word-boundary anchor.
- Reused existing `cloudflare.rulesets` provider alias; updated `variables.tf` description and `main.tf` alias comment to reflect both consumers.

Post-merge operator work (in order):

1. Expand `CF_API_TOKEN_RULESETS` scope in the Cloudflare dashboard: add `Zone WAF:Edit` on zone `soleur.ai`. Token value does NOT rotate on permission edit (per `2026-03-21-cloudflare-api-token-permission-editing.md`) — Doppler secret stays valid.
2. Run the standard doppler-wrapped `terraform apply` per `cq-when-running-terraform-commands-locally`. Expect `1 resource added, 0 changed, 0 destroyed`.
3. Verify via `curl -A "GPTBot/1.1" -sI https://soleur.ai/` returning HTTP 200 (was 403 pre-apply). Loop over all 20 UA tokens.

## Sharp edges

- **Do NOT add `http_request_firewall_managed` to the skipped phases "for future-proofing"**. Initial plan included it with rationale "if waf=on later, allowlist stays intact." Security review correctly flagged this: pre-authorizing a skip of the Managed Ruleset for any UA-asserting-AI client means a spoofed `User-Agent: GPTBot` bypasses every future zone-wide CF emergency rule (Log4Shell-class patches, CVE-driven Managed rule additions) the moment `waf` is enabled. **Principle: don't pre-authorize skips against rules that don't yet exist.** If a specific Managed rule empirically blocks a legit AI crawler after waf=on, re-add narrowly via `action_parameters.skip_rules = [<rule_id>]` scoped to that one rule.

- **Context7 enum drift still bites** — Context7's Cloudflare Terraform provider docs returned `uaBlock` / `rateLimit` / `zoneLockdown` (camelCase) and listed `http_request_sbfm` in the `phases` enum. The pinned `cloudflare/cloudflare@4.52.7` depends on cloudflare-go v0.115.0, whose `RulesetActionParameterProductValues()` uses lowercase (`uablock`, `hot`, `ratelimit`, `zonelockdown`; only `securityLevel` is camelCase) and whose `RulesetPhaseValues()` does NOT include `http_request_sbfm`. Applying Context7's values verbatim would have failed `terraform validate`. Direct inspection of the library source is the authoritative resolution when Context7 and the pinned provider disagree. This is a fresh concrete instance of `2026-04-10-context7-terraform-provider-version-mismatch.md`.

- **`starts_with(lower(...), "ccbot")` also works** but fails open if a vendor prepends their UA with a product prefix (`MyCrawler-CCBot/2.0`). The regex word-boundary form `(^|[^a-z])ccbot([^a-z]|$)` handles that case.

## Session errors

1. **Bash CWD drift on first commit attempt** — I ran `git add apps/web-platform/infra/bot-allowlist.tf ...` while the Bash tool's persistent CWD was `apps/web-platform/infra/` (from a prior `cd`). Git resolved the path relative to that CWD, producing `apps/web-platform/infra/apps/web-platform/infra/bot-allowlist.tf`, and failed with `pathspec did not match any files`. Recovery: re-ran with `cd <worktree-root> && git add ...` chained in the same Bash call. **Prevention:** for any commit workflow, always chain `cd <worktree-abs-path> &&` in the same Bash call, OR pass absolute paths to `git add`. This is the same class as `cq-for-local-verification-of-apps-doppler` (shell state doesn't persist) but for git operations — worth noting that running terraform/validate/plan commands can leave Bash in a sub-directory that later `git add` invocations inherit.

2. **Forwarded from plan subagent (captured in session-state.md)** — Context7-vs-pinned-provider enum drift caught in deepen pass, not at runtime. Two specific hits (product-enum casing, `http_request_sbfm` absence). No runtime impact because deepen-plan caught them pre-commit. Class is already covered by the 2026-04-10 learning; this session added `http_request_sbfm` as a new concrete instance of the pattern.

## Prevention checklist (future CF WAF work)

- [ ] Before reusing a narrow provider alias for a new resource, edit the variable description AND the `provider "cloudflare"` block comment in the same PR.
- [ ] Before shipping a UA-matching firewall expression, audit each token for substring collisions. Use regex anchors for any token `<= 6 chars` that is plausibly a substring of an unrelated UA.
- [ ] Do NOT include `http_request_firewall_managed` in `skip` phases unless you are skipping a **specific** Managed rule that is empirically blocking legitimate traffic — and even then, prefer `skip_rules = [<rule_id>]` over phase-wide skip.
- [ ] Cross-check any `products` / `phases` value Context7 returns against the pinned cloudflare-go source (`.terraform.lock.hcl` → library version → `rulesets.go` on the matching tag). Run `terraform validate` immediately after drafting and before commit.
- [ ] When committing from a worktree after a `cd` into a subdirectory, prepend `cd <worktree-root> &&` to the `git add/commit/push` Bash call.
- [ ] Document in the PR body that post-apply requires a CF token scope expansion BEFORE `terraform apply`, so the operator doesn't hit `request is not authorized` at apply time.

## References

- PR #2740 — this fix
- Issue #2662 — P0 report
- Audit: `knowledge-base/marketing/audits/soleur-ai/2026-04-19-aeo-audit.md` §P0-1
- `knowledge-base/project/learnings/2026-04-10-context7-terraform-provider-version-mismatch.md` — Context7 enum drift
- `knowledge-base/project/learnings/2026-03-21-cloudflare-api-token-permission-editing.md` — token scope expansion via Playwright
- `knowledge-base/project/learnings/integration-issues/2026-04-10-cloudflare-dashboard-react-select-playwright-workaround.md` — React Select in CF dashboard
- `knowledge-base/project/learnings/2026-04-18-cloudflare-zone-settings-narrow-token-and-tfstate-recovery.md` — narrow-alias precedent; orphan state recovery
- AGENTS.md rules applied: `cq-cloudflare-provider-alias-for-narrow-scope`, `cq-terraform-failed-apply-orphaned-state`, `cq-when-running-terraform-commands-locally`, `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`
