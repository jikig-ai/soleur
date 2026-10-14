# Tasks: Growth Audit P1 — FAQ Sections + Keyword Injection

## Phase 1: Setup

- [x] 1.1 Run `npm install` in the worktree to ensure Eleventy builds work
- [x] 1.2 Verify existing FAQ pattern works by building: `npx @11ty/eleventy --dryrun`

## Phase 2: Core Page FAQ Sections (6 pages)

- [x] 2.1 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/getting-started.md`
  - [x] 2.1.1 Write 3-5 FAQ Q&A pairs (installation, prerequisites, first steps, Claude Code requirements)
  - [x] 2.1.2 Add HTML FAQ section using `<details class="faq-item">` pattern
  - [x] 2.1.3 Add `<script type="application/ld+json">` FAQPage schema block
  - [x] 2.1.4 Include "solo founder AI tools" in one FAQ answer
- [x] 2.2 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/agents.njk`
  - [x] 2.2.1 Write 3-5 FAQ Q&A pairs (what are agents, how many, customization, domain coverage)
  - [x] 2.2.2 Add HTML FAQ section matching index.njk pattern
  - [x] 2.2.3 Add FAQPage schema block
- [x] 2.3 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/skills.njk`
  - [x] 2.3.1 Write 3-5 FAQ Q&A pairs (what are skills, how many, workflow lifecycle, invoking)
  - [x] 2.3.2 Add HTML FAQ section matching index.njk pattern
  - [x] 2.3.3 Add FAQPage schema block
- [x] 2.4 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/vision.njk`
  - [x] 2.4.1 Write 3-5 FAQ Q&A pairs (CaaS thesis, roadmap, pricing model, open source commitment)
  - [x] 2.4.2 Add HTML FAQ section matching index.njk pattern
  - [x] 2.4.3 Add FAQPage schema block
- [x] 2.5 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/community.njk`
  - [x] 2.5.1 Write 3-5 FAQ Q&A pairs (how to contribute, Discord, getting help, CLA)
  - [x] 2.5.2 Add HTML FAQ section matching index.njk pattern
  - [x] 2.5.3 Add FAQPage schema block
- [x] 2.6 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/changelog.njk`
  - [x] 2.6.1 Write 3-4 FAQ Q&A pairs (release cadence, versioning, how to upgrade, breaking changes)
  - [x] 2.6.2 Add HTML FAQ section matching index.njk pattern
  - [x] 2.6.3 Add FAQPage schema block

## Phase 3: Blog Case Study FAQ Sections (5 pages)

- [x] 3.1 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-brand-guide-creation.md`
  - [x] 3.1.1 Write 3-4 FAQ Q&A pairs (AI brand guide creation, time savings, output quality)
  - [x] 3.1.2 Add `<details>` FAQ section matching what-is-company-as-a-service.md pattern
  - [x] 3.1.3 Add `<script type="application/ld+json">` FAQPage schema block
- [x] 3.2 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-business-validation.md`
  - [x] 3.2.1 Write 3-4 FAQ Q&A pairs (AI business validation, gate methodology, when to use)
  - [x] 3.2.2 Add `<details>` FAQ section and FAQPage schema block
- [x] 3.3 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-competitive-intelligence.md`
  - [x] 3.3.1 Write 3-4 FAQ Q&A pairs (AI competitive analysis, battlecard generation, coverage)
  - [x] 3.3.2 Add `<details>` FAQ section and FAQPage schema block
- [x] 3.4 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-legal-document-generation.md`
  - [x] 3.4.1 Write 3-4 FAQ Q&A pairs (AI legal documents, jurisdiction coverage, accuracy)
  - [x] 3.4.2 Add `<details>` FAQ section and FAQPage schema block
- [x] 3.5 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-operations-management.md`
  - [x] 3.5.1 Write 3-4 FAQ Q&A pairs (AI operations management, expense tracking, infrastructure)
  - [x] 3.5.2 Add `<details>` FAQ section and FAQPage schema block

## Phase 4: Keyword Injection ("solo founder AI tools")

- [x] 4.1 Inject "solo founder AI tools" into `plugins/soleur/docs/index.njk` FAQ section
- [x] 4.2 Inject "solo founder AI tools" into `plugins/soleur/docs/pages/getting-started.md` (done in 2.1.4 — FAQ answer includes it)
- [x] 4.3 Inject "solo founder AI tools" into `plugins/soleur/docs/llms.txt.njk` description paragraph
- [x] 4.4 Verify 3+ distinct pages contain the exact phrase "solo founder AI tools" — confirmed 4 pages

## Phase 5: Verification

- [x] 5.1 Run Eleventy build to verify no template errors — `npx @11ty/eleventy --dryrun` passed
- [x] 5.2 Verify all 11 pages have FAQPage schema blocks — confirmed 13 pages (11 new + 2 existing)
- [x] 5.3 Verify "solo founder AI tools" appears in 3+ pages — confirmed 4 pages
- [x] 5.4 Spot-check that JSON-LD schema entries match visible FAQ text on 2-3 pages — checked agents.njk and case-study-brand-guide-creation.md
- [x] 5.5 Confirm P2 issue #656 was created for pricing page — confirmed
