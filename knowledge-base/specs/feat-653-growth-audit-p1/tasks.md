# Tasks: Growth Audit P1 — FAQ Sections + Keyword Injection

## Phase 1: Setup

- [ ] 1.1 Run `npm install` in the worktree to ensure Eleventy builds work
- [ ] 1.2 Verify existing FAQ pattern works by building: `npx @11ty/eleventy --dryrun`

## Phase 2: Core Page FAQ Sections (6 pages)

- [ ] 2.1 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/getting-started.md`
  - [ ] 2.1.1 Write 3-5 FAQ Q&A pairs (installation, prerequisites, first steps, Claude Code requirements)
  - [ ] 2.1.2 Add HTML FAQ section using `<details class="faq-item">` pattern
  - [ ] 2.1.3 Add `<script type="application/ld+json">` FAQPage schema block
  - [ ] 2.1.4 Include "solo founder AI tools" in one FAQ answer
- [ ] 2.2 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/agents.njk`
  - [ ] 2.2.1 Write 3-5 FAQ Q&A pairs (what are agents, how many, customization, domain coverage)
  - [ ] 2.2.2 Add HTML FAQ section matching index.njk pattern
  - [ ] 2.2.3 Add FAQPage schema block
- [ ] 2.3 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/skills.njk`
  - [ ] 2.3.1 Write 3-5 FAQ Q&A pairs (what are skills, how many, workflow lifecycle, invoking)
  - [ ] 2.3.2 Add HTML FAQ section matching index.njk pattern
  - [ ] 2.3.3 Add FAQPage schema block
- [ ] 2.4 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/vision.njk`
  - [ ] 2.4.1 Write 3-5 FAQ Q&A pairs (CaaS thesis, roadmap, pricing model, open source commitment)
  - [ ] 2.4.2 Add HTML FAQ section matching index.njk pattern
  - [ ] 2.4.3 Add FAQPage schema block
- [ ] 2.5 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/community.njk`
  - [ ] 2.5.1 Write 3-5 FAQ Q&A pairs (how to contribute, Discord, getting help, CLA)
  - [ ] 2.5.2 Add HTML FAQ section matching index.njk pattern
  - [ ] 2.5.3 Add FAQPage schema block
- [ ] 2.6 Add FAQ section + FAQPage schema to `plugins/soleur/docs/pages/changelog.njk`
  - [ ] 2.6.1 Write 3-4 FAQ Q&A pairs (release cadence, versioning, how to upgrade, breaking changes)
  - [ ] 2.6.2 Add HTML FAQ section matching index.njk pattern
  - [ ] 2.6.3 Add FAQPage schema block

## Phase 3: Blog Case Study FAQ Sections (5 pages)

- [ ] 3.1 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-brand-guide-creation.md`
  - [ ] 3.1.1 Write 3-4 FAQ Q&A pairs (AI brand guide creation, time savings, output quality)
  - [ ] 3.1.2 Add `<details>` FAQ section matching what-is-company-as-a-service.md pattern
  - [ ] 3.1.3 Add `<script type="application/ld+json">` FAQPage schema block
- [ ] 3.2 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-business-validation.md`
  - [ ] 3.2.1 Write 3-4 FAQ Q&A pairs (AI business validation, gate methodology, when to use)
  - [ ] 3.2.2 Add `<details>` FAQ section and FAQPage schema block
- [ ] 3.3 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-competitive-intelligence.md`
  - [ ] 3.3.1 Write 3-4 FAQ Q&A pairs (AI competitive analysis, battlecard generation, coverage)
  - [ ] 3.3.2 Add `<details>` FAQ section and FAQPage schema block
- [ ] 3.4 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-legal-document-generation.md`
  - [ ] 3.4.1 Write 3-4 FAQ Q&A pairs (AI legal documents, jurisdiction coverage, accuracy)
  - [ ] 3.4.2 Add `<details>` FAQ section and FAQPage schema block
- [ ] 3.5 Add FAQ section + FAQPage schema to `plugins/soleur/docs/blog/case-study-operations-management.md`
  - [ ] 3.5.1 Write 3-4 FAQ Q&A pairs (AI operations management, expense tracking, infrastructure)
  - [ ] 3.5.2 Add `<details>` FAQ section and FAQPage schema block

## Phase 4: Keyword Injection ("solo founder AI tools")

- [ ] 4.1 Inject "solo founder AI tools" into `plugins/soleur/docs/index.njk` FAQ section
- [ ] 4.2 Inject "solo founder AI tools" into `plugins/soleur/docs/pages/getting-started.md` (done in 2.1.4 if FAQ answer includes it, otherwise add to "What Is Soleur?" section)
- [ ] 4.3 Inject "solo founder AI tools" into `plugins/soleur/docs/llms.txt.njk` description paragraph
- [ ] 4.4 Verify 3+ distinct pages contain the exact phrase "solo founder AI tools"

## Phase 5: Verification

- [ ] 5.1 Run Eleventy build to verify no template errors
- [ ] 5.2 Verify all 11 pages have FAQPage schema blocks (grep for `FAQPage` across docs/)
- [ ] 5.3 Verify "solo founder AI tools" appears in 3+ pages (grep across docs/)
- [ ] 5.4 Spot-check that JSON-LD schema entries match visible FAQ text on 2-3 pages
- [ ] 5.5 Confirm P2 issue #656 was created for pricing page
