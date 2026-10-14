# Tasks — Marketing Comparison + Disambiguation Pages

Branch: `feat-one-shot-mktg-compare-pages-3177-4408-4409`
Plan: `knowledge-base/project/plans/2026-06-01-mktg-compare-pages-plan.md`

- [x] Study existing comparison post, blog.json, base.njk, blog-post.njk, pricing/caas FAQ + JSON-LD parity, sitemap auto-inclusion, validate-seo.sh, content plans
- [x] Verify candidate citation URLs return 200
- [x] Write plan + tasks
- [ ] Create `pages/compare-soleur-vs-cursor.njk` (#4408) — summary, table, when-to-pick, citations, trust scaffolding, FAQ + FAQPage JSON-LD, cross-link existing blog post
- [ ] Create `pages/compare-soleur-vs-devin.njk` (#4409) — pricing arc $500→$20, table, when-to-pick, citations, FAQ + FAQPage JSON-LD
- [ ] Create `blog/2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md` (#3177) — disambiguation table, FAQ + FAQPage JSON-LD, links to plugin pillar + sibling
- [ ] Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with the new-surface describe block
- [ ] Build with `npx @11ty/eleventy --output=/tmp/site-prF`, confirm 3 new pages
- [ ] `validate-seo.sh /tmp/site-prF` exit 0
- [ ] `bun test plugins/soleur/test/` green
- [ ] CodeQL self-check grep clean
- [ ] anti-slop scan clean
- [ ] Commit (conventional, no Closes #N)
