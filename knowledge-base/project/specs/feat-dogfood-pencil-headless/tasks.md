---
title: Tasks - Dogfood Pencil Headless CLI via Pricing Page
issue: 656
branch: dogfood-pencil-headless
created: 2026-03-24
updated: 2026-03-25
---

# Tasks

## Phase 0: Setup

- [ ] 0.1 Run `pencil-setup` skill to register headless MCP
- [ ] 0.2 Verify MCP responds (`get_editor_state`)

## Phase 1: Quick Wireframe in Pencil (15 min)

- [ ] 1.1 Set design variables via `set_variables` (brand tokens)
- [ ] 1.2 Create page sections via `batch_design` (hero, tiers, comparison, FAQ, CTA)
- [ ] 1.3 Screenshot via `get_screenshot` (full canvas + tracked node IDs)

## Phase 2: HTML/Eleventy Implementation

- [ ] 2.1 Create `plugins/soleur/docs/pages/pricing.njk` with frontmatter
- [ ] 2.2 Implement page sections (hero, tier cards, comparison, cost explainer, FAQ, CTA)
- [ ] 2.3 Add `.pricing-grid` and `.pricing-card` CSS to `style.css`
- [ ] 2.4 Add FAQPage JSON-LD schema (4 questions)
- [ ] 2.5 Add "Pricing" to nav and footer in `site.json`

## Phase 3: OG Image via Pencil

- [ ] 3.1 Design 1200x630 OG image in pencil
- [ ] 3.2 Export via `export_nodes` to `plugins/soleur/docs/images/pricing-og.png`

## Phase 4: Validation and Issue Roundup

- [ ] 4.1 Run Eleventy build
- [ ] 4.2 Run SEO validation (`validate-seo.sh`)
- [ ] 4.3 Screenshot at 3 breakpoints via Playwright
- [ ] 4.4 Compile issue log and batch-create GitHub issues
- [ ] 4.5 Update brainstorm test matrix
- [ ] 4.6 Run compound to capture learnings
