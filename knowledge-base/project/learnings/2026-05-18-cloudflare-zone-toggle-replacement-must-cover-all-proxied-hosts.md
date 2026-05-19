---
date: 2026-05-18
problem_type: security_issue
component: cloudflare_ruleset
severity: high
tags: [cloudflare, ruleset, https-upgrade, hsts, subdomain-coverage, multi-agent-review, infra]
synced_to: []
---

# Replacing a zone-wide Cloudflare toggle with a path-aware ruleset must cover every host the toggle previously covered

## Problem

PR-α (commit `5fe23e47`) replaced Cloudflare's zone-level `always_use_https` toggle with `cloudflare_ruleset.acme_aware_https_upgrade` — a 2-rule ruleset that (Rule 1) skips HTTPS upgrade for `/.well-known/acme-challenge/*` on the apex + www hosts so Let's Encrypt HTTP-01 can renew the GitHub Pages cert, and (Rule 2) 301-redirects HTTP → HTTPS for everything else.

The initial draft inherited the same host-scope into both rules: Rule 2's expression was `(http.host in {"soleur.ai" "www.soleur.ai"} and not ssl)`. This dropped HTTPS upgrade for every OTHER proxied host in the zone — concretely `app.soleur.ai` (Next.js + Hetzner origin, carries Supabase access/refresh tokens in `Cookie`/`Authorization` headers) and `deploy.soleur.ai` (CF Tunnel, carries `CF-Access-Client-Id` + `CF-Access-Client-Secret` + HMAC deploy creds).

Effect: plain-HTTP requests to either subdomain reached the origin without TLS upgrade. HSTS preload (`include_subdomains = true`, submitted 2026-03-20, **pending** Chromium inclusion per `domains.md:32`) protects returning HTTPS visitors only — first-visit users, server-side OG-image fetchers, OAuth callback retries on the `http://` scheme, and any client whose HSTS cache expired all leaked credentials on the wire between user and Cloudflare's edge.

The defect was invisible to `terraform validate`, `terraform plan`, `terraform fmt`, and the targeted-resource `infra-validation.yml` workflow. It surfaced only at the multi-agent review pass — `security-sentinel` flagged it as P1 and `user-impact-reviewer` independently concurred (Finding 1, 2, 5 in the review report).

## Root Cause

Two semantic concerns with **different host scopes** were collapsed into a single host-scope expression:

| Rule | Concern | Correct host scope |
|---|---|---|
| Rule 1 (skip) | "Which hosts need the ACME exception?" | apex + www only — only GitHub Pages uses LE HTTP-01 for origin-cert renewal |
| Rule 2 (redirect) | "Which hosts need HTTPS upgrade?" | **all proxied hosts in the zone** — replacement for `always_use_https = on` |

Inheriting Rule 1's narrower scope into Rule 2 was the coverage collapse. `app.soleur.ai` and `deploy.soleur.ai` use Cloudflare-managed edge certs (not origin LE), so they don't need the ACME carve-out — but they DID previously rely on the zone-toggle for HTTPS upgrade.

## Solution

Change Rule 2's expression from a host-scoped match to zone-wide `(not ssl)`:

```hcl
# BEFORE (host-scoped — incorrect, drops app/deploy coverage)
expression = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and not ssl)"

# AFTER (zone-wide — restores prior always_use_https = on coverage)
expression = "(not ssl)"
```

Rule 1 stays host-scoped to apex + www because the ACME carve-out is genuinely narrower. See `apps/web-platform/infra/acme-challenge-ruleset.tf` post-fix.

## Key Insight

When replacing a zone-wide CF setting with a path-aware ruleset, the **exception** rule and the **upgrade** rule can have different host scopes. The exception is usually narrower (one origin needs the carve-out); the upgrade must be at least as wide as the toggle it replaces. Inheriting the exception's scope into the upgrade is a silent coverage collapse that doesn't surface at any IaC validation gate — only review prompts that explicitly enumerate every proxied host in the zone catch it.

## Prevention

1. **Review-prompt mandate.** When reviewing any PR that disables a zone-wide Cloudflare setting and adds a path-aware ruleset, the review-spawn prompt MUST literally enumerate every proxied host in the zone (cheapest: `grep -E '"(A|CNAME)"' apps/web-platform/infra/dns.tf | grep -v 'proxied.*false' | grep name`) and ask reviewers to verify each host is covered by the replacement rule's expression.
2. **Default to zone-wide for upgrade rules.** A "force HTTPS" rule should default to `(not ssl)` (any plain-HTTP request gets redirected) unless there's a concrete reason to host-scope. The exception is the narrower rule; the upgrade is the broader rule.
3. **user-impact-reviewer agent fires automatically.** Any `cloudflare_ruleset` PR that disables a zone-level toggle warrants the `user-impact-reviewer` agent regardless of the plan's `brand_survival_threshold` — the regression vector is cross-subdomain credential exposure, which is single-user-incident-class by default.
4. **Defense at plan time.** Plans for "replace zone toggle with ruleset" PRs must include an Acceptance Criterion of the form "Rule N's expression covers all proxied hosts in `dns.tf`, verified by enumerating each."

## Session Errors

1. **Sub-100-line spot-read insufficient for "not present" claims.** Initial pipeline brief asserted apex/www DNS records were NOT in `dns.tf` (only `app`, `deploy`, email records). The actual file was 246 lines; the records were at lines 186-219. The orchestrator read only the first ~55 lines before drawing the conclusion. Recovery: planning subagent did full-file read and overturned scope items 1, 2, 3, 5 of PR-α. **Prevention:** when asserting "resource X is not in file Y" before scope-defining a PR, run `wc -l <file>` first and either read the full file or grep the resource pattern with no line limit. Sub-100-line spot-reads are not sufficient evidence for absence claims on config files.

2. **Plan made unverified v4-provider claim.** Initial plan stated v4 `cloudflare_zone_settings_override` doesn't cleanly expose `always_use_https`, deferring it to a v5-migration follow-up "PR-δ" — would have shipped a manual dashboard click violating `hr-never-label-any-step-as-manual-without`. Deepen-plan caught it via Context7 verification against the v5-migration guide on `main`. **Prevention:** any plan claim of the form "v4 provider doesn't support X" MUST cite verbatim Context7 docs at plan time, not at deepen-plan. Routes to plan skill Sharp Edges.

3. **P1 cross-subdomain HTTPS-upgrade regression caught only at review.** Plan + brainstorm + deepen + work all missed the host-scope collapse. Multi-agent review (security-sentinel + user-impact-reviewer concurring) caught it pre-merge. **Prevention:** see this learning's "Prevention" section item 1 — review-spawn prompt mandate. Same defect class as the cross-artifact contract drift catalogued in `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` (locally-correct + cross-boundary-wrong).

4. **Phase-cap uncertainty unaddressed at plan time.** Plan claimed Free-tier `http_request_dynamic_redirect` cap is per-ruleset; git-history (PR #3357 commit message) reports the error wording was "in the phase" — strongly suggests per-phase. Plan made the assertion with no empirical verification. Could fail at apply time. Recovery: added an explicit fallback runbook to PM2 in the plan (inline ACME rules into `seo_page_redirects`, drop 2 lowest-value SEO rules). **Prevention:** when introducing a new `cloudflare_ruleset` on a phase that already has a ruleset, plan MUST cite authoritative CF docs OR a successful prior apply with multiple rulesets on the same phase. Routes to plan skill.

5. **HSTS table row stale in `domains.md`.** Pre-existing: `domains.md:31` claimed `max-age=31536000` (1y) while `cloudflare-settings.tf` codified `63072000` (2y) since PR #2528 (2026-04-18) — ~4 weeks of stale doc. Fixed inline this PR. **Prevention:** when bumping `last_updated:` frontmatter on a mirror-shaped doc, sweep every row that mirrors a codified value for drift. Routes to compound-capture? No — too specific. Routes to a future docs-mirror-drift skill, or stays in this learning as a one-off prevention note.

## Related

- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — this is a fresh instance of the same defect class (locally-correct rule, cross-boundary coverage gap).
- `knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` — same shape (one agent reads file A in isolation, can't catch contradiction with file B).
- `knowledge-base/project/plans/2026-05-18-fix-soleur-ai-apex-cf-iac-plan.md` — the plan whose scope was overturned and AC1-AC6 narrowed in deepen.
- Commit `5fe23e47` — the production fix.
- Commit `e8197f35` — review-fix commit (this defect was caught here).
- `hr-all-infrastructure-provisioning-servers` — the rule that motivated codifying `always_use_https = "off"` in IaC instead of leaving it as a dashboard step.
- 2026-05-18 incident PIR (filed via `/soleur:incident` after PR-α merge + cert recovery).

## Tags

category: security-issues
module: apps/web-platform/infra (Cloudflare ruleset)
