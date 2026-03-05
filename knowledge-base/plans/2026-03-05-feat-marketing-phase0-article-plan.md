---
title: "feat: finish Phase 0 keyword vacuum fixes and publish first pillar article"
type: feat
date: 2026-03-05
semver: patch
---

# Finish Phase 0 Marketing Foundation and Launch Phase 1 Category Creation

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 8
**Research sources:** content-writer skill, growth skill, seo-aeo skill, frontend-design skill, 4 institutional learnings, 5 web searches, competitive intelligence document

### Key Improvements
1. Added verified external source URLs with exact quotation text for GEO compliance
2. Added content-writer skill constraint: do NOT add `layout` or `ogType` to frontmatter (inherited from blog.json), and do NOT generate inline BlogPosting JSON-LD (layout handles it)
3. Added pillar page SEO statistics: 30% organic traffic increase, 50% more likely to rank top 10
4. Added E-E-A-T guidance for 2026 SEO landscape
5. Added CSS/layout constraints from institutional learnings (grid orphan checks, existing class names only)
6. Refined article outline with specific word count targets per section and prose intro paragraph guidance

### New Considerations Discovered
- The `blog-post.njk` layout already generates BlogPosting JSON-LD -- only FAQ JSON-LD should be inline in the article body
- Instagram co-founder Mike Krieger quote adds a third quotation source for GEO compliance
- Pillar content strategy research validates the topic cluster approach as a 2026 SEO best practice
- Introductory prose sections on agents/skills pages should use a `<section class="content">` wrapper with `.prose` inside, matching the getting-started page pattern

---

## Overview

Complete the remaining Phase 0 SEO foundation work (keyword vacuum fixes on homepage, agents, and skills pages) and publish the first Phase 1 pillar article "What Is Company-as-a-Service?" -- all in a single PR. This PR transforms Soleur's web presence from zero informational content to having keyword-bearing page copy and a category-defining pillar article.

## Problem Statement / Motivation

The marketing strategy assessment (2026-03-03) documents a critical gap: **zero target keywords in body copy across all pages** and **zero informational content**. The content audit scored 2/10 for content and 1.6/10 for AEO. Meanwhile, the competitive window is narrowing -- Anthropic Cowork, Notion Custom Agents, and Tanka are all expanding. Soleur coined "Company-as-a-Service" but has not defined it publicly. Zero competition exists for this exact term, making category creation the highest-leverage content play available.

### Research Insights

**Pillar Page SEO Impact (2026 data):**
- Websites that implement a pillar content strategy see a **30% increase in organic traffic** compared to those that do not ([Bloghunter](https://bloghunter.se/blog/pillar-content-strategy-stats-facts-for-2026-data-driven-insights))
- Pillar pages are **50% more likely to rank in the top 10** search results for their target keywords
- The topic cluster model (pillar page + cluster content articles) builds topical authority, which is the primary ranking signal in 2026
- E-E-A-T (Experience, Expertise, Authoritativeness, Trust) is the foundation of modern SEO -- content backed by real insights, references, and structured clarity stands out

**Category Creation Timing:**
- Zero competition for "company as a service" as a search term (content strategy confirmed)
- Amodei's prediction places the one-person billion-dollar company timeline at 2026, making this the optimal moment to define the category

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

### Research Insights: Content-Writer Skill Constraints

From the `content-writer` skill (`plugins/soleur/skills/content-writer/SKILL.md`):

**Critical frontmatter rule:** `layout: "blog-post.njk"` and `ogType: "article"` are inherited from `blog/blog.json` -- do NOT add them to individual post frontmatter. The blog-post layout handles BlogPosting JSON-LD automatically -- do NOT generate inline BlogPosting JSON-LD in the post body. Only FAQ JSON-LD should appear inline.

**Correct frontmatter for the article:**

```yaml
---
title: "What Is Company-as-a-Service?"
date: 2026-03-05
description: "Company-as-a-Service is a new model where AI agents run every business department. Learn what CaaS means, how it works, and why it matters for solo founders."
tags:
  - company-as-a-service
  - CaaS
  - solo-founder
---
```

**Do NOT include:**
- `layout:` (inherited from blog.json)
- `ogType:` (inherited from blog.json)
- Inline `<script type="application/ld+json">` for BlogPosting (layout handles it)

### Nunjucks Frontmatter Limitation

Nunjucks does not resolve template variables (`{{ }}`) in YAML frontmatter. All frontmatter values (title, description, date) must be literal strings. Template variables only work in the body.

### SEO Validation

`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` checks: llms.txt, robots.txt AI bot access, sitemap.xml lastmod, canonical URL, JSON-LD, OG tags, Twitter card, SoftwareApplication on homepage, changelog build-time content. The article must pass all applicable checks. Instant meta-refresh redirects (like articles.njk) are auto-skipped.

### Brand Voice Constraints

From `knowledge-base/overview/brand-guide.md`:
- Prohibited terms: "AI-powered", "leverage AI", "just/simply", "assistant/copilot" (in marketing), startup jargon ("disrupt", "synergy", "move the needle")
- Declarative voice, no hedging
- Founder as decision-maker, system as executor
- Tone for category definition: Maximum ambition, declarative (Marketing/Hero spectrum)
- Never call it a "plugin" or "tool" in marketing content (exception: literal CLI commands in technical docs)

### Research Insights: Brand Guide Inline Validation

From learning `2026-02-12-brand-guide-contract-and-inline-validation.md`:

Apply inline brand voice validation during content generation, not as a separate post-hoc pass. Read the `## Voice` section from the brand guide and check each paragraph against the do's/don'ts list. This is faster and catches violations in the same context.

### Princeton GEO/AEO Requirements

From `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`:
- Cite sources: +30-40% visibility uplift
- Add quotations: +30-40%
- Add statistics: up to +40%
- Keyword stuffing: **-10% (negative)** -- avoid
- Target: cite 5-8 external sources, include 2-3 quotations, embed 5-10 statistics with sources

### Research Insights: 2026 SEO Landscape

From web research on 2026 SEO best practices:
- **E-E-A-T matters more than ever:** Google prioritizes content that shows real understanding -- Experience, Expertise, Authoritativeness, Trust ([Young Urban Project](https://www.youngurbanproject.com/how-to-write-seo-friendly-blog-posts/))
- **AI Overviews change the game:** Search engines now read context, not phrases -- clarity and intent matter more than keyword density
- **Schema markup is critical:** JSON-LD structured data drives rich snippets and AI engine citations ([12AM Agency](https://12amagency.com/blog/why-schema-markup-is-critical-for-seo-success/))
- **Topic clusters build authority:** A central pillar page connecting with multiple cluster articles establishes topical authority ([Semrush](https://www.semrush.com/blog/pillar-page/))

### CSS/Layout Constraints

From institutional learnings:
- **Use existing CSS classes only** (`2026-02-13-parallel-subagent-css-class-mismatch.md`): When adding HTML content to existing pages, use the established CSS classes (`.prose`, `.container`, `.content`, `.section-label`, `.section-title`, `.section-desc`). Do not invent new class names.
- **Grid orphan check** (`2026-02-22-landing-page-grid-orphan-regression.md`): If prose intro sections add any new card grids, verify `card_count % column_count == 0` at every responsive breakpoint.
- **Getting Started page pattern**: The getting-started.md page uses `<section class="content"><div class="container"><div class="prose">` to wrap Markdown prose. Use this same pattern for agents and skills page introductions.

### npm Install Requirement

Worktrees do not share `node_modules/`. Must run `npm install` in the worktree before `npm run docs:build`.

## Acceptance Criteria

### Deliverable 1: Keyword Vacuum Fixes

- [x] **Homepage H2s contain target keywords** (`plugins/soleur/docs/index.njk`)
  - "This Is the Way" section: H2 rewritten to include "company-as-a-service" or equivalent target keyword while preserving brand voice
  - "Your AI Organization" section: H2 rewritten to include relevant keywords
  - Final CTA H2 can remain non-keyword (it's a conversion element)
  - Section labels (`.section-label`) can remain as-is (decorative, low SEO weight)
- [x] **Agents page has introductory prose** (`plugins/soleur/docs/pages/agents.njk`)
  - 2-3 paragraph introduction after the hero `</section>` close and before the `<div class="container">` containing the category nav
  - Wrapped in `<section class="content"><div class="container"><div class="prose">` (matching getting-started.md pattern)
  - Includes target keywords: "agentic engineering", "AI agents", "company-as-a-service", "cross-domain"
  - Explains what the agents do, why 8 domains matter, how they share context
  - FAQ section deferred to a later PR (avoid scope creep)
- [x] **Skills page has introductory prose** (`plugins/soleur/docs/pages/skills.njk`)
  - 2-3 paragraph introduction after the hero `</section>` close and before the `<div class="container">` containing the category nav
  - Wrapped in `<section class="content"><div class="container"><div class="prose">` (matching getting-started.md pattern)
  - Includes target keywords: "agentic engineering", "compound engineering", "AI workflow"
  - Explains the brainstorm-plan-implement-review-compound lifecycle
- [x] All changes use existing CSS classes (`.prose`, `.container`, `.content` section wrappers)
- [x] No brand guide violations in new copy
- [x] No new CSS classes invented

### Deliverable 2: Pillar Article

- [x] **Article file created** at `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- [x] **Frontmatter** includes: title, description (under 160 chars with primary keyword), date (2026-03-05), tags -- NO `layout` or `ogType` fields (inherited from blog.json)
- [x] **Primary keyword** "company as a service" appears in: H1 (via title), first 150 words, at least one H2
- [x] **Secondary keywords** appear in H2s or body: "CaaS platform", "full-stack AI organization", "agentic company", "solo founder"
- [x] **Word count** 2,500-3,000 words (per content strategy brief)
- [ ] **Structure follows content strategy checklist:**
  - Machine-readable summary in first paragraph (what, who, why)
  - Definition uses "is" format ("Company-as-a-Service is...")
  - H2/H3 hierarchy is logical and scannable
  - Each section can stand alone for AI extraction
  - FAQ section with 3-5 questions in conversational format
  - FAQPage JSON-LD schema inline in the article body (this is the ONLY inline JSON-LD -- BlogPosting is handled by the layout)
  - CTA present (not aggressive)
  - Internal links to at least 2 other Soleur pages with keyword-rich anchor text
- [ ] **GEO/AEO compliance:**
  - 5-8 external source citations with links (Princeton GEO: +30-40%)
  - 2-3 quotations from industry leaders (Princeton GEO: +30-40%)
  - 5-10 statistics with attribution (Princeton GEO: up to +40%)
  - No keyword stuffing -- primary keyword appears naturally, not forced (Princeton GEO: -10% for stuffing)
- [ ] **Brand voice compliance:**
  - Zero prohibited terms ("AI-powered", "leverage AI", "just/simply", "assistant/copilot", "plugin/tool", startup jargon)
  - Declarative, ambitious tone -- no hedging ("might", "could", "potentially")
  - Concrete numbers from the product (agent counts, department counts, PR count)
  - Founder framed as decision-maker
- [x] **BlogPosting JSON-LD** rendered correctly via blog-post.njk layout (verified after build, not generated inline)
- [x] **OG tags and Twitter card** rendered correctly via base.njk layout
- [x] **Canonical URL** rendered correctly

### Build and Validation

- [x] `npm install` succeeds in worktree
- [x] `npm run docs:build` succeeds with zero errors
- [x] `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` passes with zero failures
- [x] Blog post appears in blog index page at `/blog/`
- [x] Blog post accessible at `/blog/what-is-company-as-a-service/`
- [x] RSS feed includes the new post
- [x] Blog post HTML contains BlogPosting JSON-LD (from layout)
- [x] Blog post HTML contains FAQPage JSON-LD (from inline)
- [x] Blog post HTML contains canonical URL, OG tags, Twitter card (from base layout)

## Test Scenarios

- Given the built site, when validate-seo.sh runs against `_site/`, then all checks pass (canonical, JSON-LD, OG, Twitter card on every HTML page including the new blog post)
- Given the blog post markdown with frontmatter (no layout field), when Eleventy builds, then the post inherits blog-post.njk from blog.json and renders at the correct permalink
- Given the blog index page, when there are blog posts in the collection, then the "coming soon" message is replaced with post cards
- Given the homepage H2s, when a search engine crawls the page, then "company-as-a-service" appears in at least one H2 element
- Given the agents page, when crawled, then introductory prose contains "agentic engineering" in body text
- Given the skills page, when crawled, then introductory prose contains "agentic engineering" and describes the workflow lifecycle
- Given the article body, when scanned for prohibited brand terms, then zero matches found

## Implementation Notes

### Article Outline (Pre-approved by Content Strategy, Enhanced with Research)

Based on `knowledge-base/overview/content-strategy.md` Gap 2 (CaaS Category Definition):

1. **Introduction / Definition** (~300 words) -- "Company-as-a-Service is..." (machine-readable, first 150 words). Include the core definition, who it serves, and why it exists now. Use "is" format for AI extractability.

2. **The Problem CaaS Solves** (~400 words) -- Solo founders run 70% non-engineering tasks manually; AI tools only cover code. Frame the gap between engineering AI (Cursor, Copilot, Devin) and full business operations. Use statistics on the number of tools solo founders juggle.

3. **How CaaS Works** (~500 words) -- Three pillars: multi-domain agent organization, compounding knowledge base, workflow orchestration. Concrete Soleur examples (61 agents, 8 departments, brainstorm-plan-implement-review-compound lifecycle). This is the section that differentiates category definition from product pitch -- keep it conceptual with concrete anchors.

4. **CaaS vs. SaaS, AIaaS, BPaaS** (~300 words) -- Comparison table distinguishing the categories. SaaS = software tools you operate. AIaaS = AI capabilities you integrate. BPaaS = business processes outsourced. CaaS = a complete AI organization that operates autonomously across every department with compounding institutional memory.

5. **The Technology Behind CaaS** (~400 words) -- Cross-domain coherence (brand guide informs marketing, competitive analysis shapes pricing, legal audit references privacy policy). Institutional memory that persists across sessions. Lifecycle orchestration across brainstorm > plan > build > review > compound.

6. **Who Needs CaaS** (~300 words) -- Solo founders building real companies. Small teams (1-3 people) operating across multiple domains. Technical builders who want business operations to compound, not reset. Frame as psychographics, not demographics.

7. **The CaaS Future** (~400 words) -- Billion-dollar solo company thesis. Amodei prediction (2026, 70-80% probability). Altman betting pool. Instagram/13-person precedent. The window: who defines the category now defines it for the next decade.

8. **FAQ** (~200 words) -- 3-5 conversational questions. Include FAQPage JSON-LD schema. Questions should match search queries: "What is company-as-a-service?", "How is CaaS different from SaaS?", "Who is CaaS for?", "Is CaaS the same as AI agents?"

9. **CTA** (~100 words) -- Link to Getting Started, link to Agents page. Keyword-rich anchor text.

**Total target: ~2,900 words** (within the 2,500-3,000 range)

### Verified Sources to Cite (GEO Compliance)

All URLs verified via web search on 2026-03-05:

| Source | URL | Use In Article |
|--------|-----|---------------|
| Amodei prediction (Inc.com) | https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609 | Section 7: CaaS Future |
| Altman prediction (Fello AI) | https://felloai.com/2025/09/sam-altman-other-ai-leaders-the-next-1b-startup-will-be-a-one-person-company/ | Section 7: CaaS Future |
| AI one-person unicorn (TechCrunch) | https://techcrunch.com/2025/02/01/ai-agents-could-birth-the-first-one-person-unicorn-but-at-what-societal-cost/ | Section 2: Problem |
| Princeton GEO paper | https://arxiv.org/abs/2311.09735 | Not cited in article (methodology reference for author) |
| Cursor $29.3B / $1B ARR (CNBC) | https://www.cnbc.com/2026/02/24/cursor-announces-major-update-as-ai-coding-agent-battle-heats-up.html | Section 2: Problem (market context) |
| Devin $20/month (VentureBeat) | https://venturebeat.com/programming-development/devin-2-0-is-here-cognition-slashes-price-of-ai-software-engineer-to-20-per-month-from-500 | Section 4: CaaS vs SaaS |
| Notion Custom Agents (Notion) | https://www.notion.com/releases/2026-02-24 | Section 5: Technology |
| Anthropic Cowork (TechCrunch) | https://techcrunch.com/2026/02/24/anthropic-launches-new-push-for-enterprise-agents-with-plugins-for-finance-engineering-and-design/ | Section 2: Problem |
| One-person unicorn guide (NxCode) | https://www.nxcode.io/resources/news/one-person-unicorn-context-engineering-solo-founder-guide-2026 | Section 7: CaaS Future |

### Verified Quotations (GEO Compliance)

| Speaker | Quote | Source |
|---------|-------|--------|
| Dario Amodei, CEO Anthropic | "There will be a one-person billion-dollar company in 2026" (70-80% probability) | [Inc.com](https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609) |
| Sam Altman, CEO OpenAI | "The first year that there is a one-person billion-dollar company... would have been unimaginable without AI -- and now will happen." | [Fello AI](https://felloai.com/2025/09/sam-altman-other-ai-leaders-the-next-1b-startup-will-be-a-one-person-company/) |
| Mike Krieger, Co-founder Instagram | "I built a billion-dollar company with 13 people." (When asked if he could do it alone with AI, responded the two co-founders could probably manage with Claude) | [Inc.com](https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609) |
| The Soleur Thesis | "The first billion-dollar company run by one person isn't science fiction. It's an engineering problem. We're solving it." | brand-guide.md |

### Key Statistics to Embed (GEO Compliance)

- 61 agents across 8 departments (Soleur product data -- use `{{ stats.agents }}` in body for dynamic count)
- 55 skills, 3 commands (Soleur product data -- use `{{ stats.skills }}` and `{{ stats.commands }}`)
- 420+ merged PRs (Soleur dogfooding data)
- $29.3B Cursor valuation, $1B ARR (CNBC, 2026)
- $200M ARR Lovable at $6.6B valuation (competitive intelligence)
- 9,000+ Claude Code plugins (Composio, 2026)
- 35M+ Notion users (competitive intelligence)
- 70% of running a company is non-engineering (thesis framing)
- WhatsApp: 55 employees, $19B acquisition, ~$345M per employee (precedent for lean companies)
- Devin pricing drop: $500 to $20/month (market evolution)

**Note on template variables:** `{{ stats.agents }}`, `{{ stats.skills }}`, etc. work in the article body because `markdownTemplateEngine: "njk"` is set in eleventy.config.js. They do NOT work in frontmatter.

### Homepage H2 Rewrite Guidance

Current H2s to rewrite:

| Current | Proposed | Rationale |
|---------|----------|-----------|
| "One founder powered by a full AI organization across every department." | "The company-as-a-service platform -- one founder, one AI organization, every department." | Injects primary keyword "company-as-a-service" while preserving the value proposition |
| "Your AI organization -- every department, from idea to shipped." | "Agentic engineering from idea to shipped -- every department, one workflow." | Injects secondary keyword "agentic engineering" and maintains the department coverage message |

These are suggestions -- the implementer should refine for brand voice. The H2 should feel like a natural evolution of the existing copy, not a keyword insertion.

### Prose Introduction Guidance for Agents and Skills Pages

**Agents page intro (2-3 paragraphs):**
- Paragraph 1: Define what agentic engineering means in the context of Soleur -- AI agents that operate as specialist team members across every business domain
- Paragraph 2: Explain the cross-domain coherence advantage -- agents share context (brand guide informs marketing, competitive analysis shapes product, legal audit references privacy policy)
- Paragraph 3: Scale statement (agent count, department count) with invitation to explore

**Skills page intro (2-3 paragraphs):**
- Paragraph 1: Define what agentic engineering skills are -- multi-step workflow orchestration that chains agents, tools, and knowledge
- Paragraph 2: Explain the compound engineering lifecycle (brainstorm > plan > implement > review > compound) and how each stage feeds the next
- Paragraph 3: Skill count with invitation to explore categories

**HTML wrapper pattern (from getting-started.md):**
```html
<section class="content">
  <div class="container">
    <div class="prose">

[Markdown prose content here]

    </div>
  </div>
</section>
```

## Success Metrics

- All validate-seo.sh checks pass
- Blog post renders correctly with full schema markup (BlogPosting from layout + FAQPage inline)
- Homepage, agents, and skills pages contain target keywords in headings and body
- Article word count is 2,500-3,000 words
- Article cites 5+ external sources with live URLs
- Article includes 3+ quotations (Amodei, Altman, Krieger) and 5+ statistics
- Article passes brand voice check (zero prohibited terms)

## Dependencies and Risks

**Dependencies:**
- Blog infrastructure is already built (confirmed: blog.json, blog-post.njk, blog index, RSS feed all exist)
- Brand guide and content strategy documents exist (confirmed)
- Competitive intelligence provides source material for citations (confirmed)

**Risks:**
- **Keyword stuffing trap:** The content strategy lists many keywords. The article must use them naturally, not force them. Princeton GEO shows keyword stuffing reduces AI visibility by 10%. Mitigation: limit primary keyword ("company as a service") to 8-12 natural occurrences in a 3,000-word article (0.3-0.4% density).
- **Build breakage:** New markdown file in blog/ could expose edge cases in the blog-post.njk template or Eleventy config. Mitigated by building and validating before commit.
- **Nunjucks frontmatter limitation:** Template variables in frontmatter will not resolve. All frontmatter must use literal strings. Template variables in the body work fine.
- **Prose styling:** New introductory paragraphs on agents/skills pages need the `.prose` CSS class wrapper. Use the `<section class="content"><div class="container"><div class="prose">` pattern from getting-started.md.
- **Duplicate JSON-LD:** The blog-post.njk layout generates BlogPosting JSON-LD. Do NOT add another BlogPosting block inline. Only FAQPage JSON-LD should appear in the article body.
- **External link rot:** Source URLs were verified on 2026-03-05. Some may become unavailable. Use permanent archive references where possible (arxiv, official blog posts).

## References and Research

### Internal References

- Content strategy: `knowledge-base/overview/content-strategy.md` (Gap 2, Pillar 1, Content Quality Standards)
- Marketing strategy: `knowledge-base/overview/marketing-strategy.md` (Phase 0-1 execution plan)
- Brand guide: `knowledge-base/overview/brand-guide.md` (voice, tone, prohibited terms)
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md` (Priority 1.1-1.3 stale pages)
- Competitive intelligence: `knowledge-base/overview/competitive-intelligence.md` (source material)
- GEO/AEO learning: `knowledge-base/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`
- Brand guide inline validation: `knowledge-base/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md`
- CSS class mismatch prevention: `knowledge-base/learnings/2026-02-13-parallel-subagent-css-class-mismatch.md`
- Grid orphan checks: `knowledge-base/learnings/2026-02-22-landing-page-grid-orphan-regression.md`
- UX review gap: `knowledge-base/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md`
- Content-writer skill: `plugins/soleur/skills/content-writer/SKILL.md`

### File Paths

- Homepage: `plugins/soleur/docs/index.njk`
- Agents page: `plugins/soleur/docs/pages/agents.njk`
- Skills page: `plugins/soleur/docs/pages/skills.njk`
- Getting Started page: `plugins/soleur/docs/pages/getting-started.md` (reference for prose wrapper pattern)
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
- Pillar content strategy: https://www.semrush.com/blog/pillar-page/
- 2026 SEO best practices: https://www.youngurbanproject.com/how-to-write-seo-friendly-blog-posts/
- Schema markup for blogs: https://12amagency.com/blog/why-schema-markup-is-critical-for-seo-success/
- Amodei prediction: https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609
- Altman prediction: https://felloai.com/2025/09/sam-altman-other-ai-leaders-the-next-1b-startup-will-be-a-one-person-company/
- One-person unicorn (TechCrunch): https://techcrunch.com/2025/02/01/ai-agents-could-birth-the-first-one-person-unicorn-but-at-what-societal-cost/
