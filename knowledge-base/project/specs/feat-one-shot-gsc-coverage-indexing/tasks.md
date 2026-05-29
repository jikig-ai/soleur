---
feature: feat-one-shot-gsc-coverage-indexing
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-gsc-coverage-indexing-host-canonical-plan.md
---

# Tasks — Fix GSC coverage / indexing failures

Derived from `2026-05-29-fix-gsc-coverage-indexing-host-canonical-plan.md`. Order is load-bearing: the host flip (Phase 1) lands before downstream sitemap/canonical/validator verification.

## Phase 1 — Flip canonical host to bare apex (root cause #1)

- [x] 1.1 Edit `plugins/soleur/docs/_data/site.json`: `"url": "https://www.soleur.ai"` → `"url": "https://soleur.ai"`
- [x] 1.2 Edit `plugins/soleur/docs/robots.txt`: Sitemap line → `https://soleur.ai/sitemap.xml`
- [x] 1.3 Edit `eleventy.config.js`: feed `base` → `https://soleur.ai/`
- [x] 1.4 Edit `plugins/soleur/docs/_data/github.js`: remove `APEX_RE` (line 49) and the `.replace(APEX_RE, "https://www.soleur.ai")` (line 54) — stop rewriting apex→www in changelog bodies
- [x] 1.5 Sweep 7 legal docs + 1 blog post prose `www.soleur.ai` → apex (read each before editing): `pages/legal/{acceptable-use-policy,cookie-policy,data-protection-disclosure,disclaimer,gdpr-policy,privacy-policy,terms-and-conditions}.md`, `blog/2026-04-30-best-claude-code-plugins-2026.md`

## Phase 2 — Close legacy redirect-stub gap (root cause #3)

- [x] 2.1 Add `{ from: "pages/legal/terms-of-service.html", to: "/legal/terms-and-conditions/" }` to `plugins/soleur/docs/_data/pageRedirects.js`
- [x] 2.2 Audit the full GSC CSV legacy-path list against the existing map; add any other old-name stubs still indexed (cited set already covered; only `terms-of-service.html` was missing)

## Phase 3 — App noindex + app robots policy (root cause #4)

- [x] 3.1 Add `robots: { index: false, follow: false }` to the `metadata` export in `apps/web-platform/app/(auth)/layout.tsx` (keep existing `referrer`)
- [x] 3.2 Create `apps/web-platform/app/robots.ts` (Next.js `MetadataRoute.Robots`) disallowing crawl of the app subdomain

## Phase 4 — Regression guard + validator semantics

- [x] 4.1 Add regression guard: built sitemap excludes `/pages/`, `/index.html`, `feed.xml` and uses apex host. Extend existing docs test surface (`plugins/soleur/test/`, `bun test`) OR add a shell assertion to `deploy-docs.yml` "Verify build output" — do NOT add a new test runner
- [x] 4.2 (optional) Correct the stale `apex→www` comment in `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh:62` to `www→apex`
- [x] 4.3 Confirm `deploy-docs.yml` has no `www.soleur.ai` reference and its `test -f _site/pages/${page}.html` loop still passes

## Phase 5 — Build + validate

- [x] 5.1 `npx @11ty/eleventy` from worktree root
- [x] 5.2 `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` (expect exit 0, `single canonical host: https://soleur.ai`)
- [x] 5.3 `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site`
- [x] 5.4 Mechanically confirm AC4–AC9 + AC15 (apex-only hosts in sitemap/canonical/changelog; terms-of-service stub built; no www in github.js output)

## Post-merge (operator / ship)

- [ ] P.1 (ship-automatable) After deploy: `curl -sI https://soleur.ai/sitemap.xml` → 200, apex hosts; `curl -sI https://soleur.ai/pages/legal/terms-of-service.html` → 200 meta-refresh; `curl -s https://app.soleur.ai/login | grep noindex`. Bake into `/soleur:ship` post-merge verification
- [ ] P.2 (operator-only) Click "Validate Fix" in Google Search Console for each affected coverage category — no public API, interactive Google OAuth + console button

## Deferred (tracking issue)

- [ ] D.1 File issue: `api.soleur.ai`/`deploy.soleur.ai` subdomain coverage leakage — Cloudflare edge `X-Robots-Tag: noindex` or robots at the subdomain. Labels: `domain/engineering`, `chore`, `priority/p3-low`. Re-evaluate when subdomains carry real content
