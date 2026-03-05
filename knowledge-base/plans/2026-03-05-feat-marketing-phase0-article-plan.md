---
title: "feat: finish Phase 0 keyword vacuum fixes and publish first pillar article"
type: feat
date: 2026-03-05
semver: patch
---

# Finish Phase 0 Marketing Foundation and Launch Phase 1 Category Creation

## Overview

Complete the remaining Phase 0 SEO foundation work (keyword vacuum fixes on homepage, agents, and skills pages) and publish the first Phase 1 pillar article "What Is Company-as-a-Service?" -- all in a single PR. This PR transforms Soleur's web presence from zero informational content to having keyword-bearing page copy and a category-defining pillar article.

## Problem Statement / Motivation

The marketing strategy assessment (2026-03-03) documents a critical gap: **zero target keywords in body copy across all pages** and **zero informational content**. The content audit scored 2/10 for content and 1.6/10 for AEO. Meanwhile, the competitive window is narrowing -- Anthropic Cowork, Notion Custom Agents, and Tanka are all expanding. Soleur coined "Company-as-a-Service" but has not defined it publicly. Zero competition exists for this exact term, making category creation the highest-leverage content play available.

**What has already been done (prior sessions):**
- Blog infrastructure built (blog.json collection, blog-post.njk layout, BlogPosting JSON-LD, RSS feed, blog index page)
- FAQ section and FAQPage JSON-LD added to homepage
- "What is Soleur?" section added to Getting Started page
- llms.txt rewritten with platform positioning
- articles.njk redirect page created
- Blog CSS styles added (prose, blog-tags, blog-post-meta)

**What remains:**
- Homepage H2s still use decorative text ("This Is the Way", "Your AI Organization") instead of keyword-bearing headings
- Agents page has no introductory prose paragraph with target keywords
- Skills page has no introductory prose paragraph with target keywords
- No pillar article exists -- the blog directory contains zero posts

## Proposed Solution

Two deliverables in one PR, executed sequentially:

### Deliverable 1: Finish Phase 0 Keyword Vacuum Fixes

Edit three existing page templates to inject target keywords into headings and body copy.

### Deliverable 2: Write and Publish First Pillar Article

Create the "What Is Company-as-a-Service?" article as a markdown file in `plugins/soleur/docs/blog/`, following the blog-post.njk layout, brand guide voice, content strategy brief, and Princeton GEO/AEO techniques.

## Technical Considerations

### Eleventy Blog Infrastructure (Already Built)

- **Collection:** `plugins/soleur/docs/blog/blog.json` assigns tag `blog`, layout `blog-post.njk`, permalink `blog/{{ page.fileSlug }}/index.html`
- **Layout:** `plugins/soleur/docs/_includes/blog-post.njk` renders hero (title, description, date, tags), prose content, and BlogPosting JSON-LD
- **Base layout:** `plugins/soleur/docs/_includes/base.njk` provides canonical URL, OG tags, Twitter card, WebSite/WebPage JSON-LD, SoftwareApplication (homepage only)
- **RSS feed:** Configured in `eleventy.config.js` via `@11ty/eleventy-plugin-rss`, outputs to `/blog/feed.xml`
- **Blog index:** `plugins/soleur/docs/pages/blog.njk` lists posts from `collections.blog`
- **Date filters:** `readableDate` and `dateToRfc3339` already registered in eleventy.config.js
- **Site data:** `plugins/soleur/docs/_data/site.json` provides author name ("Jean Jikig"), site URL, etc.

### Nunjucks Frontmatter Limitation

Nunjucks does not resolve template variables (`{{ }}`) in YAML frontmatter. All frontmatter values (title, description, date) must be literal strings. Template variables only work in the body.

### SEO Validation

`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` checks: llms.txt, robots.txt AI bot access, sitemap.xml lastmod, canonical URL, JSON-LD, OG tags, Twitter card, SoftwareApplication on homepage, changelog build-time content. The article must pass all applicable checks. Instant meta-refresh redirects (like articles.njk) are auto-skipped.

### Brand Voice Constraints

From `knowledge-base/overview/brand-guide.md`:
- Prohibited terms: "AI-powered", "leverage AI", "just/simply", "assistant/copilot" (in marketing), startup jargon
- Declarative voice, no hedging
- Founder as decision-maker, system as executor
- Tone for category definition: Maximum ambition, declarative (Marketing/Hero spectrum)
- Never call it a "plugin" or "tool" in marketing content

### Princeton GEO/AEO Requirements

From `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`:
- Cite sources: +30-40% visibility uplift
- Add quotations: +30-40%
- Add statistics: up to +40%
- Keyword stuffing: **-10% (negative)** -- avoid
- Target: cite 5-8 external sources, include 2-3 quotations, embed 5-10 statistics with sources

### npm Install Requirement

Worktrees do not share `node_modules/`. Must run `npm install` in the worktree before `npm run docs:build`.

## Acceptance Criteria

### Deliverable 1: Keyword Vacuum Fixes

- [ ] **Homepage H2s contain target keywords** (`plugins/soleur/docs/index.njk`)
  - "This Is the Way" section: H2 rewritten to include "company-as-a-service" or equivalent target keyword
  - "Your AI Organization" section: H2 rewritten to include relevant keywords
  - Final CTA H2 can remain non-keyword (it's a conversion element)
  - Section labels (`.section-label`) can remain as-is (decorative, low SEO weight)
- [ ] **Agents page has introductory prose** (`plugins/soleur/docs/pages/agents.njk`)
  - 2-3 paragraph introduction after the hero section, before the category nav
  - Includes target keywords: "agentic engineering", "AI agents", "company-as-a-service", "cross-domain"
  - Consider adding FAQ section with 3 questions (optional, can be deferred)
- [ ] **Skills page has introductory prose** (`plugins/soleur/docs/pages/skills.njk`)
  - 2-3 paragraph introduction after the hero section, before the category nav
  - Includes target keywords: "agentic engineering", "compound engineering", "AI workflow"
  - Explains the brainstorm-plan-implement-review-compound lifecycle
- [ ] All changes use existing CSS classes (`.prose`, `.container`, `.content` section wrappers)
- [ ] No brand guide violations in new copy

### Deliverable 2: Pillar Article

- [ ] **Article file created** at `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- [ ] **Frontmatter** includes: title, description (under 160 chars with primary keyword), date (2026-03-05), tags (at minimum: "company-as-a-service", "CaaS")
- [ ] **Primary keyword** "company as a service" appears in: H1 (via title), first 150 words, at least one H2
- [ ] **Secondary keywords** appear in H2s or body: "CaaS platform", "full-stack AI organization", "agentic company", "solo founder"
- [ ] **Word count** 2,500-3,000 words (per content strategy brief)
- [ ] **Structure follows content strategy checklist:**
  - Machine-readable summary in first paragraph (what, who, why)
  - Definition uses "is" format ("Company-as-a-Service is...")
  - H2/H3 hierarchy is logical and scannable
  - Each section can stand alone for AI extraction
  - FAQ section with 3-5 questions in conversational format
  - FAQPage JSON-LD schema for the article's FAQ
  - CTA present (not aggressive)
  - Internal links to at least 2 other Soleur pages with keyword-rich anchor text
- [ ] **GEO/AEO compliance:**
  - 5-8 external source citations with links (Princeton GEO: +30-40%)
  - 2-3 quotations from industry leaders (Princeton GEO: +30-40%)
  - 5-10 statistics with attribution (Princeton GEO: up to +40%)
  - No keyword stuffing -- primary keyword appears naturally, not forced (Princeton GEO: -10% for stuffing)
- [ ] **Brand voice compliance:**
  - Zero prohibited terms
  - Declarative, ambitious tone
  - Concrete numbers from the product (agent counts, department counts, PR count)
  - Founder framed as decision-maker
- [ ] **BlogPosting JSON-LD** rendered correctly via blog-post.njk layout (headline, description, datePublished, author, publisher)
- [ ] **OG tags and Twitter card** rendered correctly via base.njk layout
- [ ] **Canonical URL** rendered correctly

### Build and Validation

- [ ] `npm install` succeeds in worktree
- [ ] `npm run docs:build` succeeds with zero errors
- [ ] `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` passes with zero failures
- [ ] Blog post appears in blog index page at `/blog/`
- [ ] Blog post accessible at `/blog/what-is-company-as-a-service/`
- [ ] RSS feed includes the new post

## Test Scenarios

- Given the built site, when validate-seo.sh runs against `_site/`, then all checks pass (canonical, JSON-LD, OG, Twitter card on every HTML page including the new blog post)
- Given the blog post markdown with frontmatter, when Eleventy builds, then the post appears in `collections.blog` and renders at the correct permalink
- Given the blog index page, when there are blog posts in the collection, then the "coming soon" message is replaced with post cards
- Given the homepage H2s, when a search engine crawls the page, then "company-as-a-service" appears in at least one H2 element
- Given the agents page, when crawled, then introductory prose contains "agentic engineering" in body text
- Given the skills page, when crawled, then introductory prose contains "agentic engineering" and describes the workflow lifecycle

## Implementation Notes

### Article Outline (Pre-approved by Content Strategy)

Based on `knowledge-base/overview/content-strategy.md` Gap 2 (CaaS Category Definition):

1. **Introduction / Definition** -- "Company-as-a-Service is..." (machine-readable, first 150 words)
2. **The Problem CaaS Solves** -- Solo founders run 70% non-engineering tasks manually; AI tools only cover code
3. **How CaaS Works** -- Multi-domain agent organization, compounding knowledge base, workflow orchestration
4. **CaaS vs. SaaS, AIaaS, BPaaS** -- Category differentiation table
5. **The Technology Behind CaaS** -- Cross-domain coherence, institutional memory, lifecycle orchestration
6. **Who Needs CaaS** -- Solo founders, small teams, technical builders
7. **The CaaS Future** -- Billion-dollar solo company thesis, industry predictions
8. **FAQ** -- 3-5 conversational questions with FAQPage JSON-LD
9. **CTA** -- Link to Getting Started

### Sources to Cite (GEO Compliance)

From competitive intelligence and industry research:
- Dario Amodei's prediction about one-person billion-dollar companies (2025)
- Sam Altman's similar prediction (2025)
- Princeton GEO research paper (KDD 2024, arxiv:2311.09735) -- methodology credibility
- Cursor $29.3B valuation / $1B ARR (2026) -- market context
- Devin $20/month pricing (2026) -- market evolution
- Notion Custom Agents launch (Feb 24, 2026) -- competitive landscape
- Lovable $200M ARR (2026) -- market validation
- Anthropic Cowork Plugins engineering coverage (Feb 24, 2026) -- platform dynamics

### Key Statistics to Embed (GEO Compliance)

- 61 agents across 8 departments (Soleur product data)
- 55 skills, 3 commands (Soleur product data)
- 420+ merged PRs (Soleur dogfooding data)
- $29.3B Cursor valuation (industry data)
- $200M ARR Lovable (industry data)
- 9,000+ Claude Code plugins (ecosystem data)
- 35M+ Notion users (competitive data)
- 70% of running a company is non-engineering (thesis framing)

### Quotations to Include (GEO Compliance)

- Dario Amodei on one-person billion-dollar companies
- Sam Altman on AI enabling solo company scale
- The Soleur Thesis: "The first billion-dollar company run by one person isn't science fiction. It's an engineering problem. We're solving it."

## Success Metrics

- All validate-seo.sh checks pass
- Blog post renders correctly with full schema markup
- Homepage, agents, and skills pages contain target keywords in headings and body
- Article word count is 2,500-3,000 words
- Article cites 5+ external sources
- Article includes 2+ quotations and 5+ statistics

## Dependencies and Risks

**Dependencies:**
- Blog infrastructure is already built (confirmed: blog.json, blog-post.njk, blog index, RSS feed all exist)
- Brand guide and content strategy documents exist (confirmed)
- Competitive intelligence provides source material for citations (confirmed)

**Risks:**
- **Keyword stuffing trap:** The content strategy lists many keywords. The article must use them naturally, not force them. Princeton GEO shows keyword stuffing reduces AI visibility by 10%.
- **Build breakage:** New markdown file in blog/ could expose edge cases in the blog-post.njk template or Eleventy config. Mitigated by building and validating before commit.
- **Nunjucks frontmatter limitation:** Template variables in frontmatter will not resolve. All frontmatter must use literal strings.
- **Prose styling:** New introductory paragraphs on agents/skills pages need the `.prose` CSS class wrapper. The existing pages use `.container` but not `.prose` for their content sections.

## References and Research

### Internal References

- Content strategy: `knowledge-base/overview/content-strategy.md` (Gap 2, Pillar 1, Content Quality Standards)
- Marketing strategy: `knowledge-base/overview/marketing-strategy.md` (Phase 0-1 execution plan)
- Brand guide: `knowledge-base/overview/brand-guide.md` (voice, tone, prohibited terms)
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md` (Priority 1.1-1.3 stale pages)
- Competitive intelligence: `knowledge-base/overview/competitive-intelligence.md` (source material)
- GEO/AEO learning: `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`

### File Paths

- Homepage: `plugins/soleur/docs/index.njk`
- Agents page: `plugins/soleur/docs/pages/agents.njk`
- Skills page: `plugins/soleur/docs/pages/skills.njk`
- Blog collection config: `plugins/soleur/docs/blog/blog.json`
- Blog post layout: `plugins/soleur/docs/_includes/blog-post.njk`
- Base layout: `plugins/soleur/docs/_includes/base.njk`
- Blog index: `plugins/soleur/docs/pages/blog.njk`
- SEO validator: `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
- Eleventy config: `eleventy.config.js`
- Site data: `plugins/soleur/docs/_data/site.json`
- CSS: `plugins/soleur/docs/css/style.css`

### External References

- Princeton GEO paper: https://arxiv.org/abs/2311.09735 (KDD 2024)
- Eleventy blog collection docs: https://www.11ty.dev/docs/collections/
