---
title: "feat: Marketing Foundation — Blog Infrastructure, SEO Fixes, AEO"
type: feat
date: 2026-03-03
semver: patch
---

# Marketing Foundation — Blog Infrastructure, SEO Fixes, AEO

## Overview

Execute Phase 0 of the unified marketing strategy (#236). Build the foundational infrastructure that unblocks all content marketing: blog/articles section in Eleventy, keyword-optimized copy on existing pages, FAQ schema for AEO, and enhanced llms.txt. This is the prerequisite for Phases 1-3 (content creation, validation outreach, social proof).

## Problem Statement

The docs site at soleur.ai has zero informational content. SEO content score is 2/10. AEO score is 1.6/10. Zero target keywords appear in body copy. No blog infrastructure exists. The Feb 19 content plan prescribed 15 articles but blog infrastructure was never built, blocking all execution. This PR builds the foundation.

## Proposed Solution

Six deliverables, all within the existing Eleventy 3.x site:

1. **Blog infrastructure** — Eleventy articles collection with directory data file, article layout template, article index page, JSON-LD Article schema
2. **Keyword vacuum fix** — Rewrite H1s, H2s, meta descriptions, and body copy on all 5 existing pages to include target keywords
3. **llms.txt enhancement** — Expand with platform positioning, target keywords, use-case descriptions
4. **Getting Started context** — Add "What is Soleur?" paragraph before install command
5. **Homepage FAQ schema** — FAQPage JSON-LD with 5-6 common questions for AEO
6. **Validation outreach template** — Draft message for recruiting problem interview participants (saved to knowledge-base)

## Technical Considerations

### Architecture

All changes are within `plugins/soleur/docs/` — no plugin code, no agents, no skills modified.

**Files to create:**
- `plugins/soleur/docs/articles/articles.json` — directory data file (auto-tags collection)
- `plugins/soleur/docs/_includes/article.njk` — article layout extending base.njk
- `plugins/soleur/docs/pages/articles.njk` — article index/listing page

**Files to modify:**
- `plugins/soleur/docs/index.njk` — H1, hero-sub, H2s, FAQ section + FAQPage JSON-LD
- `plugins/soleur/docs/_includes/base.njk` — JSON-LD SoftwareApplication description, conditional Article schema
- `plugins/soleur/docs/_data/site.json` — navigation entry for Articles, description update
- `plugins/soleur/docs/pages/getting-started.md` — H1, description, "What is Soleur?" paragraph
- `plugins/soleur/docs/pages/agents.njk` — H1, description
- `plugins/soleur/docs/pages/skills.njk` — H1, description
- `plugins/soleur/docs/llms.txt.njk` — expanded content with keywords and positioning

**Files NOT modified (important):**
- No changes to `eleventy.config.js` — Eleventy directory data files handle collection creation automatically
- No changes to `style.css` — reuse existing CSS classes (`.page-hero`, `.catalog-grid`, `.component-card`)
- No changes to legal docs, plugin code, agents, or skills

### Key Learnings to Apply

1. **Nunjucks does NOT resolve variables in YAML frontmatter** — dynamic meta descriptions must use `{% set %}` blocks in template body
2. **`page.url` already has leading slash** — concatenation with `site.url` must not double-slash
3. **All content must be build-time rendered** — no client-side JS for SEO-critical content
4. **Keyword stuffing hurts AI visibility by -10%** — use citations, statistics, quotations instead (+30-40%)
5. **Run `npm install` in worktree** before building — dependencies not shared across worktrees
6. **Exclude utility pages from `collections.all`** — `eleventyExcludeFromCollections: true` for sitemap, 404, llms.txt

### Keyword Strategy

Target keywords to weave into existing pages (from content audit):

| Keyword | Primary Page | Secondary Pages |
|---------|-------------|-----------------|
| company as a service | Homepage, Articles | Getting Started, Vision |
| Claude Code plugin | Getting Started | Homepage, Agents |
| AI agents for business | Agents | Homepage |
| solo founder AI | Homepage | Getting Started, Articles |
| agentic engineering | Articles | Skills |

**Approach:** Natural integration in headings and body copy. No stuffing. Prioritize citations and statistics for GEO/AEO effectiveness.

## Acceptance Criteria

- [ ] `plugins/soleur/docs/articles/` directory exists with `articles.json` data file
- [ ] `plugins/soleur/docs/_includes/article.njk` layout renders articles with Article JSON-LD schema
- [ ] `plugins/soleur/docs/pages/articles.njk` index page lists articles (empty state handled)
- [ ] Articles nav entry appears in site header
- [ ] Homepage H1 contains "Soleur" and a target keyword
- [ ] All 5 page H1s contain descriptive text (not single generic words)
- [ ] All 5 page meta descriptions contain "Soleur" and relevant keywords
- [ ] Getting Started page has "What is Soleur?" context paragraph before install
- [ ] Homepage has FAQ section with FAQPage JSON-LD schema
- [ ] llms.txt contains platform positioning, target keywords, and articles link
- [ ] `validate-seo.sh` passes with no regressions
- [ ] Site builds cleanly with `npm run docs:build`
- [ ] Validation outreach template saved to knowledge-base

## Test Scenarios

- Given the articles directory exists with articles.json, when `npm run docs:build` runs, then `_site/articles/` directory is created
- Given an article.md file in articles/ with frontmatter, when built, then the article page has Article JSON-LD schema
- Given no articles exist, when visiting /pages/articles.html, then an empty state message is shown
- Given the homepage is built, when inspecting JSON-LD, then FAQPage schema with 5+ Q&A pairs is present
- Given all pages are built, when running validate-seo.sh, then all checks pass
- Given the sitemap is built, when inspecting entries, then articles index and article pages are included
- Given llms.txt is built, when reading content, then "company as a service" and "Claude Code" appear in the text

## Success Metrics

- Site builds with zero errors
- validate-seo.sh passes (no regressions from current baseline)
- All 5 pages contain at least one target keyword in H1
- FAQPage JSON-LD validates via Google Rich Results Test
- llms.txt word count increases by 50%+

## Dependencies & Risks

**Dependencies:**
- None — all changes are within the docs site, no external services

**Risks:**
- Blog layout may need CSS adjustments if article content doesn't fit existing styles (mitigated: reuse existing classes first)
- Keyword integration in H1s may affect brand voice (mitigated: maintain brand guide tone, test each rewrite against prohibited terms list)
- Build-time Article JSON-LD requires date handling in Nunjucks (mitigated: `dateToRfc3339` filter already exists)

## References & Research

### Internal References

- Marketing strategy: `knowledge-base/overview/marketing-strategy.md` (Phase 0 section)
- Content strategy: `knowledge-base/overview/content-strategy.md` (pillar content definitions)
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md` (page-specific rewrites)
- Content audit: `knowledge-base/audits/soleur-ai/2026-02-19-content-audit.md` (Sections 4.1-4.9 rewrite suggestions)
- AEO audit: `knowledge-base/audits/soleur-ai/2026-02-19-aeo-audit.md` (FAQ recommendations)
- Brand guide: `knowledge-base/overview/brand-guide.md` (prohibited terms, voice)

### Learnings Applied

- `knowledge-base/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md`
- `knowledge-base/learnings/build-errors/eleventy-seo-aeo-patterns.md`
- `knowledge-base/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md`
- `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`

### Related Issues

- #236 — Marketing Strategy Review (parent issue)
- #131 — Add SEO, AEO to the website docs (shipped — built the technical foundation)
- #88 — Publish brand website Solar Forge (shipped — built the docs site)
