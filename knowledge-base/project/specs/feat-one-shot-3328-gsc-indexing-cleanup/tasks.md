# Tasks — feat-one-shot-3328-gsc-indexing-cleanup

Plan: `knowledge-base/project/plans/2026-09-18-feat-blog-redirects-edge-migration-plan.md`
Ground truth: `knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md`

Two merges (verify-then-delete). PR-B must not merge until Phase-1 apply is
verified live (46/46 curls).

## Phase 1 — PR-A: edge 301s (infra, additive-only)

- [ ] 1.1 Edit `apps/web-platform/infra/seo-bulk-redirects.tf`
  - [ ] 1.1.1 Add `locals { blog_redirect_pairs = { …23 pairs… } }` + `blog_redirect_items` flatten (2 URL shapes per slug) before `resource "cloudflare_list" "legal_redirects"`
  - [ ] 1.1.2 Append `dynamic "item"` block inside `cloudflare_list.legal_redirects` AFTER all explicit items (v4 block syntax; `status_code=301`, `include_subdomains="enabled"`, `preserve_query_string="enabled"`)
  - [ ] 1.1.3 Update list `description` + header comment (legal + blog reslug + blog date-slugs; name retained by precedent)
- [ ] 1.2 Validate locally
  - [ ] 1.2.1 `cd apps/web-platform/infra && terraform validate`
  - [ ] 1.2.2 `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` green (still 2 rules, bind order unchanged)
  - [ ] 1.2.3 `bash apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` green
- [ ] 1.3 Merge PR-A → confirm `apply-web-platform-infra.yml` ran and applied `cloudflare_list.legal_redirects`
- [ ] 1.4 Post-merge verification (record output in PR/issue evidence)
  - [ ] 1.4.1 Loop all 46 source URLs: `curl -sI -A Googlebot` → `HTTP/2 301` + correct `location:` per the pairs table
  - [ ] 1.4.2 Single-hop check: `https://www.soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` → 301 → `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` in one hop
  - [ ] 1.4.3 Canonical check: `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` → `200`

## Phase 2 — PR-B: deletion + guard repurposing + internal links

Precondition: 1.4 complete (46/46 verified).

- [ ] 2.1 Per-item live re-verification before deletion (`hr-bulk-delete-per-item-live-infra-role-check`): curl all 19 `pageRedirects.js` `from` paths → 301 (record in PR)
- [ ] 2.2 Delete meta-refresh machinery
  - [ ] 2.2.1 `plugins/soleur/docs/page-redirects.njk`
  - [ ] 2.2.2 `plugins/soleur/docs/_data/pageRedirects.js`
  - [ ] 2.2.3 `plugins/soleur/docs/blog/redirects.njk`
  - [ ] 2.2.4 `plugins/soleur/docs/_data/blogRedirects.js`
- [ ] 2.3 Repurpose guards
  - [ ] 2.3.1 `scripts/validate-blog-links.sh`: replace redirect-validation block with Guard-1 bidirectional parity check + anti-vacuity floor
  - [ ] 2.3.2 `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`: delete "Skip instant meta-refresh redirects" block
  - [ ] 2.3.3 `plugins/soleur/test/validate-seo.test.ts`: flip instant-redirect test → stub page FAILS (exit 1, missing canonical)
  - [ ] 2.3.4 `plugins/soleur/test/seo-aeo-drift-guard.test.ts`: replace stub-existence tests with Guard-2 zero-stub fence + tf-source assertions (9 legal source_urls + ToS pair present in `seo-bulk-redirects.tf`)
- [ ] 2.4 Comment/doc cleanup: `plugins/soleur/docs/sitemap.njk` stale comment; `plugins/soleur/skills/seo-aeo/SKILL.md` sweep-list reference to `page-redirects.njk`
- [ ] 2.5 Internal-link equity
  - [ ] 2.5.1 `_data/pillars.js`: add `soleur-comparisons` series (8 vs-posts) + `agentic-solo-founder` series (6 posts)
  - [ ] 2.5.2 `pillar:` frontmatter on the 14 member posts (do not reassign the 2 posts already in `billion-dollar-solo-founder`)
  - [ ] 2.5.3 `_data/site.json`: append `gdpr-policy` + `data-protection-disclosure` to `footerLegal`
  - [ ] 2.5.4 Optional bounded: ≤2 in-prose contextual links per target post where a natural anchor exists
- [ ] 2.6 Build + verify
  - [ ] 2.6.1 `npx @11ty/eleventy`; `grep -rl 'http-equiv="refresh"' _site` → empty
  - [ ] 2.6.2 Rendered pillar-series asides + footer links verified in `_site`
  - [ ] 2.6.3 Host-mangle grep `grep -rEoh 'https://soleur\.ai[a-zA-Z]' _site/blog/` clean (fix surfaced broken links in scope)
  - [ ] 2.6.4 `bun test plugins/soleur/test/validate-seo.test.ts plugins/soleur/test/seo-aeo-drift-guard.test.ts` green; `bash scripts/validate-blog-links.sh _site` green
- [ ] 2.7 PR body contains `Closes #3328` on its own line

## Phase 3 — Post-merge

- [ ] 3.1 `deploy-docs.yml` publishes stub-free site; spot re-curl 3–5 date-slug URLs live
- [ ] 3.2 File GSC re-verification follow-up issue (re-pull "Why pages aren't indexed" in ~2–4 weeks) — deferral tracking
