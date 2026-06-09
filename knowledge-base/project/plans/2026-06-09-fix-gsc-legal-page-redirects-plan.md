---
title: "Fix GSC Crawled-not-indexed for stale /pages/legal/*.html URLs via Cloudflare Bulk Redirects"
type: fix
date: 2026-06-09
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: all infrastructure (Bulk Redirect list + ruleset) is routed
     through Terraform and the existing automated apply-web-platform-infra.yml workflow.
     The sole residual operator step is Cloudflare API-TOKEN PERMISSION editing, which
     has no Terraform-managed resource in this repo (the token value lives in Doppler;
     its permission grants are operator-edited via the Cloudflare API/token surface).
     It is conditional (only if Phase 0 finds the token under-scoped) and flagged BLOCKING
     in the PR body, not a silent TODO. This is the genuinely-required manual carve-out. -->

# Fix GSC "Crawled - currently not indexed" for soleur.ai stale legal-page URLs

## Enhancement Summary

**Deepened on:** 2026-06-09
**Sections enhanced:** Implementation Phase 2 (v4 HCL grounding), Risk Analysis (precedent-diff).
**Method:** local research (no nested Task agents available inside the plan/deepen subagent — direct
tool use: repo greps, context7 Terraform provider docs, Cloudflare docs MCP, WebFetch). Halt-gates 4.6
(User-Brand Impact), 4.7 (Observability), 4.8 (PAT-shaped), 4.9 (UI-wireframe) all PASS.

### Key Improvements
1. **Grounded the v4 HCL block shape against repo precedent** (`cache.tf` ruleset + `tunnel.tf` account-level
   resources) — context7 returns `main`/v5 examples by default; the v5-upgrade guide explicitly lists
   `from_list`/`action_parameters`/`rules` as moved-to-attributes IN v5, confirming v4 uses BLOCKS.
2. **Precedent-diff added** (Phase 4.4 gate): no in-repo Bulk-Redirects precedent — pattern is NOVEL; the
   closest shapes are the zone ruleset (`cache.tf`) and account-level resources (`tunnel.tf`). `terraform
   validate` is the load-bearing catch.
3. **Verify-the-negative pass** confirmed the plan's constraint claims ("Rule 10 cannot be evicted", "do NOT
   touch seo_page_redirects") are respected by the diff shape — the plan adds a new file and a new phase, so
   no contradiction with the protected HTTPS catch-all.

### New Considerations Discovered
- The `cloudflare_list` `items` vs `item {}` form is the single sharpest v4/v5 trap; the repo precedent
  (`cache.tf` rules-as-blocks) is the authority, NOT context7's default page.
- The account-level ruleset needs `account_id`, not `zone_id` (unlike every existing `cloudflare_ruleset` in
  the repo, which is zone-scoped) — confirm the provider alias's token carries account scope (Phase 0.3).

## Overview

Nine legacy `/pages/legal/<slug>.html` URLs on soleur.ai (the Eleventy docs site at
`plugins/soleur/docs/`, served on the apex behind GitHub Pages + Cloudflare) have **no HTTP 301**
to their clean `/legal/<slug>/` equivalents. They are served the meta-refresh fallback HTML
(`plugins/soleur/docs/page-redirects.njk`, HTTP 200), which Google Search Console classifies as
"Crawled - currently not indexed". This plan adds edge 301s for all nine legal slugs (plus the
`terms-of-service.html → terms-and-conditions/` rename alias) using a **Cloudflare Bulk Redirects
list** — a Free-tier product that is NOT subject to the 10-rule-per-phase dynamic-redirect cap that
forced these nine to be deferred — and adds `<meta name="robots" content="noindex">` to the
meta-refresh fallback as a defensive interim so the HTTP-200 fallback can never leak into the index.

Post-merge, the Cloudflare ruleset apply is **automated** by `.github/workflows/apply-web-platform-infra.yml`
(triggers on `push` to `main` touching `apps/web-platform/infra/**`). The new Terraform resources MUST
be added to that workflow's `-target=` allow-list, or they silently never apply.

## Problem Statement

GSC drilldown export (`/home/jean/Downloads/soleur.ai-Coverage-Drilldown-2026-06-09/Table.csv`,
6 URLs flagged). Only **3** are actionable; the other 3 are confirmed non-issues:

| Flagged URL | Status | Action |
|---|---|---|
| `https://soleur.ai/pages/legal/cookie-policy.html` | No 301 → meta-refresh 200 | **FIX** |
| `https://www.soleur.ai/pages/legal/cookie-policy.html` | No 301 → meta-refresh 200 | **FIX** |
| `https://www.soleur.ai/legal/data-protection-disclosure/` | Clean URL (www variant) — collapses to apex once the `/pages/legal/*` 301 fires; the www→apex canonicalizer already handles it | **FIX (covered by the legal redirects landing apex-ward)** |
| `https://www.soleur.ai/pages/changelog.html` | Already 301s via existing `cloudflare_ruleset.seo_page_redirects` rule (`seo-rulesets.tf:194-208`) | Non-issue — do NOT touch |
| `https://soleur.ai/blog/case-study-brand-guide-creation/` | Healthy 200; Google lag, self-resolves | Non-issue — do NOT touch |
| `https://www.soleur.ai/blog/feed.xml` | Correctly `noindex`'d via `seo_response_headers` rule (`seo-rulesets.tf:375-392`) | Non-issue — working as intended |

The actionable set is the **9 `/pages/legal/<slug>.html` legal pages** that have no edge 301. The two
`cookie-policy.html` rows are representative; the same gap applies to all nine legal slugs.

## Research Reconciliation — Feature Description vs. Codebase

The one-shot feature description prescribed an approach (regex/wildcard consolidation of per-slug
dynamic-redirect rules via `regex_replace()`) that is **blocked by a documented, hard Cloudflare
constraint**. This section reconciles the prescribed approach against verified codebase + vendor reality.
**The plan deliberately diverges from the prescribed mechanism — and the divergence is the whole point.**

| Feature-description claim | Verified reality | Plan response |
|---|---|---|
| "Consolidate per-slug rules into wildcard/regex via `http.request.uri.path matches` + `regex_replace()` target" | `seo-rulesets.tf:48-51` documents (from PR #3296 apply): **"`regex_replace()` in `target_url.expression` requires Business or WAF Advanced (cannot be used to consolidate)."** `regex_replace()` is a PAID-tier feature. The prescribed mechanism violates the "no paid upgrade" constraint. | **Reject `regex_replace()` consolidation.** Use Cloudflare **Bulk Redirects** (`cloudflare_list` kind `"redirect"` + account-level `cloudflare_ruleset` phase `http_request_redirect` with a `from_list` action) — a separate Free-tier product, exact-match (no regex needed because every legal slug maps clean→clean), NOT subject to the 10-rule dynamic-redirect cap. This is the documented intended fix (`seo-rulesets.tf:59-66`, follow-up #3328) and is named in the test guard itself (`seo-rulesets-noindex.test.ts:19` — "a Bulk-Redirects consolidation"). |
| "all 10 slots are consumed by individual per-slug `/pages/<slug>.html` rules" | The 10 dynamic-redirect slots are: 8 generic page redirects, 1 `terms-of-service → terms-and-conditions` rename, and **1 load-bearing HTTPS catch-all** (Rule 10, `seo-rulesets.tf:255-269`) that upgrades every proxied host to HTTPS and carves out the Let's Encrypt ACME challenge. That rule protects cross-subdomain credentials (Supabase tokens, CF Access service-token) from wire leakage (user-impact-reviewer, PR #3974) and **cannot be evicted**. | Do NOT touch the 10-rule `seo_page_redirects` ruleset (no slot reclamation needed — Bulk Redirects is a separate quota). The 9 legal redirects land entirely in the new Bulk Redirect list. |
| "regex wildcard `/pages/legal/*.html → /legal/$1/` with terms exception higher-priority" | Every legal slug maps clean-slug == clean-slug (verified below), so a **regex is unnecessary** — exact source→target pairs suffice. The terms exception is a separate source path (`terms-of-service.html`, no matching source page) and is simply one more exact pair in the same list. | Encode all 10 pairs as exact `source_url`/`target_url` items in the Bulk Redirect list. No priority ordering needed — exact matches don't overlap. |

**Premise validation note:** All cited artifacts verified on the working tree (= `origin/main` baseline,
clean branch). `seo-rulesets.tf` and `page-redirects.njk` exist as described. Cited deferral comment is at
`seo-rulesets.tf:59-66` (description said "~59-66" — exact). Provider pinned `cloudflare/cloudflare 4.52.7`
(`~> 4.0`, `.terraform.lock.hcl`). No external GitHub issue/PR was cited as a blocker; the related
trackers (#3297 GSC feature, #3328 source-template deletion follow-up) are referenced for provenance only,
not validated as open/closed gates.

## Slug-mapping verification (exact source→target pairs)

All 9 legal source pages (`plugins/soleur/docs/pages/legal/*.md`) have `permalink: legal/<slug>/` matching
their filename slug (verified by reading each frontmatter). The `terms-of-service.html` alias has no source
page (legacy slug rename → `terms-and-conditions/`). The full Bulk Redirect item set (10 pairs):

| `source_url` (host-less path, apex) | `target_url` | Source page exists? |
|---|---|---|
| `soleur.ai/pages/legal/privacy-policy.html` | `https://soleur.ai/legal/privacy-policy/` | yes |
| `soleur.ai/pages/legal/cookie-policy.html` | `https://soleur.ai/legal/cookie-policy/` | yes |
| `soleur.ai/pages/legal/gdpr-policy.html` | `https://soleur.ai/legal/gdpr-policy/` | yes |
| `soleur.ai/pages/legal/acceptable-use-policy.html` | `https://soleur.ai/legal/acceptable-use-policy/` | yes |
| `soleur.ai/pages/legal/data-protection-disclosure.html` | `https://soleur.ai/legal/data-protection-disclosure/` | yes |
| `soleur.ai/pages/legal/individual-cla.html` | `https://soleur.ai/legal/individual-cla/` | yes |
| `soleur.ai/pages/legal/corporate-cla.html` | `https://soleur.ai/legal/corporate-cla/` | yes |
| `soleur.ai/pages/legal/disclaimer.html` | `https://soleur.ai/legal/disclaimer/` | yes |
| `soleur.ai/pages/legal/terms-and-conditions.html` | `https://soleur.ai/legal/terms-and-conditions/` | yes |
| `soleur.ai/pages/legal/terms-of-service.html` | `https://soleur.ai/legal/terms-and-conditions/` | **no (rename alias)** |

Source-page slug list cross-checked against `_data/pageRedirects.js:16-25` (existing meta-refresh map) —
exact match for the 9 real slugs + the terms-of-service alias at `:18`.

**`include_subdomains` covers the www variant.** The bulk redirect items use a host-less / apex `source_url`;
the matching www deep-links (e.g. `www.soleur.ai/pages/legal/cookie-policy.html`) are caught either by
`include_subdomains = true` on each item OR by the existing host-preserving www→apex GitHub-Pages canonicalizer
firing in sequence — **verify which during /work** (curl both apex and www forms). The targets are apex
literals because the live edge is apex-canonical post-#4577 (`seo-rulesets.tf:14-23`).

## Proposed Solution

1. **New Terraform file `apps/web-platform/infra/seo-bulk-redirects.tf`** (prefer a new file for a clean diff
   and to avoid churning the destroy-guard-sensitive existing ruleset):
   - `resource "cloudflare_list" "legal_redirects"` — `account_id = var.cf_account_id`, `kind = "redirect"`,
     with 10 `item { value { redirect { source_url = "...", target_url = "...", status_code = 301,
     preserve_query_string = true } } }` blocks (v4 BLOCK syntax — see Sharp Edges).
   - `resource "cloudflare_ruleset" "bulk_redirects"` — `account_id = var.cf_account_id`, `kind = "root"`,
     `phase = "http_request_redirect"`, one rule with `action = "redirect"` and
     `action_parameters { from_list { name = cloudflare_list.legal_redirects.name, key = "http.request.full_uri" } }`.
2. **Token scope** — `cf_api_token_rulesets` is zone-scoped (`variables.tf:74-75`). Bulk Redirects need
   **Account-level** permissions (`Account Rulesets:Edit` + `Account Filter Lists:Edit`). Determine at /work
   whether the existing token already carries these or whether the token must be widened (one operator step —
   flag in PR body, see Apply Path).
3. **`<meta name="robots" content="noindex">`** added to `plugins/soleur/docs/page-redirects.njk` (one line
   in `<head>`) as defensive interim so the HTTP-200 meta-refresh fallback never indexes even before/if the
   edge 301 is missed. The meta-refresh template and `_data/pageRedirects.js` are **kept** (load-bearing for
   the `terms-of-service` stub test guard at `seo-aeo-drift-guard.test.ts:464-467`; deletion stays deferred to #3328).
4. **Allow-list extension** — add the two new resources to `apply-web-platform-infra.yml`'s plan `-target=` list.
5. **Validate** with `terraform fmt` / `terraform validate` / `terraform plan`, and rebuild the Eleventy site
   to confirm the redirect template still renders with the new noindex meta.

## Technical Approach

### Architecture

```
                 Googlebot / user
                       |
                       v
   +-----------------------------------------------+
   | Cloudflare edge (soleur.ai zone, apex proxied)|
   |                                               |
   |  Phase http_request_redirect (ACCOUNT ruleset)|  <- NEW (Bulk Redirects)
   |    rule: redirect from_list "legal_redirects" |
   |      key = http.request.full_uri              |
   |      -> 301 to clean /legal/<slug>/           |
   |                                               |
   |  Phase http_request_dynamic_redirect (ZONE)   |  <- UNCHANGED (10/10 slots)
   |    8 page redirects + terms rename + HTTPS rule|
   +-----------------------------------------------+
                       | (no match -> origin)
                       v
                 GitHub Pages origin
              (meta-refresh stub, now noindex'd)
```

Both redirect phases run **before** origin fetch, so the 301 fires regardless of what GitHub Pages emits.
The Bulk Redirect (account `http_request_redirect`) and the existing zone `http_request_dynamic_redirect` are
**different phases** with independent quotas — no slot contention.

### Implementation Phases

#### Phase 0 — Preconditions (verify before writing HCL)

- [ ] Confirm provider pin: `grep version apps/web-platform/infra/.terraform.lock.hcl` → `4.52.7`. **All HCL
      uses v4 block syntax.**
- [ ] Read `apps/web-platform/infra/tunnel.tf` for the exact `cloudflare_ruleset` v4 block shape already in use
      with `account_id` (structural template alongside `cache.tf` for nested-block ruleset rules).
- [ ] Determine Bulk Redirects token scope: check whether `cf_api_token_rulesets` carries account-level
      `Account Rulesets:Edit` + list permissions. If not, this is the one operator-gated step (Cloudflare
      token-permission edit) — see Apply Path / Risks.
- [ ] `git grep -n "cf_account_id" apps/web-platform/infra/*.tf` confirms the var is wired (used in `tunnel.tf:11`).

#### Phase 1 — Eleventy fallback noindex (RED → GREEN, cheapest, independently shippable)

- [ ] Add a failing test to `plugins/soleur/test/seo-aeo-drift-guard.test.ts`: every rendered meta-refresh
      stub under `_site/pages/**` contains `<meta name="robots" content="noindex">`. Walk the dir (do NOT
      hardcode a file list — directory walk per the source-template-drift-guard convention). Assert ≥1 stub found.
- [ ] Edit `plugins/soleur/docs/page-redirects.njk`: add `<meta name="robots" content="noindex">` inside `<head>`,
      adjacent to the existing `<meta http-equiv="refresh">`.
- [ ] Rebuild: `npm run docs:build` (= `npx @11ty/eleventy` from repo root). Confirm stubs render with both
      metas and stay `< 2000` bytes (the existing `http-equiv="refresh"` size-gated detection at
      `seo-aeo-drift-guard.test.ts:220,237,531,1116` must still fire — adding one `<meta>` line keeps stubs tiny).
- [ ] Confirm the `terms-of-service` stub guard still passes (`seo-aeo-drift-guard.test.ts:464-467` — stub still
      contains `/legal/terms-and-conditions/`).

#### Phase 2 — Cloudflare Bulk Redirects Terraform (v4)

- [ ] Create `apps/web-platform/infra/seo-bulk-redirects.tf` with `cloudflare_list.legal_redirects` (10 redirect
      items, v4 `item { value { redirect { ... } } }` blocks) + `cloudflare_ruleset.bulk_redirects` (account-level,
      `http_request_redirect`, `from_list` action). Provider alias: use `cloudflare.rulesets` (same alias as
      `seo_page_redirects`) if its token scope covers account rulesets; otherwise document the token-widening
      requirement. Header comment cross-references this plan, #3297, #3328, and `seo-rulesets.tf:59-66`.
- [ ] `cd apps/web-platform/infra && terraform fmt && terraform validate` (Doppler-injected, per the canonical
      triplet below). `validate` is the load-bearing catch for v4-vs-v5 schema drift.
- [ ] `terraform plan` (target-scoped to the two new resources) to confirm 2 resources to add, 0 to change,
      0 to destroy. Attach plan output to PR body.

### Research Insights (v4 HCL — copy-ready shape, verify with `terraform validate`)

**Precedent-diff (Phase 4.4):** No in-repo `cloudflare_list` / `http_request_redirect` precedent exists
(`dns.tf:209-210`). Pattern is **NOVEL**. Closest sibling shapes, read directly from the repo (the authority
over context7, which defaults to v5):
- `cache.tf` `cloudflare_ruleset.cache_shared_binaries` — v4 nested-BLOCK form: `rules { action = "...";
  action_parameters { ... } }` (repeated blocks, NOT `rules = [ {…} ]` lists-of-objects). Uses
  `provider = cloudflare.rulesets`, `zone_id`, `kind = "zone"`.
- `tunnel.tf` — the repo's only `account_id`-scoped Cloudflare resources (template for `account_id =
  var.cf_account_id`).

The new ruleset differs from every existing one in the repo on TWO axes: `account_id` (not `zone_id`) and
`kind = "root"` at account level. That is exactly why the token-scope check (Phase 0.3) is load-bearing.

**v4-vs-v5 confirmation:** the Cloudflare provider v5-upgrade guide explicitly lists `from_list`,
`action_parameters`, and `rules` among attributes that moved from "multiple blocks" → "single nested
attributes / lists of objects" IN v5. Our pin is `4.52.7` → **BLOCK form**. context7's default
(`/cloudflare/terraform-provider-cloudflare` `main`) returns the v5 attribute/`items`-set shape — do NOT copy
it. Cross-check any context7 snippet against `cache.tf` before adopting.

**Sketch (v4 block syntax — confirm each attribute name via `terraform validate`):**

```hcl
# apps/web-platform/infra/seo-bulk-redirects.tf
resource "cloudflare_list" "legal_redirects" {
  provider    = cloudflare.rulesets   # confirm token carries Account Filter Lists:Edit (Phase 0.3)
  account_id  = var.cf_account_id
  name        = "legal_redirects"     # referenced by name from the ruleset's from_list
  kind        = "redirect"
  description = "Legacy /pages/legal/*.html -> clean /legal/<slug>/ 301s. See plan 2026-06-09, #3297, #3328."

  # One item {} block per pair (10 total). v4 uses item { value { redirect {} } } blocks.
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/cookie-policy.html"
        target_url            = "https://soleur.ai/legal/cookie-policy/"
        status_code           = 301
        preserve_query_string = true
        # include_subdomains   = true   # EVALUATE in Phase 0/curl: covers www.* deep-links if the
                                         # existing www->apex canonicalizer doesn't already collapse them
      }
    }
  }
  # ... 9 more item {} blocks (8 remaining legal slugs + terms-of-service alias) ...
}

resource "cloudflare_ruleset" "bulk_redirects" {
  provider    = cloudflare.rulesets
  account_id  = var.cf_account_id     # ACCOUNT-level (not zone_id) — the novel axis
  name        = "Legal page bulk redirects"
  description = "Account http_request_redirect ruleset bound to the legal_redirects list. See plan 2026-06-09."
  kind        = "root"
  phase       = "http_request_redirect"

  rules {
    action      = "redirect"
    description = "301 legacy /pages/legal/*.html via the legal_redirects bulk list"
    enabled     = true
    expression  = "http.request.full_uri in $legal_redirects"   # confirm the $list-reference form for v4
    action_parameters {
      from_list {
        name = "legal_redirects"
        key  = "http.request.full_uri"
      }
    }
  }
}
```

> **Two details most likely wrong (Sharp Edges):** (1) the rule `expression` form for a Bulk Redirect — CF
> may auto-generate it or require `http.request.full_uri in $<list>`; (2) the `source_url` host-format
> (host-less `soleur.ai/path` vs full `https://soleur.ai/path`). `terraform validate` catches attribute-name
> errors; only a live `terraform plan` + post-apply curl catches the expression/host-format semantics. Verify
> both against the current Cloudflare Bulk Redirects docs at /work and curl apex AND www before declaring done.

#### Phase 3 — Apply-workflow allow-list extension

- [ ] Edit `.github/workflows/apply-web-platform-infra.yml`: append
      `-target=cloudflare_list.legal_redirects` and `-target=cloudflare_ruleset.bulk_redirects` to the
      `terraform plan` `-target=` list (after `seo_response_headers` at line ~278). This is mandatory — without
      it, the new resources never apply and surface only in the 12h drift detector (`scheduled-terraform-drift.yml`).
- [ ] Check whether `scheduled-terraform-drift.yml` carries its own `-target=` allow-list that also needs the
      two new addresses (`git grep -n "seo_page_redirects" .github/workflows/`). Add them there too if present.

#### Phase 4 — Validate, push, PR, post-merge verify

- [ ] Run the three SEO/drift test suites: `apps/web-platform/test/seo-rulesets-noindex.test.ts`,
      `plugins/soleur/test/validate-seo.test.ts`, `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — all green.
- [ ] Open PR. Body splits AC into Pre-merge / Post-merge. Use `Ref #3297` and `Ref #3328` (NOT `Closes` —
      the fix is verified-live only after the automated apply runs; see ops-remediation Closes-vs-Ref convention).
- [ ] Post-merge: the apply workflow auto-fires. Verify (curl suite below). If the token-scope widening is
      required, that single operator step must complete BEFORE the apply can succeed — flag it as a blocking
      pre-apply step in the PR body, never a silent TODO.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| `regex_replace()` wildcard consolidation of dynamic-redirect rules (the feature-description's prescribed approach) | `regex_replace()` in `target_url.expression` requires **Cloudflare Business / WAF Advanced** (paid) — documented at `seo-rulesets.tf:48-51` from PR #3296. Violates the no-paid-upgrade constraint. |
| Evict the HTTPS catch-all (Rule 10) to free a dynamic-redirect slot | Rule 10 protects cross-subdomain credentials from wire leakage (PR #3974 user-impact-reviewer). Removing it re-opens a credential-leak window AND breaks Let's Encrypt ACME renewal. Non-starter. |
| Add 9 more individual `http.request.uri.path eq` rules to the existing zone ruleset | Free tier caps `http_request_dynamic_redirect` at **10 rules/phase**; all 10 are used. No room. |
| Delete the meta-refresh template + `pageRedirects.js` in this PR | Creates a window where docs deploy can run before the edge 301 applies, leaving URLs as 404; also breaks the `terms-of-service` stub test guard. Deletion stays deferred to #3328. |
| Single `cloudflare_list_item` resources instead of inline `item` blocks | v4 inline `item` blocks are simpler for a fixed 10-item set and atomic; per-item resources add 10 addresses to the allow-list. Inline preferred. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a legal page (e.g. Cookie Policy, Privacy Policy) reached
  via an old `/pages/legal/<slug>.html` link returns the bare meta-refresh interstitial or a 404 instead of
  cleanly 301-ing to the canonical `/legal/<slug>/` — a low-trust experience on legal/compliance pages, and
  the GSC "Crawled - not indexed" status persists (SEO-only, no data exposure).
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — this is public marketing/legal
  content served anonymously on the apex docs site. No authenticated surface, no user data, no secrets in the
  redirect config. The one credential-adjacent surface (the HTTPS catch-all Rule 10) is explicitly **not
  touched** by this plan.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the diff touches apps/web-platform/infra (a sensitive path
per preflight Check 6) but only adds anonymous public-content edge 301s + a static account-scoped redirect
list; it touches no auth flow, no schema, no secret value, and explicitly does not modify the
credential-protecting HTTPS catch-all rule.`

## Observability

```yaml
liveness_signal:
  what:            "Post-apply curl verification suite (Phase 4) — 301 + correct Location on each /pages/legal/*.html; backstopped by GSC re-validation in Search Console"
  cadence:         "per-apply (on merge); GSC recrawl over days"
  alert_target:    "apply-web-platform-infra.yml job status (GitHub Actions) + operator GSC dashboard"
  configured_in:   ".github/workflows/apply-web-platform-infra.yml (Post-apply summary step, ~line 558); apps/web-platform/infra/seo-bulk-redirects.tf"
error_reporting:
  destination:     "GitHub Actions run failure on apply-web-platform-infra.yml (terraform plan/apply non-zero exit fails the job loudly); scheduled-terraform-drift.yml 12h backstop surfaces un-applied resources"
  fail_loud:       "terraform apply step exits non-zero, job red; drift detector files an issue if the two new resources are missing from live state"
failure_modes:
  - mode:          "New resources omitted from apply-workflow -target= allow-list, never applied"
    detection:     "scheduled-terraform-drift.yml next cron run (<=12h) shows the two resources as to-create drift"
    alert_route:   "drift-detector auto-filed GitHub issue"
  - mode:          "Token lacks account-level Bulk Redirects scope, apply fails with CF 403/authz error"
    detection:     "terraform apply step exits non-zero in apply-web-platform-infra.yml"
    alert_route:   "GitHub Actions job failure (red check on merge)"
  - mode:          "Wrong-destination 301 (slug typo), user lands on 404"
    detection:     "Phase 4 post-apply curl suite asserts exact Location per slug"
    alert_route:   "operator curl-suite verification (load-bearing, in PR post-merge checklist)"
logs:
  where:           "GitHub Actions run logs for apply-web-platform-infra.yml; Cloudflare Rules > Bulk Redirects live state"
  retention:       "GH Actions default (90 days); Cloudflare config persistent"
discoverability_test:
  command:         'curl -sIA "Googlebot" https://soleur.ai/pages/legal/cookie-policy.html | grep -iE "^(HTTP|location)"'
  expected_output: "HTTP/2 301 and location: https://soleur.ai/legal/cookie-policy/"
```

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements
- [ ] `apps/web-platform/infra/seo-bulk-redirects.tf` declares `cloudflare_list.legal_redirects`
      (`kind = "redirect"`, `account_id = var.cf_account_id`) with exactly 10 redirect items matching the
      slug-mapping table (9 legal slugs + terms-of-service alias), all `status_code = 301`.
- [ ] The file declares `cloudflare_ruleset.bulk_redirects` (account-level, `kind = "root"`,
      `phase = "http_request_redirect"`) with a single `from_list` redirect rule referencing the list by name.
- [ ] All HCL uses **v4 block syntax** (`item { value { redirect { ... } } }`, `from_list { name=… key=… }` as
      blocks, NOT v5 attribute-map/list-of-objects).
- [ ] `plugins/soleur/docs/page-redirects.njk` contains `<meta name="robots" content="noindex">` in `<head>`.
- [ ] `_data/pageRedirects.js` and `page-redirects.njk` are **retained** (not deleted).
- [ ] `apply-web-platform-infra.yml` plan `-target=` list includes both new resource addresses.

#### Quality Gates
- [ ] `cd apps/web-platform/infra && terraform fmt -check && terraform validate` passes (Doppler-injected).
- [ ] `terraform plan` (target-scoped) shows exactly **2 to add, 0 to change, 0 to destroy**; output pinned in PR body.
- [ ] `npm run docs:build` succeeds; rendered `_site/pages/legal/*.html` stubs contain both
      `http-equiv="refresh"` and `name="robots" content="noindex"`, and remain `< 2000` bytes.
- [ ] All three SEO test suites green: `seo-rulesets-noindex.test.ts`, `validate-seo.test.ts`,
      `seo-aeo-drift-guard.test.ts` (including the new noindex-on-stub assertion).
- [ ] PR body uses `Ref #3297` / `Ref #3328` (not `Closes`), and splits AC into Pre-merge / Post-merge.

### Post-merge (operator / automated)
- [ ] **(Operator, only if Phase 0 finds the token lacks account scope — BLOCKING pre-apply)** Widen
      `cf_api_token_rulesets` (or mint/scope the appropriate token) to include `Account Rulesets:Edit` +
      `Account Filter Lists:Edit` via the Cloudflare API token-permissions surface; update Doppler
      `prd_terraform` if the value rotates. *Automation: not feasible — Cloudflare API-token permission
      editing is an operator/OAuth-gated action with no Terraform-managed path in this repo.* This MUST
      complete before the auto-apply can succeed; flag it explicitly in the PR body, never as a silent TODO.
- [ ] **(Automated)** `apply-web-platform-infra.yml` fires on merge and applies the two new resources
      (verify the run is green; if token-scope step was needed, re-run via `gh workflow run
      apply-web-platform-infra.yml --ref main -F reason='bulk-redirects apply after token widen'`).
- [ ] **(Operator curl suite — load-bearing)** Each `/pages/legal/<slug>.html` (apex + www) returns
      `301` with the exact `Location` from the slug table; `terms-of-service.html` → `/legal/terms-and-conditions/`.
- [ ] **(Operator)** GSC URL Inspection / re-validation requested for the 9 legal URLs; `gh issue` notes added
      to #3297 referencing the live-verified 301s.

## Test Scenarios

### Acceptance Tests (RED targets)
- Given the rendered docs site, when reading any `_site/pages/**/*.html` meta-refresh stub, then it contains
  `<meta name="robots" content="noindex">`. (New test in `seo-aeo-drift-guard.test.ts`.)
- Given `seo-bulk-redirects.tf`, when running `terraform validate` under the v4 provider, then it passes
  (proves v4 block syntax is correct).

### Regression
- Given the rendered `pages/legal/terms-of-service.html` stub, when read, then it still contains
  `/legal/terms-and-conditions/` (`seo-aeo-drift-guard.test.ts:464-467` unaffected).
- Given `validate-seo.test.ts`, when run, then redirect stubs still never appear in the sitemap and the
  size-gated `http-equiv="refresh"` detection still fires.

### Integration Verification (for /soleur:qa, post-merge)
- **API verify (apex):** `curl -sIA "Googlebot" https://soleur.ai/pages/legal/cookie-policy.html | grep -i location`
  expects `location: https://soleur.ai/legal/cookie-policy/`.
- **API verify (www variant):** `curl -sIA "Googlebot" https://www.soleur.ai/pages/legal/cookie-policy.html`
  expects a 301 chain resolving to `https://soleur.ai/legal/cookie-policy/` (confirms `include_subdomains` /
  www→apex canonicalizer coverage).
- **API verify (terms alias):** `curl -sIA "Googlebot" https://soleur.ai/pages/legal/terms-of-service.html | grep -i location`
  expects `location: https://soleur.ai/legal/terms-and-conditions/`.
- **Negative control:** `curl -sIA "Googlebot" https://soleur.ai/pages/changelog.html | grep -i location`
  still expects `https://soleur.ai/changelog/` (existing rule untouched).

## Success Metrics

- All 9 `/pages/legal/<slug>.html` URLs return HTTP 301 (apex + www) within minutes of apply.
- GSC "Crawled - currently not indexed" count for the legal-path cluster drops to 0 over the next recrawl cycle.
- Zero regression on the 10 existing dynamic-redirect rules and the X-Robots-Tag rules.

## Dependencies & Risks

### Risk Analysis & Mitigation

- **v4-vs-v5 provider schema drift (HIGH likelihood, caught early).** Research/LLM/context7 default to v5
  schema (`items` attribute-set, single nested `redirect` attribute). Repo pins v4 (`4.52.7`) which uses
  repeated `item { value { redirect { ... } } }` blocks and block-style `from_list`/`action_parameters`.
  *Mitigation:* `terraform validate` immediately after writing the file. See learning
  `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` and `cache.tf` / `tunnel.tf` as v4 nested-block
  templates. Do NOT copy context7's `main`-branch (v5) examples verbatim.
- **Token scope gap (MEDIUM).** Bulk Redirects need account-level permissions the existing zone-scoped
  `cf_api_token_rulesets` may lack. *Mitigation:* Phase 0 determines this; if widening is needed it is the
  single operator pre-apply step, flagged BLOCKING in the PR body. The apply job fails loudly (red check) if
  the scope is missing — no silent partial state.
- **Apply-workflow allow-list omission (MEDIUM, self-healing).** The new resources must be in the `-target=`
  list. *Mitigation:* Phase 3 adds them; `scheduled-terraform-drift.yml` is the 12h backstop.
- **Account-level ruleset is a NOVEL pattern in this repo (MEDIUM).** `dns.tf:209-210` confirms no prior
  `cloudflare_list` / `http_request_redirect` resource exists. *Mitigation:* `terraform plan` against live
  state before merge; the deepen-plan precedent-diff gate (Phase 4.4) should diff against the closest sibling
  (`cache.tf` ruleset shape + `tunnel.tf` account_id usage) and note "no in-repo Bulk-Redirects precedent —
  pattern is novel; v4 schema verified against `4.52.7` via terraform validate."
- **`from_list` lookup key (MEDIUM).** The `key` expression must produce the value the list `source_url`
  matches against. Cloudflare matches `source_url` against the request URL; the rule `key` is typically
  `http.request.full_uri`. *Mitigation:* verify the exact `key` expression and `source_url` host-format
  (host-less vs full-URL) during /work against Cloudflare Bulk Redirects docs; curl-test apex AND www.
- **Destroy-guard interaction (LOW).** Adding (not removing) resources produces 0 destroys, so the
  `[ack-destroy]` gate in `apply-web-platform-infra.yml` is not triggered. Confirmed by the target-scoped plan.

### Dependencies & Prerequisites
- Cloudflare Bulk Redirects available on Free tier (separate quota from the 10-rule dynamic-redirect cap).
  *Verify the exact Free-tier list/redirect quota during /work* — WebFetch of the CF availability page was
  inconclusive at plan time (quota table behind a sub-page); 9 redirects is far below any documented tier limit.
- `var.cf_account_id` already defined and wired (`variables.tf:97`, used in `tunnel.tf`).
- `apply-web-platform-infra.yml` auto-apply workflow (already exists; `seo_page_redirects` already in its list).

## Documentation Plan

- Header comment in `seo-bulk-redirects.tf` cross-referencing this plan + #3297 + #3328 + `seo-rulesets.tf:59-66`
  (so a future reader sees the deferred-→-resolved arc).
- Update the deferral comment in `seo-rulesets.tf:59-66` to note the 9 legal redirects are now landed via
  the Bulk Redirect list (strike the "return 404 until a Bulk Redirects refactor lands" language). This is a
  technical-fact correction in the same file, not a strategy change.
- Capture a learning at `/compound` time if the v4 Bulk-Redirects HCL shape required non-obvious adjustments.

## References & Research

### Internal References
- `apps/web-platform/infra/seo-rulesets.tf:48-66` — the 10-rule cap, the `regex_replace()` paid-tier
  constraint, and the deferred-9-legal-redirects comment (the root cause).
- `apps/web-platform/infra/seo-rulesets.tf:255-269` — load-bearing HTTPS catch-all (Rule 10, do not touch).
- `apps/web-platform/infra/variables.tf:74-75,97` — `cf_api_token_rulesets` scope + `cf_account_id`.
- `apps/web-platform/infra/.terraform.lock.hcl` — provider `cloudflare/cloudflare 4.52.7`.
- `apps/web-platform/infra/dns.tf:209-210` — confirms no prior `cloudflare_list` / `http_request_redirect`.
- `apps/web-platform/infra/cache.tf`, `tunnel.tf` — v4 nested-block ruleset + `account_id` templates.
- `.github/workflows/apply-web-platform-infra.yml:264-346` — the `-target=` allow-list (auto-apply on merge).
- `plugins/soleur/docs/page-redirects.njk`, `_data/pageRedirects.js:16-25` — meta-refresh fallback + map.
- `plugins/soleur/docs/pages/legal/*.md` — 9 legal source pages (permalinks verified).
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts:220,237,464-467,531,1116` — stub-detection + terms guard.
- `apps/web-platform/test/seo-rulesets-noindex.test.ts:19-21` — names "a Bulk-Redirects consolidation" as the
  anticipated refactor.
- `knowledge-base/project/plans/2026-05-05-feat-gsc-indexing-fixes-plan.md` — prior GSC plan (apply/verify pattern).
- `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` — v4/v5 schema drift.
- `knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md` — GSC bucket triage.
- `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` —
  canonical Doppler+terraform invocation triplet for `prd_terraform`.

### External References
- Cloudflare Bulk Redirects: https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/
  (essentially static, exact-match, no regex — confirmed; per-plan availability behind sub-page).
- Terraform `cloudflare_list` (v4): https://registry.terraform.io/providers/cloudflare/cloudflare/4.52.7/docs/resources/list
  (`kind = "redirect"`, item/value/redirect block syntax — verify v4 page, NOT `latest`/v5).
- Terraform `cloudflare_ruleset` `http_request_redirect` + `from_list` action (v4 docs).

### Related Work
- Ref #3297 (GSC indexing fixes feature), #3328 (meta-refresh source-template deletion follow-up),
  #3296 (the apply that discovered the regex_replace paid-tier constraint), #3974 (HTTPS catch-all rationale),
  #4577 (apex-canonical reconcile).

## Sharp Edges

- **v4 block syntax is non-negotiable.** context7 and the Terraform Registry `latest` page show v5
  (`items`/attribute-map). The repo is `4.52.7`. Use `item { value { redirect { source_url = ...,
  target_url = ..., status_code = 301, preserve_query_string = true } } }` blocks and block-style
  `action_parameters { from_list { name = ..., key = ... } }`. `terraform validate` is the catch.
- **The `source_url` host-format and the rule `key` expression are the two details most likely to be wrong.**
  Verify against CF Bulk Redirects docs at /work and curl-test both apex and www before declaring done.
- **Do NOT delete `page-redirects.njk` / `pageRedirects.js`** — the `terms-of-service` stub test guard depends
  on the meta-refresh stub being generated. Deletion stays deferred to #3328.
- **Do NOT touch `cloudflare_ruleset.seo_page_redirects` Rule 10 (HTTPS catch-all)** — credential-leak +
  ACME-renewal protection.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this
  section is filled with threshold `none` + a sensitive-path scope-out reason.

## Open Code-Review Overlap

None — checked after Files-to-Edit was finalized; `gh issue list --label code-review --state open` query to be
run at /work-time against the final file list (`seo-bulk-redirects.tf`, `seo-rulesets.tf`, `page-redirects.njk`,
`apply-web-platform-infra.yml`, `seo-aeo-drift-guard.test.ts`). No open scope-out is known to touch these paths.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure / SEO-hygiene change. Mechanical UI-surface override
did NOT fire: Files-to-Edit are `.tf` (edge config), `.yml` (CI workflow), `.test.ts` (test guard), and
`page-redirects.njk` (a meta-refresh HTTP-200 stub template — not a user-facing page/component; no
`components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`). Product domain → NONE. The change
touches legal *page redirects* but no legal *document content*, so no CLO review is needed.

## GDPR / Compliance Gate

Skipped — no regulated-data surface. The diff touches no schema/migration/`.sql`, no auth flow, no API route
handling personal data; the redirect config moves anonymous public legal-page URLs only. None of the
expanded (a)-(d) triggers fire (no LLM/external-API processing of operator data, threshold is `none`, no new
cron reading learnings/specs, no new artifact distribution surface).

## Infrastructure (IaC)

### Terraform changes
- New file `apps/web-platform/infra/seo-bulk-redirects.tf`: `cloudflare_list.legal_redirects` +
  `cloudflare_ruleset.bulk_redirects`. Provider `cloudflare/cloudflare ~> 4.0` (4.52.7), alias
  `cloudflare.rulesets` (or the account-scoped token alias if widening is required).
- Sensitive inputs: `var.cf_api_token_rulesets` (Doppler `prd_terraform`, may need account-scope widening),
  `var.cf_account_id`, `var.cf_zone_id` — all already wired.
- Edit `seo-rulesets.tf:59-66` deferral comment (technical-fact correction).
- Edit `.github/workflows/apply-web-platform-infra.yml` `-target=` list.

### Apply path
- This is an edge-config resource, not a host — cloud-init is N/A. Apply path is the existing automated
  `apply-web-platform-infra.yml` (push to `main` → target-scoped `terraform apply`). Zero downtime; blast
  radius = the soleur.ai zone's redirect phase only. The PR merge IS the human authorization
  (`hr-menu-option-ack-not-prod-write-auth`). The ONE possible operator pre-step is the Cloudflare token-scope
  widening (if Phase 0 finds it necessary) — operator-gated, no Terraform path, flagged BLOCKING in the PR body.

### Distinctness / drift safeguards
- New resources MUST be in `apply-web-platform-infra.yml` AND (if present) `scheduled-terraform-drift.yml`
  `-target=` lists. Adding-only → 0 destroys → no `[ack-destroy]` gate. R2 backend state, no state lock —
  the shared GH Actions concurrency group `terraform-apply-web-platform-host` is the serializer (unchanged).

### Vendor-tier reality check
- Bulk Redirects is Free-tier-available and a separate quota from the 10-rule dynamic-redirect cap (the entire
  premise of this plan). 9 redirects is far below any documented per-tier list/redirect limit. Confirm the exact
  Free-tier quota at /work; no paid `count = var.paid_tier ? 1 : 0` gate is anticipated.
