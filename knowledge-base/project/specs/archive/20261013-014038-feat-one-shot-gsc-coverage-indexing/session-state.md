# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-gsc-coverage-indexing-host-canonical-plan.md
- Status: complete

### Errors
None. (One transient build failure occurred because the subagent initially ran `npx @11ty/eleventy` from the bare repo root — a stale synced mirror missing the `jsonLdSafe` filter; rebuilding from the worktree succeeded. No impact on deliverables.)

### Decisions
- Root cause is a canonical-host inversion, not stale sitemap entries. Live curl (2026-05-29): bare `soleur.ai` = 200, `www.soleur.ai` 301s → bare, but the codebase declares `https://www.soleur.ai` everywhere (`site.json`, `robots.txt`, feed `base`). GitHub Pages now enforces the apex `CNAME`; plan flips code to match live infra.
- Most GSC CSV items are already fixed in source. A worktree build showed the built sitemap (48 URLs) has zero `/pages/*.html`, `/index.html`, or `feed.xml` (PRs #1851/#3296 cleaned those). Plan has a "Research Reconciliation" table separating already-fixed from genuinely-open items.
- Genuinely open items: (1) host flip; (2) missing redirect stub for `/pages/legal/terms-of-service.html` (live 404; renamed to terms-and-conditions); (3) app login page not noindexed + no app `robots.ts`; (4) `api`/`deploy` subdomain leakage deferred as a Cloudflare-edge concern with a tracking issue. `/legal/disclaimer/` "crawled-not-indexed" resolves via the host flip.
- Deepen pass found a second active www-canonicalizer: `_data/github.js:49-54` (`APEX_RE`) rewrites apex→www in changelog content; must be deleted. Full www sweep quantified: 24 refs across 12 files.
- Detail level MORE (focused bug fix); brand-survival threshold `aggregate pattern`. GSC "Validate Fix" is the single operator-only post-deploy step (no public API); post-deploy curl probes are automatable.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Deepen-plan halt gates 4.6 / 4.7 / 4.8 — all passed
