---
title: "feat: fix GSC critical indexing issues for soleur.ai"
type: feature
classification: ops-only-prod-write
issue: "#3297"
brainstorm: knowledge-base/project/brainstorms/2026-05-05-gsc-indexing-fixes-brainstorm.md
spec: knowledge-base/project/specs/feat-seo-gsc-indexing-fixes/spec.md
branch: feat-seo-gsc-indexing-fixes
worktree: .worktrees/feat-seo-gsc-indexing-fixes/
draft_pr: "#3296"
brand_critical: true
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-05-05
---

# feat: fix GSC critical indexing issues for soleur.ai

## Overview

Google Search Console flagged 29 pages on `soleur.ai` across 5 critical-indexing
categories (snapshot 2026-05-05). The fix lands in three building blocks:

1. **Switch canonical hostname to www** — `_data/site.json` declares apex; CF
   301s every apex URL to www; sitemap, robots, OG tags all reference the
   wrong host. One-line config change resolves ~18 of 20 redirect-bucket entries.
2. **Replace meta-refresh redirects with HTTP 301 at the edge** — Cloudflare
   Single Redirects (`http_request_dynamic_redirect`) replace
   `page-redirects.njk` + `_data/pageRedirects.js`. Adds the missing
   `terms-of-service.html` mapping. Resolves ~6 entries scattered across
   redirect / crawled-not-indexed / alternate-canonical buckets.
3. **`X-Robots-Tag` headers on subdomain leaks + RSS feed** — Cloudflare
   Transform Rules (`http_response_headers_transform`) on `api.soleur.ai`,
   `deploy.soleur.ai`, and `www.soleur.ai/blog/feed.xml`. The user-brand-critical
   vector (`deploy.soleur.ai` is the 1× 403 entry — Googlebot enumerated it via
   CT logs).

Single PR, single Terraform file, all landing in the existing
`apps/web-platform/infra/` root.

## Research Reconciliation — Spec vs. Codebase

| Spec / Brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "No existing Cloudflare Terraform root manages soleur.ai DNS/redirects" (brainstorm Capability Gaps) | `apps/web-platform/infra/` manages the entire `soleur.ai` zone (DNS, Tunnel + Access for `deploy`, Supabase CNAME for `api`, zone settings, cache rulesets, bot management). | **Add new `.tf` to existing root**, not a new root. R2 backend already in place. Splitting state files would risk provider conflicts on the shared zone. |
| "Cloudflare Bulk Redirects" (brainstorm Vector 2) | 19 redirects (17 pageRedirects + 1 missing terms-of-service + 1 blog redirect entry) — small set. Single Redirects (`cloudflare_ruleset` `phase = "http_request_dynamic_redirect"`) is the right primitive. | Use **Single Redirects**, not Bulk Redirects. |
| "deploy.soleur.ai admin/deployment subdomain leaked" (brainstorm Vector 3) | `deploy.soleur.ai` is intentionally CF-proxied with `cloudflare_zero_trust_access_application.deploy` (`tunnel.tf`). The 403 IS the CF Access challenge — by design. Discovery vector is CT-log enumeration. | **Reframe as "subdomain hardening"**, not "leak fix". The auth wall is correct; what's missing is `X-Robots-Tag`. Per learning [`deploy-pipeline-fix-postapply-verification-cf-access`](../learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md), verify Transform Rule fires on the Access challenge response. |
| Spec FR2 "every entry in `_data/pageRedirects.js`" — implies full coverage of legacy redirect surface | A SECOND meta-refresh system exists: `_data/blogRedirects.js` + `blog/redirects.njk` (date-prefixed slugs → canonical). Validator dependency: `scripts/validate-blog-links.sh` uses `blogRedirects.js`. None of the GSC-flagged URLs match the blog date-prefix pattern in this snapshot. | **Scope blog redirects OUT** of this PR. Tracked separately (deferral issue at plan exit). Document why in Non-Goals. Pair with deferred meta-refresh deletion below. |
| `cf_api_token_rulesets` token (existing) is sufficient | Existing scope: **Cache Rules:Edit + Zone WAF:Edit** (`variables.tf:69`). New work needs **Single Redirect Rules:Edit** + **Transform Rules:Edit**. | **Expand existing token scope**, do NOT mint a new token. Same blast radius (zone-scoped rule writes). Operator action documented in post-merge runbook. |
| Plan Files-to-Delete listed `page-redirects.njk` + `pageRedirects.js` | Deletion in same PR creates a window where docs deploy can run before `terraform apply`, leaving URLs as 404s until apply. | **Defer deletion to follow-up PR.** This PR adds Cloudflare 301s + leaves meta-refresh files untouched (harmless coexistence — CF's request-phase 301 fires before origin fetch). |

## User-Brand Impact

**If this lands broken, the user experiences:**

- **Prospect (anonymous via Google):** brief sitemap-regen lag where search
  results go stale or return broken pages. Worst case: a misconfigured
  Transform Rule on `deploy.soleur.ai` interferes with the Cloudflare Zero
  Trust Access challenge, exposing internal admin tooling to public view.
- **Authenticated app user (`api.soleur.ai` Supabase REST/Auth path):** the
  new Transform Rule injects `X-Robots-Tag` on responses from `api.soleur.ai`.
  This is the path that carries Soleur app login, conversations, messages,
  and BYOK token operations. Although `X-Robots-Tag` is not a CORS-relevant
  header, scope creep on the Supabase REST surface is the highest-blast-radius
  scenario in this PR — every request from every app user passes through.
  Mitigation: rule scoped to `http.request.method eq "GET"` (no impact on
  POST/PATCH/DELETE/OPTIONS preflights).
- **Legal-document signer (slug-rename redirect):** legacy
  `/pages/legal/terms-of-service.html` now 301s to
  `/legal/terms-and-conditions/`. Verified pre-merge: the destination is the
  canonical, semantically-equivalent Terms page (slug-rename, not policy
  change). If a future slug-rename happens without updating
  `seo-rulesets.tf`, a prospect could land on the wrong policy text — single-
  user incident class.

**If this leaks, the user's [trust / brand / data path] is exposed via:**

- **`deploy.soleur.ai` Transform Rule scope error.** Wrong `expression`,
  wrong `phase`, or interaction with `cloudflare_zero_trust_access_application.deploy`
  could short-circuit Access enforcement. The Access app holds (independent
  ruleset), but a Transform Rule that touches the Access challenge response
  in the wrong way could surface 403 HTML body content publicly.
- **Partial-apply state during `terraform apply`.** If apply lands
  `seo_page_redirects` but fails on `seo_response_headers` (e.g., token-scope
  expansion forgotten), 19 page redirects fire WITHOUT the X-Robots-Tag
  protection on subdomain user-data paths — half-protection sits live until
  the operator re-runs apply. Mitigation: `terraform plan -out=<file>` shows
  the full diff before commit; operator must verify both rulesets present.
- **Wrong-destination 301.** Mitigated pre-merge by verification of the
  `terms-of-service.html` → `terms-and-conditions/` mapping.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at
plan-time (this gate). `user-impact-reviewer` invoked at PR-review-time.

A plan whose `## User-Brand Impact` section is empty, contains only
`TBD`/`TODO`/placeholder text, or omits the threshold will fail
`deepen-plan` Phase 4.6.

## Files to Edit

```
apps/web-platform/infra/variables.tf                  # update cf_api_token_rulesets description
plugins/soleur/docs/_data/site.json                   # url: "https://www.soleur.ai"
plugins/soleur/docs/robots.txt                        # Sitemap: https://www.soleur.ai/sitemap.xml
plugins/soleur/docs/scripts/validate-seo.sh           # add canonical-host gate
.github/workflows/deploy-docs.yml                     # post-build apex-grep gate
```

## Files to Create

```
apps/web-platform/infra/seo-rulesets.tf               # both rulesets in one file
knowledge-base/project/specs/feat-seo-gsc-indexing-fixes/tasks.md  # generated at plan exit
```

## Files to Delete

None in this PR. Meta-refresh templates (`page-redirects.njk`, `_data/pageRedirects.js`)
deferred to follow-up issue (created at plan exit) once Cloudflare 301s are
verified live.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open` against
each planned file path on 2026-05-05.

## Implementation Phases

### Phase 1 — Hostname canonicalization (Eleventy build)

1. **`plugins/soleur/docs/_data/site.json`:** `url: "https://soleur.ai"` →
   `url: "https://www.soleur.ai"`.
2. **`plugins/soleur/docs/robots.txt`:** `Sitemap: https://soleur.ai/sitemap.xml` →
   `Sitemap: https://www.soleur.ai/sitemap.xml`.
3. **Audit `{{ site.url }}` interpolation surfaces** per learning
   `2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`.
   `_includes/base.njk` has 23 `site.url` references; sitemap, og, JSON-LD,
   RSS feed all consume it. Run `npx @11ty/eleventy` and grep:
   ```
   rg -n 'https://soleur\.ai(/|[a-zA-Z]|$)' _site/ | head -20
   ```
   Expect zero matches. Any hit means a hardcoded apex string — find and
   route through `site.url`.
4. **Add canonical-host gate to `plugins/soleur/docs/scripts/validate-seo.sh`:**
   read existing validator; assert `_site/sitemap.xml` `<loc>` entries all
   use the host parsed from `site.url`. Fail build on mismatch.
5. **Add post-build apex-grep gate to `.github/workflows/deploy-docs.yml`:**
   after Eleventy build succeeds, fail the workflow if the regex above matches.

### Phase 2 — Cloudflare Single Redirects + Transform Rules (Terraform)

Create `apps/web-platform/infra/seo-rulesets.tf`. Both rulesets in one file:
they share provider, zone, and intent.

**Token scope expansion** (operator post-merge action, documented in PR body):
the existing `cf_api_token_rulesets` token grants Cache Rules:Edit + Zone
WAF:Edit. The operator must edit this token at
[Cloudflare API tokens](https://dash.cloudflare.com/profile/api-tokens) to
add **Single Redirect Rules:Edit** + **Transform Rules:Edit**, both scoped
to `Zone:soleur.ai`. Update Doppler if the token rotates as part of this.

**Update `apps/web-platform/infra/variables.tf`** comment for
`cf_api_token_rulesets` to reflect new scope:

```hcl
variable "cf_api_token_rulesets" {
  description = "CF API token: Cache Rules:Edit + Zone WAF:Edit + Single Redirect Rules:Edit + Transform Rules:Edit on soleur.ai"
  type        = string
  sensitive   = true
}
```

**`seo-rulesets.tf` — Single Redirects (Vector 2):**

```hcl
# Cloudflare Single Redirects: legacy /pages/*.html → clean URLs (HTTP 301).
#
# Replaces meta-refresh template plugins/soleur/docs/page-redirects.njk +
# _data/pageRedirects.js. Meta-refresh + canonical is classified
# non-deterministically by Google across "Page with redirect", "Crawled - not
# indexed", and "Alternate page with proper canonical tag" buckets. HTTP 301
# at the edge is deterministic. See learning 2026-05-05-gsc-indexing-triage-patterns.md.
#
# This phase runs BEFORE origin fetch, so the 301 is served regardless of
# whether the meta-refresh HTML files remain in /_site (they will, until a
# follow-up PR removes them — see issue #<deferred-meta-refresh-cleanup>).
resource "cloudflare_ruleset" "seo_page_redirects" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Legacy /pages/*.html → clean URLs (HTTP 301)"
  description = "Edge 301s replacing _data/pageRedirects.js. See issue #3297."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    action      = "redirect"
    description = "Redirect /pages/agents.html → /agents/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/agents.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/agents/"
        }
      }
    }
  }

  # ... 18 more `rules` blocks, one per row in the table below
}
```

**Full mapping (19 rules):**

| From | To | Source |
|---|---|---|
| `/pages/agents.html` | `/agents/` | pageRedirects.js |
| `/pages/skills.html` | `/skills/` | pageRedirects.js |
| `/pages/vision.html` | `/vision/` | pageRedirects.js |
| `/pages/community.html` | `/community/` | pageRedirects.js |
| `/pages/getting-started.html` | `/getting-started/` | pageRedirects.js |
| `/pages/legal.html` | `/legal/` | pageRedirects.js |
| `/pages/pricing.html` | `/pricing/` | pageRedirects.js |
| `/pages/changelog.html` | `/changelog/` | pageRedirects.js |
| `/pages/legal/privacy-policy.html` | `/legal/privacy-policy/` | pageRedirects.js |
| `/pages/legal/terms-and-conditions.html` | `/legal/terms-and-conditions/` | pageRedirects.js |
| `/pages/legal/terms-of-service.html` | `/legal/terms-and-conditions/` | **NEW (missing entry)** |
| `/pages/legal/cookie-policy.html` | `/legal/cookie-policy/` | pageRedirects.js |
| `/pages/legal/gdpr-policy.html` | `/legal/gdpr-policy/` | pageRedirects.js |
| `/pages/legal/acceptable-use-policy.html` | `/legal/acceptable-use-policy/` | pageRedirects.js |
| `/pages/legal/data-protection-disclosure.html` | `/legal/data-protection-disclosure/` | pageRedirects.js |
| `/pages/legal/individual-cla.html` | `/legal/individual-cla/` | pageRedirects.js |
| `/pages/legal/corporate-cla.html` | `/legal/corporate-cla/` | pageRedirects.js |
| `/pages/legal/disclaimer.html` | `/legal/disclaimer/` | pageRedirects.js |
| `/blog/what-is-company-as-a-service/index.html` | `/company-as-a-service/` | pageRedirects.js |

**`seo-rulesets.tf` — Transform Rules (Vector 3 + 4):**

```hcl
# Cloudflare Transform Rules: X-Robots-Tag headers on subdomain surfaces + RSS.
#
# Three response-header injections:
#   1. api.soleur.ai/*  → X-Robots-Tag: noindex, nofollow (Supabase REST root)
#   2. deploy.soleur.ai/* → X-Robots-Tag: noindex, nofollow (CF Access surface)
#   3. www.soleur.ai/blog/feed.xml → X-Robots-Tag: noindex (RSS feed)
#
# A 403 is not equivalent to a noindex — Google still records URL existence
# without a snippet. CT-log enumeration discovers the subdomains regardless of
# public links; defense in depth is the indexing block, not the auth wall.
#
# IMPORTANT (deploy.soleur.ai): per learning bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md
# the response curl returns the CF Access challenge HTML. Verify the Transform
# Rule fires on the Access challenge response itself, not just the origin
# response. If Access intercepts before the response_headers_transform phase,
# this rule is silently a no-op — the verification curl in the post-merge
# runbook (Phase 4) is load-bearing.
resource "cloudflare_ruleset" "seo_response_headers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "X-Robots-Tag on subdomains + RSS feed"
  description = "Defense-in-depth noindex for non-public subdomains + RSS. See issue #3297."
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag noindex,nofollow on api.soleur.ai/*"
    enabled     = true
    expression  = "(http.host eq \"api.soleur.ai\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex, nofollow"
      }
    }
  }

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag noindex,nofollow on deploy.soleur.ai/*"
    enabled     = true
    expression  = "(http.host eq \"deploy.soleur.ai\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex, nofollow"
      }
    }
  }

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag noindex on www.soleur.ai RSS feed"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/blog/feed.xml\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex"
      }
    }
  }
}
```

**v4 schema verification:** the pinned provider is `cloudflare ~> 4.0`
(`main.tf:23`). v4 uses repeated nested-block syntax (e.g. `headers { name = "X-...", operation = "set", value = "..." }`),
NOT v5 attribute-map syntax. Run `terraform validate` after writing the file
to confirm — `cache.tf` is the structural template (uses nested blocks for
`edge_ttl`/`browser_ttl`).

### Phase 3 — `terraform validate` and pre-merge baseline capture

1. **`terraform validate`** locally with Doppler-injected env:
   ```
   cd apps/web-platform/infra && \
     doppler run --project soleur --config prd_terraform -- \
       doppler run --token "$(doppler configure get token --plain)" \
         --project soleur --config prd_terraform --name-transformer tf-var -- \
     terraform validate
   ```
   Must pass before push.
2. **Capture pre-change baselines** (so the post-apply diff is observable):
   ```
   curl -IA "Mozilla/5.0" https://deploy.soleur.ai/  > /tmp/deploy-baseline.txt 2>&1
   curl -IA "Googlebot"   https://api.soleur.ai/     > /tmp/api-baseline.txt 2>&1
   curl -IA "Googlebot"   https://www.soleur.ai/blog/feed.xml > /tmp/feed-baseline.txt 2>&1
   ```
   Confirm none currently include `X-Robots-Tag`. Attach to PR description as
   evidence.

### Phase 4 — Post-merge operator runbook

Combined: token scope expansion → `terraform apply` → wait for ruleset
propagation → docs deploy completion check → cache purge → curl verification
suite → GSC re-validation → close issue.

Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`: every destructive
write requires explicit per-command go-ahead.

```bash
# 1. Expand cf_api_token_rulesets scope (Cloudflare dashboard).
#    Add Single Redirect Rules:Edit + Transform Rules:Edit. Save token value
#    in Doppler if rotated. (No code change required if token value is unchanged.)

# 2. Apply Terraform.
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan -out=seo-fixes.tfplan
# OPERATOR: review the plan diff (expect 2 new rulesets, 22 rules); then approve.
… terraform apply -auto-approve seo-fixes.tfplan

# 3. Wait for ruleset propagation (~30-60s edge-eventually-consistent).
sleep 60

# 4. Wait for docs deploy completion (CI auto-fires on merge to main).
gh run list --workflow=deploy-docs.yml --limit 1 --json status,conclusion,databaseId
# Confirm conclusion=success before continuing — purging stale cache otherwise.

# 5. Cache purge (after both apply AND docs deploy succeed).
#    Token: CF_API_TOKEN_PURGE in Doppler `prd` (NOT prd_terraform), per
#    learning 2026-04-18-cf-cache-purge-on-share-revoke.md.
curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CF_API_TOKEN_PURGE}" \
  -H "Content-Type: application/json" \
  --data '{"files":[
    "https://www.soleur.ai/sitemap.xml",
    "https://www.soleur.ai/robots.txt",
    "https://www.soleur.ai/blog/feed.xml"
  ]}'

# 6. Curl verification suite — load-bearing.
# Vector 1 — canonical hostname
curl -ILA "Googlebot" https://soleur.ai/                          # expect 301 → www
curl -s   https://www.soleur.ai/sitemap.xml | grep -c "https://soleur\.ai/"   # expect 0
curl -s   https://www.soleur.ai/robots.txt  | grep "Sitemap:"                 # expect www host

# Vector 2 — page redirects (one representative + the missing-entry one)
curl -ILA "Googlebot" https://www.soleur.ai/pages/agents.html
# expect 301, Location: https://www.soleur.ai/agents/
curl -ILA "Googlebot" https://www.soleur.ai/pages/legal/terms-of-service.html
# expect 301, Location: https://www.soleur.ai/legal/terms-and-conditions/

# Vector 3 — subdomain hardening
curl -IA "Googlebot" https://api.soleur.ai/    | grep -i x-robots-tag
# expect "noindex, nofollow"
curl -IA "Mozilla/5.0" https://deploy.soleur.ai/ 2>&1 | grep -iE "(x-robots-tag|HTTP/)"
# expect HTTP/2 403 AND X-Robots-Tag: noindex, nofollow
# (load-bearing: confirms Transform Rule fires on the CF Access challenge)

# Vector 4 — feed.xml
curl -IA "Googlebot" https://www.soleur.ai/blog/feed.xml | grep -i x-robots-tag
# expect "noindex"

# 7. GSC re-validation via Playwright MCP. Falls back to operator-clicks-button
#    if Playwright session can't auth (per AGENTS.md hr-never-label-any-step-as-manual-without:
#    Playwright must be tried first; only OAuth consent is genuinely manual).
#    Click "Validate fix" on each of the 5 critical-issue categories.

# 8. Close issue (ops-only-prod-write classification: PR uses "Ref #3297",
#    not "Closes #3297"; operator closes after verification).
gh issue close 3297 --comment "Verified live: see PR #<merged-pr> Phase 4 curl results."
```

If any verification fails, stop, investigate, and roll back via
`terraform destroy -target=cloudflare_ruleset.<name>` per learning
`2026-04-18-cloudflare-zone-settings-narrow-token-and-tfstate-recovery.md`.

### Phase 5 — Follow-up issue creation

At plan exit, create a single tracking issue:

> **`feat(seo): migrate blog redirects + delete page-redirects meta-refresh templates`**
>
> After PR #3297 ships and Cloudflare 301s are verified live, this follow-up:
> 1. Migrates `_data/blogRedirects.js` (date-prefixed blog slug → canonical) to
>    Cloudflare Single Redirects via the same `seo-rulesets.tf`. Requires a
>    build-time JSON export (or moving slug logic into HCL `locals` derived
>    from `git ls-files plugins/soleur/docs/blog/*.md`).
> 2. Deletes `plugins/soleur/docs/page-redirects.njk` and
>    `plugins/soleur/docs/_data/pageRedirects.js`. Eleventy stops emitting the
>    meta-refresh pages; CF 301s have been live for N days at that point.
> 3. Updates `scripts/validate-blog-links.sh` for the new data source.
> 4. Removes any vestigial "skip redirect pages" logic in `validate-seo.sh`
>    (per learning `2026-03-05-seo-validator-skip-redirect-pages.md`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/seo-rulesets.tf` exists with 2 rulesets:
      `seo_page_redirects` (19 rules) and `seo_response_headers` (3 rules).
- [ ] `apps/web-platform/infra/variables.tf` has updated description on
      `cf_api_token_rulesets` reflecting Single Redirect Rules + Transform Rules
      scope.
- [ ] `terraform validate` passes locally (Doppler-injected env).
- [ ] `plugins/soleur/docs/_data/site.json` `url` is `https://www.soleur.ai`.
- [ ] `plugins/soleur/docs/robots.txt` `Sitemap:` line points to www.
- [ ] `plugins/soleur/docs/scripts/validate-seo.sh` has canonical-host gate.
- [ ] `.github/workflows/deploy-docs.yml` has post-build grep gate
      `rg 'https://soleur\.ai(/|[a-zA-Z]|$)' _site/` returning zero matches.
- [ ] Pre-change curl baselines for `deploy.soleur.ai`, `api.soleur.ai`,
      `feed.xml` attached to PR description (confirms no existing X-Robots-Tag).
- [ ] PR body uses `Ref #3297`, NOT `Closes #3297` (ops-only-prod-write
      classification).
- [ ] PR body has `## Changelog` section + `semver:patch` label.
- [ ] CPO sign-off received (single-user incident threshold).
- [ ] `user-impact-reviewer` agent invoked and passed.
- [ ] Standard review pipeline passed (DHH + Kieran + simplicity).

### Post-merge (operator)

- [ ] `cf_api_token_rulesets` token scope expanded in Cloudflare dashboard
      to include Single Redirect Rules:Edit + Transform Rules:Edit.
- [ ] `terraform plan` shows expected diff (2 new rulesets, 22 rules) and no
      drift on existing resources.
- [ ] `terraform apply` succeeds.
- [ ] 60s wait for ruleset propagation.
- [ ] `deploy-docs.yml` workflow succeeded post-merge (sitemap regenerated).
- [ ] Cache purge succeeds.
- [ ] All Phase 4 step 6 curl verifications pass.
- [ ] GSC URL Inspection on representative URL from each category shows
      expected new state.
- [ ] GSC "Validate fix" clicked on all 5 critical-issue categories
      (via Playwright MCP if session auth holds; operator-fallback otherwise).
- [ ] `gh issue close 3297` with verification comment.
- [ ] Follow-up issue created (see Phase 5).
- [ ] 7-day Chart.csv observation: indexed-vs-not-indexed ratio improving.

## Risks and Sharp Edges

1. **`terraform plan` ≠ `terraform apply` for `cloudflare_ruleset`** (learning:
   `2026-04-21-cloudflare-block-ai-bots-feature-bypasses-waf-phase-pipeline.md`).
   Plan-time validation is structurally insufficient. Schedule a low-traffic
   apply window.
2. **CF auto-injects `logging { enabled = true }` on certain rule actions**,
   causing post-apply inconsistency on subsequent plans. If drift surfaces
   after first apply, add the block to the affected rules.
3. **`X-Robots-Tag` on `deploy.soleur.ai` must be verified on the CF Access
   challenge response** (learning:
   `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`).
   The default response IS the Access challenge HTML/403. Phase 4 step 6
   verification is the load-bearing curl.
4. **`{{ site.url }}` interpolation surfaces** (learning:
   `2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`).
   Grep `_site/` post-build for stray apex hosts. JSON-LD, og:url, RSS
   `<link>`, sitemap, and any prose that hardcoded `https://soleur.ai/...`
   are candidates. The Phase 1 grep regex `(/|[a-zA-Z]|$)` covers all three
   shapes — narrower regexes leak false-negatives.
5. **Cloudflare cache after rule changes** (learnings:
   `2026-04-18-cf-cache-purge-on-share-revoke.md`,
   `2026-04-18-cloudflare-default-bypasses-dynamic-paths.md`). Phase 4 step 5
   purges sitemap + robots + feed; verify with `CF-Cache-Status: MISS` on
   first verification fetch.
6. **CF ruleset propagation is global-eventually-consistent** (~30-60s).
   Verification curls immediately after `apply` may hit stale edge. Phase 4
   step 3 is a 60s wait.
7. **Token scope expansion is operator action**, not Terraform. Pre-merge
   verification doesn't catch a missing scope; `apply` will fail with
   "not entitled". Document explicitly in PR body.
8. **GSC "Validate fix" UI is not API-available.** Playwright MCP automation
   tried first; operator-fallback if Playwright session can't auth. Manual
   fallback runbook in PR body.
9. **`apex` vs `www` and GitHub Pages CNAME.** `plugins/soleur/docs/CNAME`
   contains `soleur.ai` (apex), but live behavior 301s apex→www. The
   redirect happens via Cloudflare DNS-level configuration that this plan
   does NOT touch. Only the Eleventy build's source-of-truth for canonical
   (sitemap, OG, robots) flips to www; the apex→www 301 stays.
10. **Blog redirects intentionally scoped out.** `_data/blogRedirects.js` +
    `blog/redirects.njk` continue to emit meta-refresh pages — same Google
    classification non-determinism, just no GSC report URLs match the
    pattern in this snapshot. Tracked in Phase 5 follow-up.
11. **CT-log enumeration is unfixable** by this PR. `deploy.soleur.ai` will
    continue to appear in CT logs. The fix is defense-in-depth: 403 +
    `X-Robots-Tag: noindex, nofollow` is the strongest indexing block. If
    broader policy is "deploy subdomain should not be public DNS at all",
    that's a separate (larger) infra change.

## Test Strategy

This is an infrastructure change. Test surfaces:

- **Eleventy build tests** — `bun test plugins/soleur/test/components.test.ts`
  after `_data/site.json` change.
- **`validate-seo.sh`** — extended to assert sitemap canonical-host gate.
  Runs locally and in `deploy-docs.yml`.
- **`deploy-docs.yml`** — post-build apex-grep gate (load-bearing safety net).
- **Terraform** — `terraform validate` (CI-runnable), `terraform plan` review
  by operator before apply.
- **Live curl suite** (Phase 4 step 6) — operator runs after apply.

No unit tests for Cloudflare ruleset HCL — verification IS the curl suite
post-apply per learning `2026-04-22-plan-ac-external-state-must-be-api-verified.md`.

## Test Scenarios

1. **Apex 301 to www** — `curl -IA "Googlebot" https://soleur.ai/changelog/`
   returns `301`, `Location: https://www.soleur.ai/changelog/`. (Pre-existing
   behavior; verify unchanged.)
2. **Sitemap uses www host** — `_loc_` entries all under `https://www.soleur.ai/`.
3. **Legacy page 301** — `/pages/agents.html` returns `301` with `Location:
   https://www.soleur.ai/agents/`. Body empty (not meta-refresh HTML).
4. **Missing entry now resolves** — `/pages/legal/terms-of-service.html` returns
   `301` to `/legal/terms-and-conditions/` (was 404 pre-fix).
5. **api.soleur.ai serves X-Robots-Tag** — header `noindex, nofollow` present.
6. **deploy.soleur.ai serves X-Robots-Tag on Access challenge** — `403` AND
   header present (load-bearing).
7. **feed.xml noindex** — `200` AND `X-Robots-Tag: noindex`.
8. **No regression on existing pages** — `/agents/` still `200`.
9. **No apex URLs in built `_site/`** — grep returns zero matches.

## Domain Review

**Domains relevant:** Marketing, Engineering, Legal, Product

(Carry-forward from brainstorm `## Domain Assessments`. Brainstorm explicitly
skipped formal leader spawn given local-discovery clarity. CTO assessment
updated post-research to reflect existing-root finding.)

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** Indexing degradation is direct organic-discovery loss. Vector 1
recovers ~18 of 20 redirect-bucket entries via one config change; Vector 2
stabilizes the long tail of legacy URLs against meta-refresh non-determinism.

### Engineering (CTO)

**Status:** reviewed (carry-forward, updated post-research)
**Assessment:** Single new `.tf` file in the existing `apps/web-platform/infra/`
Terraform root. R2 backend already in place. Existing `cf_api_token_rulesets`
token scope expanded (no new alias / variable / Doppler key). No app-layer
code change.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Vector 3 (deploy.soleur.ai X-Robots-Tag) is the load-bearing
CLO concern. CLO sign-off required on the Transform Rule scope to ensure
no rule ordering issue interferes with CF Access enforcement. Not a
privacy-policy revision; no PII at risk in the 403 response.

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** No product-feature scope; this is publishing-surface hygiene.
CPO sign-off warranted at plan-time per `requires_cpo_signoff: true`,
specifically on Vector 3's Transform Rule scope (the user-brand-critical
surface).

### Product/UX Gate

**Tier:** none
**Decision:** auto-classified — no new files match `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`. Plan creates one `.tf` file. No
UI surface, no flow, no copy.

**Brainstorm-recommended specialists:** none.

## Non-Goals

1. **Migrating the docs site off GitHub Pages.** Cloudflare is in front of GH
   Pages; edge redirects work without changing host.
2. **Migrating `_data/blogRedirects.js` to Cloudflare 301s** in this PR.
   Tracked in Phase 5 follow-up. Same template non-determinism applies but no
   GSC critical-issue URLs match the blog date-prefix pattern in this snapshot.
3. **Deleting `page-redirects.njk` + `_data/pageRedirects.js`** in this PR.
   CF 301s coexist harmlessly (request-phase 301 fires before origin); deletion
   in follow-up after live verification removes the apply-failure rollback path.
4. **Removing `api.soleur.ai` or `deploy.soleur.ai` from public DNS.** Tunnel/
   Access architecture intentionally exposes these via CF proxy.
5. **Per-subdomain `robots.txt` body content.** `X-Robots-Tag` is the
   authoritative indexing control; `Disallow:` only blocks crawl. If CLO later
   requires belt-and-suspenders, follow-up (rejected as YAGNI in this scope).
6. **Implementing IndexNow / Google Indexing API** automation. GSC re-validation
   via Playwright MCP is sufficient.
7. **AI-engine optimization (AEO) tags.** Separate scope (`soleur:seo-aeo`).

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| New Terraform root at `apps/soleur-edge/infra/` | Splits zone ownership across two state files (provider conflict risk on shared `soleur.ai` zone). |
| Cloudflare Bulk Redirects (List resource) | 19 entries fit Single Redirects; Bulk Redirects requires List management overhead. |
| New `cloudflare.transforms` provider alias + `cf_api_token_transforms` token | Same blast radius as existing `cf_api_token_rulesets` (zone-scoped rule writes). One token / one alias is simpler. |
| Per-subdomain `robots.txt` body (CF Worker / static file + 301) | Belt-and-suspenders on a noindex header. `X-Robots-Tag` is authoritative for indexing. Cut for YAGNI. |
| Eleventy-native (just fix the missing entry) | Doesn't address Google's classification non-determinism (4 entries in "crawled-not-indexed" are also meta-refresh casualties). |
| Apex as canonical (redirect www→apex) | Requires Cloudflare DNS flip + breaks existing OG/Discord embeds. Live infra already 301s the other direction; align build to deploy. |
| Delete meta-refresh files in this PR | Creates window where docs deploy can land before `terraform apply`, leaving URLs as 404 until apply completes. Defer to follow-up issue. |
| Migrate blog redirects in this PR | `blogRedirects.js` is build-time computed from blog file slugs — different architecture (HCL `locals` from `git ls-files`, or build-time JSON export). Warrants its own scoping. |

## Issue Update on Plan Exit

After plan finalization, update issue `#3297` body to link the plan and tasks
files (append below the existing Acceptance Criteria block):
- `Plan: knowledge-base/project/plans/2026-05-05-feat-gsc-indexing-fixes-plan.md`
- `Tasks: knowledge-base/project/specs/feat-seo-gsc-indexing-fixes/tasks.md`
