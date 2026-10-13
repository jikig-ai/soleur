# Tasks: Marketing Foundation

**Issue:** #236
**Plan:** `knowledge-base/project/plans/2026-03-03-feat-marketing-foundation-plan.md`

## Phase 1: Blog Infrastructure

- [ ] 1.1 Create `plugins/soleur/docs/articles/articles.json` directory data file (tags: articles, layout: article.njk, permalink pattern)
- [ ] 1.2 Create `plugins/soleur/docs/_includes/article.njk` article layout template
  - [ ] 1.2.1 Extend base.njk structure (header, nav, footer)
  - [ ] 1.2.2 Add article-specific elements: title, date, description, reading time
  - [ ] 1.2.3 Add JSON-LD Article schema (build-time, not client-side)
  - [ ] 1.2.4 Add OG/Twitter meta for article type (og:type = article)
- [ ] 1.3 Create `plugins/soleur/docs/pages/articles.njk` index page
  - [ ] 1.3.1 List articles from `collections.articles` with title, date, description
  - [ ] 1.3.2 Handle empty state (no articles yet)
  - [ ] 1.3.3 Reuse existing CSS classes (.page-hero, .catalog-grid or similar)
- [ ] 1.4 Add "Articles" nav entry to `plugins/soleur/docs/_data/site.json`
- [ ] 1.5 Verify build: `npm install && npm run docs:build` — articles collection created, no errors

## Phase 2: Keyword Vacuum Fix

- [ ] 2.1 Update `plugins/soleur/docs/index.njk`
  - [ ] 2.1.1 Rewrite H1 to include "Soleur" + target keyword (keep brand voice)
  - [ ] 2.1.2 Update hero-sub text with platform positioning keywords
  - [ ] 2.1.3 Update section H2s with descriptive keyword-rich text
  - [ ] 2.1.4 Update meta description with "Soleur", "company as a service", "Claude Code"
- [ ] 2.2 Update `plugins/soleur/docs/pages/getting-started.md`
  - [ ] 2.2.1 Rewrite H1: "Getting Started with Soleur" or similar
  - [ ] 2.2.2 Update description with "Claude Code plugin" keyword
  - [ ] 2.2.3 Add "What is Soleur?" context paragraph before install command
- [ ] 2.3 Update `plugins/soleur/docs/pages/agents.njk`
  - [ ] 2.3.1 Rewrite H1: "Soleur AI Agents" or similar
  - [ ] 2.3.2 Update description with business domain keywords
- [ ] 2.4 Update `plugins/soleur/docs/pages/skills.njk`
  - [ ] 2.4.1 Rewrite H1: "Soleur Skills" or similar
  - [ ] 2.4.2 Update description with workflow keywords
- [ ] 2.5 Update `plugins/soleur/docs/_data/site.json` description field
- [ ] 2.6 Run brand guide prohibited terms check: grep for "AI-powered", "leverage AI", "just/simply", "assistant/copilot" across all modified files

## Phase 3: AEO — FAQ Schema + llms.txt

- [ ] 3.1 Add FAQ section to `plugins/soleur/docs/index.njk`
  - [ ] 3.1.1 Write 5-6 Q&A pairs covering: "What is Soleur?", "What is Company-as-a-Service?", "How does Soleur differ from Cowork/Cursor?", "Is Soleur free?", "Who is Soleur for?"
  - [ ] 3.1.2 Add inline FAQPage JSON-LD schema (build-time rendered)
  - [ ] 3.1.3 Style FAQ section with existing CSS classes
- [ ] 3.2 Expand `plugins/soleur/docs/llms.txt.njk`
  - [ ] 3.2.1 Add platform positioning paragraph with target keywords
  - [ ] 3.2.2 Add "Articles" section link (empty until articles exist)
  - [ ] 3.2.3 Add use-case descriptions for each linked page

## Phase 4: Validation & Quality

- [ ] 4.1 Run `npm run docs:build` — clean build, no errors
- [ ] 4.2 Run `validate-seo.sh` — no regressions
- [ ] 4.3 Verify JSON-LD output in built HTML (homepage FAQPage, article Article)
- [ ] 4.4 Verify sitemap includes articles index
- [ ] 4.5 Check all modified pages for brand guide compliance (prohibited terms)

## Phase 5: Validation Outreach Template

- [ ] 5.1 Draft problem interview outreach message template
- [ ] 5.2 Save to `knowledge-base/marketing/validation-outreach-template.md`
