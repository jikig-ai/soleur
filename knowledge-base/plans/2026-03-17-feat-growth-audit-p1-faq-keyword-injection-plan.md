---
title: "feat: Growth Audit P1 — FAQ Sections + Keyword Injection"
type: feat
date: 2026-03-17
---

# feat: Growth Audit P1 — FAQ Sections + Keyword Injection

## Overview

Implement the two P1 items from the weekly growth audit (#653): (1) add FAQ sections with FAQPage schema to the 11 site pages that lack them, and (2) inject the exact phrase "solo founder AI tools" into 3+ strategic locations site-wide. A separate GitHub issue (#656) was created for the P2 pricing page.

## Problem Statement / Motivation

The 2026-03-16 growth audit identified that 11 of the site's content pages have no FAQ content, blocking AEO (AI Engine Optimization) discoverability. Blog pillar articles with FAQ score 8.7/10 avg AEO, while core pages without FAQ average ~5/10. Additionally, the commercially valuable keyword "solo founder AI tools" — an exact ICP match with buyer intent — has zero occurrences anywhere on the site.

These are the two highest-impact, lowest-effort fixes identified by the audit. FAQ sections close the gap between blog articles (which have FAQ) and core pages (which do not). The keyword injection targets a phrase with commercial intent that directly describes Soleur's audience.

## Proposed Solution

### Part 1: FAQ Sections + FAQPage Schema (11 Pages)

Add a FAQ section and corresponding `<script type="application/ld+json">` FAQPage schema to each of the following 11 pages:

**Core Pages (6):**

1. `plugins/soleur/docs/pages/agents.njk` — Questions about AI agents, agent count, customization
2. `plugins/soleur/docs/pages/skills.njk` — Questions about skills, workflow lifecycle, skill categories
3. `plugins/soleur/docs/pages/getting-started.md` — Questions about installation, prerequisites, first steps
4. `plugins/soleur/docs/pages/vision.njk` — Questions about the Soleur thesis, CaaS model, roadmap
5. `plugins/soleur/docs/pages/community.njk` — Questions about contributing, getting help, Discord
6. `plugins/soleur/docs/pages/changelog.njk` — Questions about versioning, release frequency, upgrade process

**Blog Case Studies (5):**

7. `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` — Questions about brand guide automation
8. `plugins/soleur/docs/blog/case-study-business-validation.md` — Questions about business validation workshops
9. `plugins/soleur/docs/blog/case-study-competitive-intelligence.md` — Questions about competitive analysis automation
10. `plugins/soleur/docs/blog/case-study-legal-document-generation.md` — Questions about legal document generation
11. `plugins/soleur/docs/blog/case-study-operations-management.md` — Questions about operations automation

**Pattern to follow:** The existing FAQ implementation on `index.njk` is the reference pattern:
- HTML: `<details class="faq-item">` with `<summary class="faq-question">` and `<p class="faq-answer">`
- Schema: `<script type="application/ld+json">` with `@type: FAQPage` and `mainEntity` array
- CSS: Already exists in `plugins/soleur/docs/css/style.css` (lines 964-978) — no CSS changes needed
- For blog posts (markdown): Use raw HTML `<details>` blocks (matching `what-is-company-as-a-service.md` pattern) plus `<script type="application/ld+json">` FAQPage block

**FAQ content guidelines per page:**
- 3-5 questions per page (enough for AEO, not bloated)
- Questions must match real search queries (what/how/is/does format)
- Answers must be factual, quotable, and self-contained (an AI engine should be able to extract a complete answer from any single FAQ entry)
- Include at least one question that naturally incorporates "solo founder AI tools" where contextually relevant

### Part 2: Inject "solo founder AI tools" (3+ Locations)

Add the exact phrase "solo founder AI tools" to at least 3 strategic locations. Current occurrences: zero.

**Target locations (prioritized by SEO weight):**

1. `plugins/soleur/docs/pages/getting-started.md` — In the "What Is Soleur?" section or a new FAQ answer. This is the highest-traffic informational page after the homepage.
2. `plugins/soleur/docs/index.njk` — In the FAQ section answer for "Who is Soleur for?" or in a new FAQ entry. The homepage carries the most SEO weight.
3. `plugins/soleur/docs/llms.txt.njk` — In the description paragraph. This is the primary surface for AI engine discoverability.
4. `plugins/soleur/docs/pages/agents.njk` — In the introductory prose or a FAQ answer. The agents page defines the product's core capability.
5. `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` or another case study — Natural inclusion in a FAQ answer about who the case study is relevant to.

**Injection approach:** Natural prose integration, not keyword stuffing. The phrase should read as part of a meaningful sentence. Examples:
- "Soleur provides the most comprehensive set of solo founder AI tools available as a Claude Code plugin."
- "Among solo founder AI tools, Soleur is the only platform that compounds institutional knowledge across every business department."

## Technical Considerations

- **No CSS changes needed.** The `.faq-*` CSS classes already exist in `style.css` at lines 964-978.
- **Nunjucks pages (.njk)** use raw HTML for FAQ sections (matching index.njk pattern).
- **Markdown blog posts (.md)** use raw HTML `<details>` blocks (matching what-is-company-as-a-service.md pattern) plus inline `<script>` for JSON-LD.
- **Template variables** like `{{ stats.agents }}` and `{{ stats.departments }}` can be used in .njk FAQ answers for auto-updating counts. Blog posts (markdown files processed by Eleventy) also support these Nunjucks variables.
- **FAQPage schema** must mirror the visible FAQ content exactly — discrepancies between visible text and structured data violate Google's structured data guidelines.
- **Verify Eleventy build** after changes: run `npx @11ty/eleventy --dryrun` (requires `npm install` first in worktree) to catch template errors.

## Acceptance Criteria

- [ ] All 11 pages listed above have a visible FAQ section with 3-5 questions each
- [ ] All 11 pages have a `<script type="application/ld+json">` block with `@type: FAQPage` schema
- [ ] FAQ HTML uses the existing `.faq-item`, `.faq-question`, `.faq-answer` CSS classes (core pages) or `<details>` markdown pattern (blog posts)
- [ ] Schema `mainEntity` entries match visible FAQ content exactly
- [ ] "solo founder AI tools" exact phrase appears in 3+ distinct pages
- [ ] All keyword injections read as natural prose (no keyword stuffing)
- [ ] Eleventy builds successfully with no template errors
- [ ] P2 pricing page issue created as #656

## Test Scenarios

- Given a core page (agents.njk), when the page is rendered, then a "Frequently Asked Questions" section is visible with collapsible Q&A items
- Given a blog case study (case-study-brand-guide-creation.md), when the page source is inspected, then a `<script type="application/ld+json">` block with `@type: FAQPage` is present
- Given the site is built with Eleventy, when all 11 pages are processed, then the build completes with zero errors
- Given a search for "solo founder AI tools" across the built site output, when the search runs, then 3+ distinct pages contain the exact phrase
- Given an AI engine parsing a page's FAQPage schema, when it extracts Q&A pairs, then each answer is self-contained and factually accurate

## Non-Goals

- Rewriting existing page copy (headlines, hero sections, feature descriptions) — that is a separate initiative
- Creating new pages (pricing page is tracked in #656)
- Modifying JSON-LD schema beyond FAQPage (existing WebSite, SoftwareApplication schemas remain untouched)
- Adding FAQ to the legal index page, blog index page, 404 page, or articles redirect page (these are structural/navigation pages, not content pages)

## Dependencies & Risks

- **Risk: FAQ content quality.** Low-quality FAQ answers that are vague or aspirational (matching the homepage's original copy problems) would undermine the AEO benefit. Mitigation: Follow the factual, quotable style established in the existing homepage FAQ.
- **Dependency: Eleventy build.** The worktree needs `npm install` before any build verification. CSS classes already exist, so no style changes are needed.
- **Risk: Schema validation.** Malformed JSON-LD could cause Google to ignore the structured data. Mitigation: Validate each schema block matches the exact pattern from index.njk.

## Semver

This is a docs-only change to the marketing site. Semver label: `semver:patch`.

## References & Research

### Internal References

- Homepage FAQ pattern: `plugins/soleur/docs/index.njk:127-216` — reference HTML + JSON-LD implementation
- Blog FAQ pattern: `plugins/soleur/docs/blog/what-is-company-as-a-service.md:132-216` — reference markdown + JSON-LD implementation
- FAQ CSS: `plugins/soleur/docs/css/style.css:964-978` — existing styles (no changes needed)
- Feb 2026 AEO audit: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-aeo-audit.md` — original recommendations
- Feb 2026 content audit: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-content-audit.md` — keyword gap analysis
- Feb 2026 content plan: `knowledge-base/marketing/audits/soleur-ai/2026-02-19-content-plan.md` — keyword research tables

### Related Work

- Growth audit issue: #653
- P2 pricing page issue: #656
