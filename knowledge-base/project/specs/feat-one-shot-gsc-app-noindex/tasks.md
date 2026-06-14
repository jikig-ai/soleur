# Tasks — fix(seo): X-Robots-Tag noindex on app.soleur.ai + allow Googlebot crawl

Plan: `knowledge-base/project/plans/2026-06-14-fix-gsc-app-soleur-noindex-header-plan.md`
Lane: cross-domain (spec lacks valid `lane:` — defaulted to cross-domain, fail-closed)

## Phase 1 — robots.ts crawl-allow
- [x] 1.1 Edit `apps/web-platform/app/robots.ts`: change `disallow: "/"` → `allow: "/"`.
- [x] 1.2 Rewrite the code comment: noindex header is now the load-bearing de-index mechanism; robots.txt no longer blanket-disallows (that block prevented Google from seeing the noindex); token routes protected by the global noindex header. Reference the GSC issue.

## Phase 2 — Cloudflare edge noindex rule (test-first)
- [x] 2.1 Extend `apps/web-platform/test/seo-rulesets-noindex.test.ts`: add `app.soleur.ai` assertions using `extractRuleBlockForHost(body, "app.soleur.ai")` (RED) — rule present (`action`/`"rewrite"`/`X-Robots-Tag`) + EXACT value `expect(rule).toMatch(/value\s*=\s*"noindex, nofollow"/)` (mirror deploy/api at lines 139-140, NOT substring `noindex`) + `enabled = true`.
- [x] 2.2 Add the `app.soleur.ai` `rules { }` block to `cloudflare_ruleset.seo_response_headers` in `apps/web-platform/infra/seo-rulesets.tf` (all-methods scope, mirror `deploy.soleur.ai`).
- [x] 2.3 Update the `seo_response_headers` block comment: add app.soleur.ai to the rule list + GSC "Indexed, though blocked by robots.txt" rationale.

## Phase 3 — Verify locally
- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` → exit 0.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0.
- [x] 3.3 AC1 grep: `grep -c 'disallow: "/"' apps/web-platform/app/robots.ts` → 0.

## Phase 4 — Ship + post-merge verification
- [ ] 4.1 PR body: `Ref #<GSC-issue>` (not `Closes`) + the "Why this is strictly SAFER" paragraph + the mechanism-decision table.
- [ ] 4.2 (automated on merge) `apply-web-platform-infra.yml` applies the CF rule; `web-platform-release.yml` rebuilds the container.
- [ ] 4.3 (automated AC7) `curl -sI https://app.soleur.ai/` shows `x-robots-tag: noindex, nofollow`; `curl -s https://app.soleur.ai/robots.txt` no longer blanket-`Disallow: /`.
- [ ] 4.4 (operator-only AC8) Operator clicks VALIDATE FIX in GSC (SSO/CAPTCHA-gated). After a passing crawl cycle, `gh issue close <GSC-issue>`.
