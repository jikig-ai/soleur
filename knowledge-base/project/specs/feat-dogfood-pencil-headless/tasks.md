---
title: Tasks - Dogfood Pencil Headless CLI via Pricing Page
issue: 656
branch: dogfood-pencil-headless
created: 2026-03-24
---

# Tasks

## Phase 0: Register Pencil Headless MCP

- [ ] 0.1 Verify Node.js >= 22.9.0 available
- [ ] 0.2 Verify pencil CLI installed and authenticated
- [ ] 0.3 Run pencil-setup skill to register headless MCP
- [ ] 0.4 Verify MCP responds (`get_editor_state`)
- [ ] 0.5 Load landing-page design guidelines (`get_guidelines("landing-page")`)

## Phase 1: Wireframe in Pencil (.pen)

- [ ] 1.1 Set design variables via `set_variables` (brand tokens)
- [ ] 1.2 Create hero section (badge + headline + subheadline)
- [ ] 1.3 Create tier cards (2 cards: Free + Hosted Pro)
- [ ] 1.4 Create comparison table (Soleur vs 3 competitors)
- [ ] 1.5 Create cost explainer section
- [ ] 1.6 Create FAQ section
- [ ] 1.7 Create CTA section (dual buttons)
- [ ] 1.8 Screenshot full wireframe via `get_screenshot`
- [ ] 1.9 Test `get_screenshot` with tracked node IDs
- [ ] 1.10 Review and iterate layout

## Phase 2: HTML/Eleventy Implementation

- [ ] 2.1 Create `plugins/soleur/docs/pages/pricing.njk` with frontmatter
- [ ] 2.2 Implement hero section using `.page-hero`
- [ ] 2.3 Implement tier cards with new `.pricing-grid` CSS
- [ ] 2.4 Implement comparison table with responsive CSS
- [ ] 2.5 Implement cost explainer section
- [ ] 2.6 Implement FAQ section with `<details>` pattern
- [ ] 2.7 Add FAQPage JSON-LD schema
- [ ] 2.8 Add "Pricing" to nav and footer in `site.json`
- [ ] 2.9 Add pricing-specific CSS classes to `style.css`
- [ ] 2.10 Verify grid divisibility at all breakpoints

## Phase 3: Asset Generation via Pencil

- [ ] 3.1 Design OG image (1200x630) in pencil
- [ ] 3.2 Export OG image via `export_nodes`
- [ ] 3.3 Save to `plugins/soleur/docs/images/pricing-og.png`
- [ ] 3.4 Optional: design comparison graphic for social sharing

## Phase 4: Build Validation

- [ ] 4.1 Run Eleventy build successfully
- [ ] 4.2 Run SEO validation (`validate-seo.sh`)
- [ ] 4.3 Screenshot at 3 breakpoints via Playwright (1440px, 768px, 375px)
- [ ] 4.4 Verify FAQPage JSON-LD validates
- [ ] 4.5 Verify brand compliance (colors, fonts, voice)

## Phase 5: Dogfooding Issue Roundup

- [ ] 5.1 Compile full issue log from all phases
- [ ] 5.2 Batch-create GitHub issues with labels and reproduction steps
- [ ] 5.3 Update brainstorm test matrix checkboxes
- [ ] 5.4 Run compound to capture learnings
