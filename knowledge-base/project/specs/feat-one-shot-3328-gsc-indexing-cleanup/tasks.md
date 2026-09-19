# Tasks — feat-one-shot-3328-gsc-indexing-cleanup

Plan: `knowledge-base/project/plans/2026-09-18-feat-blog-redirects-edge-migration-plan.md`
Ground truth: `knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md`

Two merges (verify-then-delete). PR-B must not merge until Phase-1 apply is
verified live (69/69 curls).

## Phase 1 — PR-A: edge 301s (infra, additive-only)

- [x] 1.1 Edit `apps/web-platform/infra/seo-bulk-redirects.tf`
  - [x] 1.1.1 Add `locals { blog_redirect_pairs = { …23 pairs… } }` + `blog_redirect_items` flatten (3 URL shapes per slug: `/`, `/index.html`, bare) before `resource "cloudflare_list" "legal_redirects"`
  - [x] 1.1.2 Append `dynamic "item"` block inside `cloudflare_list.legal_redirects` AFTER all explicit items (v4 block syntax; `status_code=301`, `include_subdomains="enabled"`, `preserve_query_string="enabled"`)
  - [x] 1.1.3 Update list `description` + header comment (legal + blog reslug + blog date-slugs; name retained by precedent)
- [x] 1.2 Validate locally
  - [x] 1.2.1 `cd apps/web-platform/infra && terraform validate` — PASS; console expansion = 69 items
  - [x] 1.2.2 `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` green (still 2 rules, bind order unchanged) — 41/41
  - [x] 1.2.3 `bash apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` green — 28/28 mutations killed; ssl-full-mitigation.test.sh 10/10 also green
- [x] 1.3 Merge PR-A → confirm `apply-web-platform-infra.yml` ran and applied `cloudflare_list.legal_redirects` — merged via **PR #8331** at 2026-09-18T19:52:20Z; apply ran on merge (recorded on issue #3328 2026-09-18 comment)
- [x] 1.4 Post-merge verification (record output in PR/issue evidence) — **69/69 verified live 2026-09-18** per the #3328 comment; 4-URL re-spot-check + www single-hop + canonical-200 re-verified green 2026-09-19 during PR-B planning resume
  - [x] 1.4.1 Loop all 69 source URLs: `curl -sI -A Googlebot` → `HTTP/2 301` + correct `location:` per the pairs table — 69/69 green 2026-09-18 (#3328 comment); spot re-check green 2026-09-19
  - [x] 1.4.2 Single-hop check: `https://www.soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` → 301 → `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` in one hop — re-verified 2026-09-19
  - [x] 1.4.3 Canonical check: `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` → `200` — re-verified 2026-09-19

## Phase 2 — PR-B: deletion + guard repurposing + internal links

Precondition: 1.4 complete (69/69 verified).

- [x] 2.1 Per-item live re-verification before deletion (`hr-bulk-delete-per-item-live-infra-role-check`): curl all 19 `pageRedirects.js` `from` paths → 301 — **19/19 green 2026-09-19** immediately pre-deletion (FAILURES=0; evidence for PR body)
- [x] 2.2 Delete meta-refresh machinery
  - [x] 2.2.1 `plugins/soleur/docs/page-redirects.njk`
  - [x] 2.2.2 `plugins/soleur/docs/_data/pageRedirects.js`
  - [x] 2.2.3 `plugins/soleur/docs/blog/redirects.njk`
  - [x] 2.2.4 `plugins/soleur/docs/_data/blogRedirects.js`
  - [x] 2.2.5 **Scope expansion:** `plugins/soleur/docs/pages/articles.njk` — a 5th stub found by the Guard-2 `_site` walk on first GREEN build (hand-maintained `/articles/` → `/blog/` meta-refresh, zero inbound links, noindex, not in sitemap, NO edge 301). Migrated to `cloudflare_list.legal_redirects` (3 items: `/articles/`, `/articles`, `/articles/index.html` → `https://soleur.ai/blog/`) + template deleted in the same PR — the only stub not edge-verified pre-merge; worst case a minutes-long 404 on a noindex zero-traffic URL if deploy beats apply.
- [x] 2.3 Repurpose guards
  - [x] 2.3.1 `scripts/validate-blog-links.sh`: replace redirect-validation block with Guard-1 bidirectional parity check + anti-vacuity floor — both mutation directions killed (file-without-key FAIL, key-without-file FAIL)
  - [x] 2.3.2 `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`: delete "Skip instant meta-refresh redirects" block
  - [x] 2.3.3 `plugins/soleur/test/validate-seo.test.ts`: flip instant-redirect test → stub page FAILS (exit 1, missing canonical)
  - [x] 2.3.4 `plugins/soleur/test/seo-aeo-drift-guard.test.ts`: replace stub-existence tests with Guard-2 zero-stub fence + tf-source assertions (9 legal source_urls + ToS pair present in `seo-bulk-redirects.tf`); ToS sibling test repointed at tf source
- [x] 2.4 Comment/doc cleanup: `sitemap.njk`, `seo-aeo/SKILL.md`, `seo-bulk-redirects.tf`, `seo-rulesets.tf`, `validate-seo.sh` header — all live-surface residuals now describe the deletion (KB history untouched)
- [x] 2.5 Internal-link equity
  - [x] 2.5.1 `_data/pillars.js`: `soleur-comparisons` (`soleur-vs-devin` pillar + 7 cluster) + `agentic-solo-founder` (`ai-agents-for-solo-founders` pillar + 5 cluster)
  - [x] 2.5.2 `pillar:` frontmatter on the 14 member posts (16 total `pillar:` keys incl. the 2 pre-existing `billion-dollar-solo-founder` — untouched)
  - [x] 2.5.3 `_data/site.json`: `gdpr-policy` + `data-protection-disclosure` appended to `footerLegal`
  - [x] 2.5.4 Optional bounded in-prose links — declined (series asides + footer carry the equity; no keyword-stuffing risk taken)
- [x] 2.6 Build + verify
  - [x] 2.6.1 `npx @11ty/eleventy` clean build; `grep -rl 'http-equiv="refresh"' _site` → empty (required `rm -rf _site` first — eleventy does not prune removed templates)
  - [x] 2.6.2 Rendered pillar-series asides (both series, all member URLs) + footer GDPR/Data-Protection links verified in `_site`
  - [x] 2.6.3 Host-mangle grep clean
  - [x] 2.6.4 `bun test` both files — 69/0; `bash scripts/validate-blog-links.sh _site` green; `terraform validate` green (post `init -backend=false`)
- [ ] 2.7 PR body contains `Closes #3328` on its own line

## Phase 3 — Post-merge

- [ ] 3.1 `deploy-docs.yml` publishes stub-free site; spot re-curl 3–5 date-slug URLs live
- [x] 3.2 File GSC re-verification follow-up issue (re-pull "Why pages aren't indexed" in ~2–4 weeks) — filed at planning time: **#8332**
