---
title: "fix(seo): X-Robots-Tag noindex on app.soleur.ai + allow Googlebot crawl to clear GSC 'Indexed, though blocked by robots.txt'"
type: fix
date: 2026-06-14
branch: feat-one-shot-gsc-app-noindex
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(seo): X-Robots-Tag noindex on app.soleur.ai + allow Googlebot crawl 🐛

## Summary

Google Search Console reports **"Indexed, though blocked by robots.txt"** for `https://app.soleur.ai/` (1 affected page, first detected 2026-06-06, non-critical). `app.soleur.ai` serves `robots.txt` with a blanket `Disallow: /` (via `apps/web-platform/app/robots.ts`). robots.txt blocks *crawling* but NOT *indexing* — Google indexed the bare URL anyway, and the crawl-block now **prevents Google from ever seeing a `noindex` directive**, so the URL cannot be removed from the index.

The **intent is correct** (`app.soleur.ai` is the login-gated product surface and must never be indexed); only the **mechanism is wrong**. The fix follows Google's documented removal method: a page must be **crawlable AND carry `noindex`** to be dropped from the index.

**Two changes, applied together:**
1. **Add a host-wide `X-Robots-Tag: noindex, nofollow` response header on ALL `app.soleur.ai` responses** via a new rule in the existing `cloudflare_ruleset.seo_response_headers` (Cloudflare edge Transform Rule, `apps/web-platform/infra/seo-rulesets.tf`).
2. **Change `apps/web-platform/app/robots.ts`** so Googlebot is allowed to crawl `/` and `/login` (drop the blanket `Disallow: /`), so it can fetch the page, see the `noindex` header, and drop the URL.

## Mechanism decision (IMPORTANT — diverges from the one-shot ARGUMENTS' first suggestion)

The task ARGUMENTS suggested adding the header via `next.config.ts headers()` / `middleware.ts` / `lib/security-headers.ts` (origin code). **Research reconciliation chose the Cloudflare edge Transform Rule instead**, because the repo already has a canonical, CI-guarded, auto-applied mechanism for exactly this surface class (`X-Robots-Tag` noindex on non-public hosts), and it is strictly more robust:

| Axis | Origin code (`security-headers.ts` / `next.config.ts headers()`) | **Cloudflare Transform Rule (chosen)** |
|---|---|---|
| Covers the 307→/login redirect | ⚠️ Unreliable — Next.js `headers()` does NOT reliably apply to middleware-generated `NextResponse.redirect()`; precedent: `/robots.txt` was shadowed by the same middleware 307 until added to `PUBLIC_PATHS` | ✅ Fires at the edge on **every** response (200, 307, 403, error) regardless of Next.js route execution |
| Repo precedent | none for app host | ✅ `deploy.soleur.ai` + `api.soleur.ai` rules already live in `seo_response_headers` (PR #3296/#3297, guarded by `test/seo-rulesets-noindex.test.ts` #4575) |
| Operator steps | none (code merge) | ✅ none — `cloudflare_ruleset.seo_response_headers` is already in the `-target=` allow-list of `apply-web-platform-infra.yml` (line ~278), so it auto-applies on merge |
| `app.soleur.ai` proxied? | n/a | ✅ `cloudflare_record.app` has `proxied = true` (`dns.tf:6`) → edge rule WILL fire |

The origin-code path would *also* work for 200 responses, but would leave the 307→/login (the exact response GSC crawled) uncertain, and would not match the established pattern. The edge rule covers the bare-URL 307 AND every other response, including the token routes (`/invite/*`, `/shared/[token]`) even if crawled.

## Why this is strictly SAFER than the old blanket Disallow (for the PR description)

The old `robots.ts` comment feared the token routes (`/invite/[token]`, `/shared/[token]`) were "a leak surface if indexed." But **robots.txt is precisely what allowed the bare URL to be indexed URL-only in the first place** — a `Disallow` records the URL's existence without a snippet and blocks the very `noindex` that would remove it. A **global `X-Robots-Tag: noindex, nofollow` at the edge guarantees the token routes are never indexed even if crawled**, which the robots.txt block never did. The fix refutes the concern that motivated the original block. (The auth-layout `<meta robots noindex>` in `app/(auth)/layout.tsx` and the `<meta name="robots" content="noindex">` in `app/shared/[token]/page.tsx` remain as harmless redundancy.)

## Research Reconciliation — Spec vs. Codebase

| Claim (from one-shot ARGUMENTS) | Reality (verified live + against `origin/main`) | Plan response |
|---|---|---|
| Fix via `next.config.ts headers()` / `middleware.ts` / `lib/security-headers.ts` | Repo has a canonical CF-edge mechanism (`seo_response_headers`) already noindexing `deploy.`/`api.` subdomains, CI-guarded + auto-applied | **Use the CF Transform Rule** (mirror the `deploy.soleur.ai` rule); document the divergence (above) |
| `curl -sI https://app.soleur.ai/` → no `X-Robots-Tag` | ✅ Confirmed live 2026-06-14: 307→/login, no `x-robots-tag` | Premise holds |
| `robots.txt` = `User-Agent: *` / `Disallow: /` | ✅ Confirmed live + `app/robots.ts` returns `{ userAgent:"*", disallow:"/" }` on `origin/main` | Premise holds |
| `app.soleur.ai` is a login-gated product surface with token routes | ✅ `app/(public)/invite`, `app/shared/[token]` exist | Premise holds |
| Security headers appear on the live 307 (suggesting `headers()` covers redirects) | Those headers are emitted on the CF-proxied response; `headers()` is NOT a reliable redirect-covering mechanism (precedent: `/robots.txt` middleware shadowing). | Edge rule is load-bearing; do not rely on origin `headers()` for the 307 |
| No existing test asserts `robots.txt` `Disallow: /` | ✅ Confirmed — repo-wide grep of `test/` found none | `robots.ts` change breaks no test |

## Premise Validation

All referenced premises checked and hold: the GSC root cause (`robots.ts` blanket Disallow) is present on `origin/main`; the token routes exist; the cited learning `knowledge-base/project/learnings/2026-06-12-gsc-duplicate-canonical-on-www-variant-is-benign-consolidation.md` exists (verify-live-before-fixing principle — applied: live `curl` confirmed the missing header before any code touched). No cited GitHub issue/PR blocker. No ADR governs robots/noindex (grep of the decisions corpus returned zero). This issue is a **distinct class** from the benign www-canonical reports — it is a real misconfiguration, not benign consolidation.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible — `app.soleur.ai` continues to function identically for logged-in users; only crawler-facing headers + `robots.txt` change. Worst realistic failure: the GSC report stays open one more crawl cycle (no regression vs. today).
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change *reduces* exposure — a global `noindex` header guarantees token routes (`/invite/*`, `/shared/[token]`) are never indexed even if crawled, which the prior robots.txt block did not. No data is added to any response; `X-Robots-Tag` is a directive header carrying no PII.
- **Brand-survival threshold:** `none` — crawler-indexing hygiene on a non-public product host; no single-user data/money/workflow path is touched. Reason for `none` on an SEO/edge surface: the change is a noindex directive + crawl-allow on an already-auth-gated host; no sensitive code path (schema, auth flow, API route, migration) is modified.

## Files to Edit

1. **`apps/web-platform/infra/seo-rulesets.tf`** — add a new `rules { }` block to `resource "cloudflare_ruleset" "seo_response_headers"` mirroring the existing `deploy.soleur.ai` rule, all-methods scope:

   ```hcl
   rules {
     action      = "rewrite"
     description = "X-Robots-Tag: noindex, nofollow on app.soleur.ai/* (login-gated product surface — GSC #<issue>)"
     enabled     = true
     expression  = "(http.host eq \"app.soleur.ai\")"
     action_parameters {
       headers {
         name      = "X-Robots-Tag"
         operation = "set"
         value     = "noindex, nofollow"
       }
     }
   }
   ```
   - Also update the resource's leading block comment: add `app.soleur.ai` to the enumerated rule list (currently lists api/deploy/RSS) and explain the GSC "Indexed, though blocked by robots.txt" rationale (noindex header is the load-bearing de-index mechanism for the bare URL + token routes).
   - All-methods scope (like `deploy.soleur.ai`), NOT GET-only (the `api.soleur.ai` GET-scope is specific to Supabase REST writes; the whole app host must noindex).
   - **No provider change** — provider is `cloudflare/cloudflare ~> 4.0` (`main.tf:24`); the `headers {}` block schema mirrors the live deploy rule.

2. **`apps/web-platform/app/robots.ts`** — change the rule from blanket `disallow: "/"` to **allow** crawling (at minimum `/` and `/login`). Recommended minimal form:

   ```ts
   export default function robots(): MetadataRoute.Robots {
     return {
       rules: {
         userAgent: "*",
         allow: "/",
       },
     };
   }
   ```
   - **Rewrite the existing code comment** to explain the new strategy: the `X-Robots-Tag: noindex, nofollow` edge header (in `seo-rulesets.tf`) is now the load-bearing de-indexing mechanism; `robots.txt` no longer blanket-disallows because that block was preventing Google from ever seeing the `noindex` (the cause of the "Indexed, though blocked by robots.txt" report). Note that token routes are protected by the global noindex header, not by a crawl block. Reference the GSC issue.
   - Crawl-allow is intentional and required: Google must be able to fetch the page to see the `noindex` and drop the URL.

3. **`apps/web-platform/test/seo-rulesets-noindex.test.ts`** — extend the existing CI guard with an `app.soleur.ai` rule assertion mirroring the `deploy.soleur.ai` tests:
   - assert the `app.soleur.ai` rewrite rule is present (`action`, `"rewrite"`, `X-Robots-Tag`),
   - assert it sets `X-Robots-Tag` to exactly `noindex, nofollow` (use the existing `extractRuleBlockForHost(body, "app.soleur.ai")` helper — note host literals are matched as `http.host eq \"<host>\"`),
   - assert it is `enabled = true`.
   - Auto-discovered by vitest (`test/**/*.test.ts` in the `unit` project, `vitest.config.ts:44`); no config change.

## Files to Create

None.

## Implementation Phases

### Phase 1 — robots.ts crawl-allow (RED→GREEN)
- (Optional but preferred) Add/adjust a source-text assertion if a robots.ts unit test is warranted; otherwise rely on the live post-merge `curl` check (Phase 4). No existing test asserts robots.txt content, so changing `robots.ts` requires no test edit to stay green.
- Change `robots.ts` to `allow: "/"`; rewrite the comment.

### Phase 2 — CF edge noindex rule (test-first)
- Add the `app.soleur.ai` assertions to `test/seo-rulesets-noindex.test.ts` (RED — fails because the rule doesn't exist yet).
- Add the `app.soleur.ai` `rules { }` block to `seo_response_headers` in `seo-rulesets.tf`; update the resource comment (GREEN).
- Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` — all rules (deploy, api, app, RSS) pass.

### Phase 3 — Verify locally
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (robots.ts type-check).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` (edge-rule guard).
- (No `terraform plan` required pre-merge — `apply-web-platform-infra.yml` runs plan/apply on merge; HCL syntax is covered by the source-text test + the workflow's own plan step.)

### Phase 4 — Post-merge auto-apply + verification (automated)
- On merge to `main`, `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**.tf` target-scoped (`-target=cloudflare_ruleset.seo_response_headers` already in the allow-list) — **no operator infra step**.
- The Next.js `robots.ts` change deploys via the standard `web-platform-release.yml` container rebuild on merge — **no operator step**.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `apps/web-platform/app/robots.ts` returns `allow: "/"` (or an allow rule covering `/` and `/login`), NOT `disallow: "/"`; the code comment explains the noindex-header-is-load-bearing strategy and references the GSC issue. Verify: `grep -n 'allow' apps/web-platform/app/robots.ts` returns the allow rule and `grep -c 'disallow: "/"' apps/web-platform/app/robots.ts` returns `0`.
- [ ] AC2 — `apps/web-platform/infra/seo-rulesets.tf` `seo_response_headers` contains a `rules` block with `expression = "(http.host eq \"app.soleur.ai\")"` and `value = "noindex, nofollow"`. Verify: `grep -n 'app.soleur.ai' apps/web-platform/infra/seo-rulesets.tf` shows the rule expression (not only the prose comment).
- [ ] AC3 — `test/seo-rulesets-noindex.test.ts` asserts the `app.soleur.ai` rule (present, exact `noindex, nofollow`, `enabled = true`); the suite passes. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` exits 0.
- [ ] AC4 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] AC5 — PR body uses `Ref #<GSC-issue>` (NOT `Closes`) so the issue closes only after the post-merge live verification confirms the header; the PR body contains the "Why this is strictly SAFER" paragraph.

### Post-merge (operator + automated)
- [ ] AC6 (automated) — `apply-web-platform-infra.yml` run succeeds on the merge; `web-platform-release.yml` rebuilds the container.
- [ ] AC7 (automated verification) — `curl -sI https://app.soleur.ai/` shows `x-robots-tag: noindex, nofollow` AND `curl -s https://app.soleur.ai/robots.txt` no longer contains `Disallow: /`. Automation: a post-merge `gh workflow`/CI curl step OR run inline at ship-time (deterministic, no SSO/CAPTCHA) — do NOT leave to operator dashboard-watching.
- [ ] AC8 (operator-only) — Operator clicks **VALIDATE FIX** in Google Search Console for the "Indexed, though blocked by robots.txt" report on `https://app.soleur.ai/`. **Automation: not feasible** — GSC is SSO/CAPTCHA-gated and the validate-fix action requires interactive Google account auth. This is the single genuinely operator-only step. After validation passes a crawl cycle, `gh issue close <GSC-issue>`.

## Observability

```yaml
liveness_signal:
  what: "x-robots-tag: noindex, nofollow header present on https://app.soleur.ai/ responses (incl. 307→/login)"
  cadence: "on-demand post-deploy + GSC weekly recrawl"
  alert_target: "GSC coverage report (operator), post-merge curl assertion (AC7)"
  configured_in: "apps/web-platform/infra/seo-rulesets.tf (seo_response_headers)"
error_reporting:
  destination: "apply-web-platform-infra.yml GitHub Actions run logs (terraform apply); CI vitest for the source-text guard"
  fail_loud: "terraform apply failure fails the workflow run (visible in Actions); seo-rulesets-noindex.test.ts fails CI on rule regression/deletion"
failure_modes:
  - mode: "Transform Rule silently dropped/disabled in a future seo-rulesets.tf refactor"
    detection: "test/seo-rulesets-noindex.test.ts asserts app.soleur.ai rule present + enabled + exact value"
    alert_route: "CI red on PR"
  - mode: "app.soleur.ai flipped to DNS-only (grey-cloud) → edge rule stops firing"
    detection: "post-deploy curl AC7 (header absent); dns.tf cloudflare_record.app proxied=true is the guard"
    alert_route: "AC7 curl verification + drift detector (scheduled-terraform-drift.yml)"
  - mode: "robots.ts reverts to Disallow: / (re-blocks crawl, re-breaks de-indexing)"
    detection: "grep AC1 in CI / code review"
    alert_route: "PR review + GSC report re-opens"
logs:
  where: "GitHub Actions run logs (apply-web-platform-infra.yml, ci.yml vitest); Cloudflare does not log per-response header injection"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "curl -sI https://app.soleur.ai/ | grep -i x-robots-tag && curl -s https://app.soleur.ai/robots.txt"
  expected_output: "x-robots-tag: noindex, nofollow  AND  robots.txt without a blanket 'Disallow: /'"
```

## Infrastructure (IaC)

### Terraform changes
- File: `apps/web-platform/infra/seo-rulesets.tf` — one new `rules { }` block appended to the existing `cloudflare_ruleset.seo_response_headers` (no new resource, no new root).
- Provider: `cloudflare/cloudflare ~> 4.0` (`main.tf:24`) — unchanged; the `headers {}` action_parameters schema mirrors the live `deploy.soleur.ai` rule.
- Sensitive variables: none new. Uses existing `var.cf_zone_id` + `cloudflare.rulesets` provider alias (bound to `var.cf_api_token_rulesets`, scope already includes Transform Rules:Edit).

### Apply path
- (b) cloud-init + idempotent: **auto-apply on merge** via `apply-web-platform-infra.yml` (path-filtered on `apps/web-platform/infra/**`, `-target=cloudflare_ruleset.seo_response_headers` already in the allow-list). No `-target=` allow-list edit needed (the resource is already listed; only a sub-rule is added). Blast radius: a single Transform Rule add on one resource; no destroy. Zero downtime.

### Distinctness / drift safeguards
- `cloudflare_record.app` (`dns.tf`) must stay `proxied = true` for the rule to fire — covered by `scheduled-terraform-drift.yml`. No `dev != prd` concern (Cloudflare zone is shared single-tenant `soleur.ai`). State holds no new secret values.

### Vendor-tier reality check
- Transform Rules (`http_response_headers_transform`) are available on Cloudflare Free tier; the zone already runs three rules in this exact resource. No tier gate needed.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — SEO/indexing-hygiene infrastructure + crawler-directive change on an already-auth-gated host. No new user-facing surface (the mechanical UI-surface override does not fire: `Files to Edit` are `.tf`, `robots.ts` metadata route, and a `.test.ts` — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` greps for `robots.ts`, `seo-rulesets`, and `security-headers` returned zero matches.)

## Test Scenarios

- `test/seo-rulesets-noindex.test.ts`: app.soleur.ai rule present + exact `noindex, nofollow` value + `enabled = true` (mirrors deploy/api assertions).
- Live post-deploy (AC7): `curl -sI https://app.soleur.ai/` → `x-robots-tag: noindex, nofollow`; `curl -s https://app.soleur.ai/robots.txt` → no blanket `Disallow: /`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `none` with reason.)
- The `api.soleur.ai` rule in `seo_response_headers` is a deliberate **dormant no-op** (DNS-only CNAME bypasses the edge — tracker #3379). Do NOT "fix" it or copy its GET-only scope to `app.soleur.ai`; `app.` is proxied and must noindex ALL methods, like `deploy.soleur.ai`.
- `extractRuleBlockForHost` in the test matches the host literal as `http.host eq \"<host>\"` (escaped quotes inside the .tf string) — the new `app.soleur.ai` rule's expression must use exactly that shape or the test helper won't bind it.
- robots.txt allowing crawl is **intentional and load-bearing** — do NOT re-add `Disallow: /`; the crawl-block is what prevented de-indexing. The global noindex header is the protection for token routes now.
- Use `Ref #<issue>` not `Closes #<issue>` (ops-remediation class): the actual de-index happens post-merge after the operator clicks VALIDATE FIX in GSC and a crawl cycle passes — close the issue then.
