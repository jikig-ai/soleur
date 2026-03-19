---
title: "feat: Growth Audit P1 — FAQ Sections + Keyword Injection"
type: feat
date: 2026-03-17
---

# feat: Growth Audit P1 — FAQ Sections + Keyword Injection

## Enhancement Summary

**Deepened on:** 2026-03-17
**Sections enhanced:** 6
**Research sources used:** Google Structured Data docs, AEO guides (CXL, GenOptima, Amsive), SEO schema guides (SchemaValidator, AirOps, Neil Patel), Soleur brand guide, growth-strategist agent, seo-aeo-analyst agent, copywriter agent

### Key Improvements

1. Added concrete FAQ question drafts for all 11 pages with brand-voice-aligned answers following the 40-word concise answer rule for AEO
2. Added the "answer-first" paragraph pattern for each FAQ answer -- the opening sentence must be a complete, self-contained answer before any elaboration
3. Added JSON-LD validation checklist and common pitfalls (HTML entities in schema text, Nunjucks variable rendering in JSON-LD blocks)
4. Added keyword co-occurrence strategy -- "solo founder AI tools" should appear alongside related terms ("company-as-a-service", "agentic engineering") to strengthen topical relevance

### New Considerations Discovered

- Google restricted FAQPage rich results in 2023 to authoritative government/health sites for competitive queries, but FAQ schema still drives 2.7x higher AI citation rates and remains critical for AEO
- FAQ schema with prompt-matched questions drives 3.1x higher answer extraction rates in AI engines
- Each page must have unique FAQ content -- copying identical schema across pages violates Google's structured data guidelines
- The 40-word rule: concise answer blocks of ~40 words are optimal for AI engine extraction
- Brand guide prohibits calling Soleur a "plugin" or "tool" in marketing copy (exception: literal CLI commands and technical docs) -- FAQ answers must say "platform" not "plugin"

---

## Overview

Implement the two P1 items from the weekly growth audit (#653): (1) add FAQ sections with FAQPage schema to the 11 site pages that lack them, and (2) inject the exact phrase "solo founder AI tools" into 3+ strategic locations site-wide. A separate GitHub issue (#656) was created for the P2 pricing page.

## Problem Statement / Motivation

The 2026-03-16 growth audit identified that 11 of the site's content pages have no FAQ content, blocking AEO (AI Engine Optimization) discoverability. Blog pillar articles with FAQ score 8.7/10 avg AEO, while core pages without FAQ average ~5/10. Additionally, the commercially valuable keyword "solo founder AI tools" -- an exact ICP match with buyer intent -- has zero occurrences anywhere on the site.

These are the two highest-impact, lowest-effort fixes identified by the audit. FAQ sections close the gap between blog articles (which have FAQ) and core pages (which do not). The keyword injection targets a phrase with commercial intent that directly describes Soleur's audience.

### Research Insights

**AEO Impact Data:**
- Pages with FAQ schema markup are 2.7x more likely to be cited in AI-generated answers (source: [Amsive AEO Guide](https://www.amsive.com/insights/seo/answer-engine-optimization-aeo-evolving-your-seo-strategy-in-the-age-of-ai-search/))
- FAQ schema with prompt-matched questions drives 3.1x higher answer extraction rates (source: [GenOptima AEO Techniques](https://www.gen-optima.com/geo/best-answer-engine-optimization-aeo-techniques-for-2026/))
- Google restricted FAQPage rich results to authoritative sites in 2023, but FAQ schema remains critical for AI engine discoverability, which is the primary goal here (source: [Search Engine Land](https://searchengineland.com/faq-schema-rise-fall-seo-today-463993))

**The 40-Word Rule:**
AI assistants extract concise answer blocks most effectively when they are approximately 40 words long (source: [CXL AEO Guide](https://cxl.com/blog/answer-engine-optimization-aeo-the-comprehensive-guide/)). Each FAQ answer should lead with a self-contained ~40-word sentence that answers the question completely, followed by optional elaboration.

## Proposed Solution

### Part 1: FAQ Sections + FAQPage Schema (11 Pages)

Add a FAQ section and corresponding `<script type="application/ld+json">` FAQPage schema to each of the following 11 pages:

**Core Pages (6):**

1. `plugins/soleur/docs/pages/agents.njk` -- Questions about AI agents, agent count, customization
2. `plugins/soleur/docs/pages/skills.njk` -- Questions about skills, workflow lifecycle, skill categories
3. `plugins/soleur/docs/pages/getting-started.md` -- Questions about installation, prerequisites, first steps
4. `plugins/soleur/docs/pages/vision.njk` -- Questions about the Soleur thesis, CaaS model, roadmap
5. `plugins/soleur/docs/pages/community.njk` -- Questions about contributing, getting help, Discord
6. `plugins/soleur/docs/pages/changelog.njk` -- Questions about versioning, release frequency, upgrade process

**Blog Case Studies (5):**

7. `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` -- Questions about brand guide automation
8. `plugins/soleur/docs/blog/case-study-business-validation.md` -- Questions about business validation workshops
9. `plugins/soleur/docs/blog/case-study-competitive-intelligence.md` -- Questions about competitive analysis automation
10. `plugins/soleur/docs/blog/case-study-legal-document-generation.md` -- Questions about legal document generation
11. `plugins/soleur/docs/blog/case-study-operations-management.md` -- Questions about operations automation

**Pattern to follow:** The existing FAQ implementation on `index.njk` is the reference pattern:
- HTML: `<details class="faq-item">` with `<summary class="faq-question">` and `<p class="faq-answer">`
- Schema: `<script type="application/ld+json">` with `@type: FAQPage` and `mainEntity` array
- CSS: Already exists in `plugins/soleur/docs/css/style.css` (lines 964-978) -- no CSS changes needed
- For blog posts (markdown): Use raw HTML `<details>` blocks (matching `what-is-company-as-a-service.md` pattern) plus `<script type="application/ld+json">` FAQPage block

**FAQ content guidelines per page:**
- 3-5 questions per page (enough for AEO, not bloated)
- Questions must match real search queries (what/how/is/does format)
- Answers must be factual, quotable, and self-contained (an AI engine should be able to extract a complete answer from any single FAQ entry)
- Include at least one question that naturally incorporates "solo founder AI tools" where contextually relevant

### Research Insights: FAQ Content Quality

**Answer-First Pattern (critical for AEO):**
Every FAQ answer must open with a direct, self-contained sentence that answers the question in ~40 words. This sentence is what AI engines will extract. Elaboration follows but is optional for comprehension.

**Bad:** "When it comes to getting started with Soleur, the first step is understanding what Claude Code is and then installing the platform..."
**Good:** "Install Soleur with `claude plugin install soleur`, then run `/soleur:go` and describe what you need. Soleur routes your request to the right workflow automatically."

**Unique Questions Per Page (Google requirement):**
Each page must have its own unique FAQ content. Copying identical questions across pages violates [Google's structured data guidelines](https://developers.google.com/search/docs/appearance/structured-data/sd-policies). The same topic (e.g., "Is Soleur free?") can appear on multiple pages only if the answer is contextually different for each page.

**Brand Voice Compliance:**
Per the brand guide, FAQ answers must:
- Use "platform" not "plugin" or "tool" (exception: literal CLI commands like `claude plugin install soleur`)
- Be declarative, not hedging ("Soleur deploys..." not "Soleur can help you...")
- Use concrete numbers when available ("{{ stats.agents }} agents across {{ stats.departments }} departments")
- Frame the founder as decision-maker, the system as executor

### Draft FAQ Questions by Page

#### 1. Agents Page (`agents.njk`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | What are Soleur agents? | Specialized AI personas with domain expertise that execute tasks within Claude Code -- not generic chatbots |
| 2 | How many agents does Soleur have? | {{ stats.agents }} agents across {{ stats.departments }} departments (auto-updating via template variable) |
| 3 | Can I customize Soleur agents? | Agents read from a shared knowledge base including brand guide and constitution -- customization is through documentation, not code |
| 4 | Do all agents run at once? | Agents are invoked by skills and workflows as needed -- only relevant agents activate for each task |
| 5 | What departments do Soleur agents cover? | Engineering, marketing, legal, finance, operations, product, sales, and support -- inject "solo founder AI tools" here |

#### 2. Skills Page (`skills.njk`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | What is a Soleur skill? | A multi-step automated workflow that orchestrates agents, tools, and knowledge for complex tasks |
| 2 | How do I run a skill? | Via `/soleur:go` which routes to the right skill, or directly via the Skill tool |
| 3 | What is the compound engineering lifecycle? | The 5-stage workflow: brainstorm, plan, implement, review, compound |
| 4 | How many skills does Soleur have? | {{ stats.skills }} skills across workflow orchestration, content, deployment, review, and more |
| 5 | What is knowledge compounding? | A system where every problem solved feeds a shared knowledge base that makes future work faster |

#### 3. Getting Started Page (`getting-started.md`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | What do I need to run Soleur? | Claude Code CLI with an Anthropic API key or Claude subscription |
| 2 | Does Soleur work on Windows, Linux, and macOS? | Yes -- runs anywhere Claude Code runs |
| 3 | How much does Soleur cost? | Free and open source -- costs depend on Claude usage |
| 4 | What is the difference between /soleur:go and individual skills? | /soleur:go is the unified entry point that routes to the right workflow -- inject "solo founder AI tools" here |
| 5 | Can I use Soleur with an existing project? | Yes -- run /soleur:sync to analyze the codebase and populate the knowledge base |

#### 4. Vision Page (`vision.njk`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | What is the Soleur thesis? | The first billion-dollar company run by one person is an engineering problem, and Soleur is solving it |
| 2 | What is company-as-a-service? | A platform model where AI agents run every department of a business, sharing compounding institutional knowledge |
| 3 | Is Soleur model-agnostic? | Current implementation runs on Claude Code; the vision includes multi-model orchestration |
| 4 | What is the Soleur roadmap? | Three milestones: automate software companies, then hardware companies, then multiplanetary operations |

#### 5. Community Page (`community.njk`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | How do I contribute to Soleur? | Read the contributing guide on GitHub, submit PRs, report bugs, or suggest features |
| 2 | Where can I get help with Soleur? | Discord server for questions, GitHub issues for bugs, community help channel |
| 3 | Does Soleur require a CLA? | Yes -- individual and corporate CLAs are required for code contributions |
| 4 | Is there a Soleur community? | Active Discord server, GitHub discussions, and X/Twitter presence |

#### 6. Changelog Page (`changelog.njk`)

| # | Question | Answer Focus |
|---|----------|-------------|
| 1 | How often is Soleur updated? | Continuous delivery -- updates ship when ready, tagged with semantic versioning |
| 2 | How do I upgrade Soleur? | Run `claude plugin install soleur` again to get the latest version |
| 3 | Does Soleur use semantic versioning? | Yes -- major.minor.patch with labels set during PR review |

#### 7-11. Case Studies (blog posts)

Each case study gets 3 unique questions following this pattern:

| # | Question Pattern | Answer Focus |
|---|-----------------|-------------|
| 1 | "Can AI [do the thing this case study covers]?" | Yes, with specifics from the case study results |
| 2 | "How long does [the process] take with Soleur?" | Time comparison: manual vs. AI-assisted |
| 3 | "Who is [this capability] for?" | Solo founders and small teams -- inject "solo founder AI tools" in one case study answer |

### Part 2: Inject "solo founder AI tools" (3+ Locations)

Add the exact phrase "solo founder AI tools" to at least 3 strategic locations. Current occurrences: zero.

**Target locations (prioritized by SEO weight):**

1. `plugins/soleur/docs/pages/getting-started.md` -- In the "What Is Soleur?" section or a new FAQ answer. This is the highest-traffic informational page after the homepage.
2. `plugins/soleur/docs/index.njk` -- In the FAQ section answer for "Who is Soleur for?" or in a new FAQ entry. The homepage carries the most SEO weight.
3. `plugins/soleur/docs/llms.txt.njk` -- In the description paragraph. This is the primary surface for AI engine discoverability.
4. `plugins/soleur/docs/pages/agents.njk` -- In the introductory prose or a FAQ answer. The agents page defines the product's core capability.
5. `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` or another case study -- Natural inclusion in a FAQ answer about who the case study is relevant to.

**Injection approach:** Natural prose integration, not keyword stuffing. The phrase should read as part of a meaningful sentence. Examples:
- "Soleur provides the most comprehensive set of solo founder AI tools available as a Claude Code platform."
- "Among solo founder AI tools, Soleur is the only platform that compounds institutional knowledge across every business department."

### Research Insights: Keyword Injection Strategy

**Keyword Co-occurrence:**
Place "solo founder AI tools" near related terms ("company-as-a-service", "agentic engineering", "knowledge compounding") to strengthen topical relevance. AI engines build semantic graphs -- clustering related terms signals topical authority.

**Avoid Over-Optimization:**
Do not use "solo founder AI tools" more than once per page. The growth-strategist agent's execution constraints specify: "Keyword injection must read naturally -- avoid repetition within 200 words of the same keyword." One natural occurrence per page across 3-5 pages is the target.

**Brand Voice Constraint:**
The brand guide says "Do not call it a tool in public-facing content." The phrase "solo founder AI tools" refers to the category, not to Soleur specifically. Use constructions where "tools" describes the market category: "Among solo founder AI tools, Soleur is the only platform that..." This keeps the brand voice intact while targeting the search query.

**Draft Injections:**

1. **index.njk** (FAQ "Who is Soleur for?" answer): "Soleur is built for solo founders and small teams who want to operate at the scale of a full organization. Among solo founder AI tools, Soleur is the only platform that spans every department and compounds institutional knowledge across sessions."

2. **getting-started.md** ("What Is Soleur?" section): Add to existing paragraph: "...agents that handle engineering, marketing, legal, finance, operations, product, sales, and support. As the most comprehensive solo founder AI tools platform available, every problem you solve compounds into patterns that make the next one faster."

3. **llms.txt.njk** (description paragraph): "{{ site.name }} is the most comprehensive solo founder AI tools platform available as a Claude Code plugin." -- Note: "plugin" is permitted in llms.txt since it is technical documentation, not marketing copy.

4. **agents.njk** (FAQ answer): "Soleur provides {{ stats.agents }} agents organized as a full company -- the most comprehensive set of solo founder AI tools for building and operating a business from a single terminal."

## Technical Considerations

- **No CSS changes needed.** The `.faq-*` CSS classes already exist in `style.css` at lines 964-978.
- **Nunjucks pages (.njk)** use raw HTML for FAQ sections (matching index.njk pattern).
- **Markdown blog posts (.md)** use raw HTML `<details>` blocks (matching what-is-company-as-a-service.md pattern) plus inline `<script>` for JSON-LD.
- **Template variables** like `{{ stats.agents }}` and `{{ stats.departments }}` can be used in .njk FAQ answers for auto-updating counts. Blog posts (markdown files processed by Eleventy) also support these Nunjucks variables.
- **FAQPage schema** must mirror the visible FAQ content exactly -- discrepancies between visible text and structured data violate Google's structured data guidelines.
- **Verify Eleventy build** after changes: run `npx @11ty/eleventy --dryrun` (requires `npm install` first in worktree) to catch template errors.

### Research Insights: Technical Pitfalls

**HTML Entities in JSON-LD:**
The existing index.njk uses `&mdash;` in visible HTML but plain `—` (em dash) in the JSON-LD schema text. This is correct. JSON-LD `"text"` values must use literal Unicode characters, not HTML entities. The FAQ answers in HTML can use `&mdash;` but the corresponding schema text must use `—` or `--`.

**Nunjucks Variables in JSON-LD:**
Template variables like `{{ stats.agents }}` render correctly inside `<script type="application/ld+json">` blocks in Eleventy because the entire template is processed by Nunjucks before output. However, avoid using `| safe` filter inside JSON-LD -- raw string output is what is needed.

**JSON-LD Placement in Markdown Files:**
In blog markdown files, the `<script type="application/ld+json">` block must appear as raw HTML within the markdown content. Eleventy processes it correctly. The existing `what-is-company-as-a-service.md` file proves this pattern works. Place the schema block after the FAQ `<details>` section, before any trailing markdown content.

**Schema Validation:**
After implementation, validate each page's structured data using [Google's Rich Results Test](https://search.google.com/test/rich-results) or [Schema Markup Validator](https://validator.schema.org/). Malformed JSON-LD is silently ignored by search engines.

**FAQ Section Placement in Core Pages:**
For `.njk` core pages, add the FAQ section as the last content section before the closing template tag, matching the index.njk pattern. For pages that end with a catalog grid (agents, skills), place the FAQ after the catalog. For pages with a final CTA, place the FAQ before the CTA.

## Acceptance Criteria

- [x] All 11 pages listed above have a visible FAQ section with 3-5 questions each
- [x] All 11 pages have a `<script type="application/ld+json">` block with `@type: FAQPage` schema
- [x] FAQ HTML uses the existing `.faq-item`, `.faq-question`, `.faq-answer` CSS classes (core pages) or `<details>` markdown pattern (blog posts)
- [x] Schema `mainEntity` entries match visible FAQ content exactly (no HTML entities in schema text)
- [x] "solo founder AI tools" exact phrase appears in 3+ distinct pages (4 pages confirmed)
- [x] All keyword injections read as natural prose (no keyword stuffing, max one occurrence per page)
- [x] Eleventy builds successfully with no template errors
- [x] P2 pricing page issue created as #656
- [x] Each FAQ answer opens with a self-contained ~40-word sentence (answer-first pattern for AEO)
- [x] No duplicate FAQ questions across pages (each page has unique Q&A pairs)
- [x] FAQ answers use "platform" not "plugin" or "tool" when referring to Soleur (brand guide compliance)

## Test Scenarios

- Given a core page (agents.njk), when the page is rendered, then a "Frequently Asked Questions" section is visible with collapsible Q&A items using `.faq-item` CSS classes
- Given a blog case study (case-study-brand-guide-creation.md), when the page source is inspected, then a `<script type="application/ld+json">` block with `@type: FAQPage` is present with unique questions
- Given the site is built with Eleventy, when all 11 pages are processed, then the build completes with zero errors
- Given a search for "solo founder AI tools" across the built site output, when the search runs, then 3+ distinct pages contain the exact phrase
- Given an AI engine parsing a page's FAQPage schema, when it extracts Q&A pairs, then each answer's opening sentence is a complete, self-contained response
- Given the JSON-LD schema blocks across all 11 pages, when validated against Google's Rich Results Test, then no errors are reported (warnings are acceptable)
- Given all FAQ answers across all 11 pages, when checked against the brand guide, then no answer uses "plugin", "tool", "assistant", or "copilot" to describe Soleur (except in literal CLI commands)

## Non-Goals

- Rewriting existing page copy (headlines, hero sections, feature descriptions) -- that is a separate initiative
- Creating new pages (pricing page is tracked in #656)
- Modifying JSON-LD schema beyond FAQPage (existing WebSite, SoftwareApplication schemas remain untouched)
- Adding FAQ to the legal index page, blog index page, 404 page, or articles redirect page (these are structural/navigation pages, not content pages)
- Optimizing for FAQ rich result snippets in Google Search (restricted to authoritative sites since 2023) -- the goal is AEO, not SERP rich results

## Dependencies & Risks

- **Risk: FAQ content quality.** Low-quality FAQ answers that are vague or aspirational (matching the homepage's original copy problems) would undermine the AEO benefit. Mitigation: Follow the factual, quotable style established in the existing homepage FAQ. Use the answer-first ~40-word pattern.
- **Dependency: Eleventy build.** The worktree needs `npm install` before any build verification. CSS classes already exist, so no style changes are needed.
- **Risk: Schema validation.** Malformed JSON-LD could cause Google to ignore the structured data. Mitigation: Validate each schema block matches the exact pattern from index.njk. Use literal Unicode in schema text, not HTML entities.
- **Risk: Brand voice drift.** FAQ answers written in haste may use prohibited terms ("tool", "plugin", "assistant") or hedging language. Mitigation: Cross-reference each answer against the brand guide Do's and Don'ts before committing.
- **Risk: Duplicate questions.** When adding FAQ to 11 pages, the temptation is to reuse generic questions like "What is Soleur?" on every page. Mitigation: The draft question tables above specify unique, page-relevant questions. Generic questions belong only on the homepage and getting-started page.

## Semver

This is a docs-only change to the marketing site. Semver label: `semver:patch`.

## References & Research

### Internal References

- Homepage FAQ pattern: `plugins/soleur/docs/index.njk:127-216` -- reference HTML + JSON-LD implementation
- Blog FAQ pattern: `plugins/soleur/docs/blog/what-is-company-as-a-service.md:132-216` -- reference markdown + JSON-LD implementation
- FAQ CSS: `plugins/soleur/docs/css/style.css:964-978` -- existing styles (no changes needed)
- Brand guide: `knowledge-base/marketing/brand-guide.md` -- voice, tone, and terminology constraints
- Feb 2026 AEO audit: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-aeo-audit.md` -- original recommendations
- Feb 2026 content audit: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-content-audit.md` -- keyword gap analysis
- Feb 2026 content plan: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-content-plan.md` -- keyword research tables

### External References

- [Google FAQPage Structured Data Documentation](https://developers.google.com/search/docs/appearance/structured-data/faqpage)
- [Google General Structured Data Guidelines](https://developers.google.com/search/docs/appearance/structured-data/sd-policies)
- [CXL: Answer Engine Optimization -- The Comprehensive Guide for 2026](https://cxl.com/blog/answer-engine-optimization-aeo-the-comprehensive-guide/)
- [GenOptima: Best AEO Techniques for 2026](https://www.gen-optima.com/geo/best-answer-engine-optimization-aeo-techniques-for-2026/)
- [Amsive: AEO -- Evolving Your SEO Strategy in the Age of AI Search](https://www.amsive.com/insights/seo/answer-engine-optimization-aeo-evolving-your-seo-strategy-in-the-age-of-ai-search/)
- [Search Engine Land: The Rise and Fall of FAQ Schema](https://searchengineland.com/faq-schema-rise-fall-seo-today-463993)
- [FAQ Schema Markup Guide (SchemaValidator)](https://schemavalidator.org/guides/faq-schema-markup-guide)
- [AirOps: How to Implement FAQ Schema](https://www.airops.com/blog/faq-schema-markup-example)
- [Wellows: FAQ Schema for SEO 2026](https://wellows.com/blog/improve-search-visibility-with-faq-schema/)
- [Google Rich Results Test](https://search.google.com/test/rich-results)

### Related Work

- Growth audit issue: #653
- P2 pricing page issue: #656
