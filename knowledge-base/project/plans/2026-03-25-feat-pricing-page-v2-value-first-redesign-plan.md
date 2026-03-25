---
title: "feat: Pricing page v2 — value-first redesign"
type: feat
date: 2026-03-25
---

# Pricing Page v2 — Value-First Redesign

## Overview

Complete rewrite of `plugins/soleur/docs/pages/pricing.njk` with a value-first page structure, new concurrent-agent-slot pricing model, and hiring comparison framing. The v1 page (PR #1096) was a pencil.dev dogfooding exercise — this v2 runs the full workflow with domain leader input.

## Problem Statement

The current pricing page:

1. Presents a fictional "Hosted Pro $49/mo + 10% rev share" tier that doesn't exist
2. Leads with "free" when the business needs to establish Soleur is worth paying for
3. Compares only against coding tools with dashes for non-engineering domains
4. Contains 7 instances of "plugin" violating brand guide

## Proposed Solution

Rewrite the page with a **value-first flow**: establish what Soleur replaces before showing a price. Introduce the concurrent-agent-slot pricing model as "Coming Soon" with waitlist capture.

### Page Sections (in order)

1. **Hero** — "Every department. One price." + replacement value subline
2. **Hiring comparison table** — Role costs vs. "Included" (Marketing Director $8k/mo, etc.)
3. **Department roster** — 8 departments rendered from `agents.js` DOMAIN_META with agent counts per department
4. **Scenario callouts** — 2-3 real-world value proofs ("Need a privacy policy? Your CLO drafts it.")
5. **Tier cards** — Solo ($49/2 slots), Startup ($149/5 slots), Scale ($499/unlimited), Enterprise (Contact), Self-hosted (Free)
6. **FAQ** — 5 objection-handling questions
7. **Final CTA** — Waitlist email capture reusing newsletter form pattern

## Technical Approach

### Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/docs/pages/pricing.njk` | Full rewrite — new sections, new content, new schema |
| `plugins/soleur/docs/css/style.css` | Add/modify pricing section CSS classes |
| `plugins/soleur/docs/_data/site.json` | No change needed — pricing already in nav |

### Files to Create

None — all changes are to existing files.

### Data Layer

The department roster section will pull from existing data:

- `stats.agents` / `stats.departments` / `stats.skills` — already available via `_data/stats.js`
- `DOMAIN_META` in `_data/agents.js` — has label, icon, and cardDescription for all 8 departments. However, this data is only available in the agents page template. The pricing page can hardcode department names or we can expose a simpler data export.

**Decision:** Hardcode the department roster in the template. The 8 departments are stable, and adding a new data pipeline for one section adds complexity without value. Use `stats.agents` and `stats.departments` for dynamic counts.

### Tier Card Architecture

Each tier card needs:

- Tier name + label
- Price (with period suffix for subscription tiers)
- Concurrent agent count
- Feature bullet list (3-4 items)
- CTA button (waitlist for paid tiers, install for self-hosted)
- "Coming Soon" badge on all paid tiers

Use existing `pricing-card` CSS class structure but expand from 2 cards to a 5-card responsive grid. On mobile, stack vertically with Solo featured.

### Waitlist Form

Reuse the existing `newsletter-form.njk` pattern (Buttondown form submission). Add a `location: pricing-waitlist` property for Plausible analytics tracking. The form already has error handling, success messages, and AJAX submission.

### Schema Markup

Replace current FAQPage-only schema with:

1. **FAQPage** — updated questions matching new FAQ content
2. **SoftwareApplication + Offer** — array of offers for each tier with price, priceCurrency, availability ("PreOrder" for Coming Soon, "InStock" for self-hosted)

### Implementation Phases

#### Phase 1: Template Rewrite (~80% of work)

Rewrite `pricing.njk` with all 7 sections. Key tasks:

- [ ] Rewrite hero: "Every department. One price." + new subline
- [ ] Add hiring comparison table section (6-8 roles with monthly costs)
- [ ] Add department roster grid (8 departments from DOMAIN_META, each with icon + name + description + agent count)
- [ ] Add scenario callout section (3 cards: legal, competitive intel, financial reporting)
- [ ] Redesign tier cards section (5 tiers: Solo, Startup, Scale, Enterprise, Self-hosted)
- [ ] All paid tier CTAs → waitlist buttons with "Coming Soon" badge
- [ ] Self-hosted tier CTA → "Install Now" linking to getting-started
- [ ] Rewrite FAQ (5 questions: "What does Soleur cost?", "What are concurrent agent slots?", "What does Claude cost?", "Is there a free option?", "When will paid tiers launch?")
- [ ] Rewrite final CTA section
- [ ] Update frontmatter: description, ogImage alt text
- [ ] Replace all "plugin" with "platform" (FR10)
- [ ] `plugins/soleur/docs/pages/pricing.njk`

#### Phase 2: CSS Updates

Add/modify styles for new sections. Reuse existing design tokens.

- [ ] Hiring comparison table: `.pricing-hiring-table` — two-column table (Role + Cost | With Soleur), alternating row backgrounds
- [ ] Department roster: `.department-roster` — responsive grid (4x2 desktop, 2x4 tablet, 1x8 mobile), each card with icon + name + description
- [ ] Scenario callouts: `.scenario-callouts` — 3-column card grid with icon/title/description
- [ ] Tier cards: expand `.pricing-grid` from 2-card to 5-card responsive layout. Featured card (Solo) gets gold border.
- [ ] Coming Soon badge: `.pricing-card-badge` already exists — verify styling works with new layout
- [ ] Waitlist form: reuse existing `.newsletter-form` styles, no new CSS needed
- [ ] `plugins/soleur/docs/css/style.css`

#### Phase 3: Schema & Meta

- [ ] Update FAQPage JSON-LD with new 5 questions
- [ ] Add SoftwareApplication + Offer schema for tier pricing
- [ ] Update `description` frontmatter to reflect new value prop messaging
- [ ] Update `ogImageAlt` to remove "$0" framing
- [ ] `plugins/soleur/docs/pages/pricing.njk`

#### Phase 4: Content Alignment

- [ ] Update `knowledge-base/product/pricing-strategy.md` — mark pricing as "decided" with new tier structure, update tier table, add implementation note
- [ ] Update `knowledge-base/product/pricing-strategy.md`

#### Phase 5: Build Validation

- [ ] Run `npx @11ty/eleventy` to verify build succeeds
- [ ] Screenshot at 1440px, 768px, 375px breakpoints via Playwright
- [ ] Visual review of all sections
- [ ] Verify FAQ schema renders in structured data testing
- [ ] Verify no "plugin" instances remain in pricing page output

## Acceptance Criteria

### Functional Requirements

- [ ] Page has 7 sections in value-first order (hero → hiring table → departments → scenarios → tiers → FAQ → CTA)
- [ ] Hiring comparison table shows 6+ roles with realistic monthly costs
- [ ] Department roster displays all 8 departments with icons, names, and descriptions
- [ ] 3 scenario callout cards with real-world value examples
- [ ] 5 tier cards: Solo ($49), Startup ($149), Scale ($499), Enterprise (Contact), Self-hosted (Free)
- [ ] All paid tiers show "Coming Soon" badge
- [ ] Paid tier CTAs are waitlist buttons (not disabled, not linked to checkout)
- [ ] Self-hosted tier links to getting-started page
- [ ] FAQ has 5 questions addressing top objections
- [ ] Zero instances of "plugin" in page content
- [ ] Waitlist form submits successfully via Buttondown

### Non-Functional Requirements

- [ ] FAQPage JSON-LD schema validates
- [ ] SoftwareApplication + Offer schema validates
- [ ] Page responsive at 1440px, 768px, 375px
- [ ] Eleventy build succeeds with no warnings
- [ ] OG meta tags reflect new messaging

## Test Scenarios

- Given a visitor on the pricing page, when they scroll, then they see value articulation (hiring table) before any price
- Given a visitor clicking a paid tier CTA, when the form submits, then they receive a waitlist confirmation
- Given a visitor clicking Self-hosted "Install Now", when they click, then they navigate to getting-started page
- Given a search engine crawling the page, when it parses JSON-LD, then it finds valid FAQPage and SoftwareApplication schemas
- Given a mobile visitor at 375px, when they view tier cards, then cards stack vertically and are fully readable

## Domain Review

**Domains relevant:** Marketing, Product, Sales

Carried forward from brainstorm `2026-03-25-pricing-page-v2-brainstorm.md` Domain Assessments section.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Complete persuasion architecture rebuild. Replace "plugin" with "platform." CTAs must match actual user journey (waitlist for paid, install for self-hosted). Recommends conversion-optimizer for layout review post-implementation.

### Product (CPO)

**Status:** reviewed
**Assessment:** Treat as marketing infrastructure, not payment infrastructure. Concurrent-agent-slot model is strategically sound. Key gap: no free cloud tier for non-CLI founders. Use page as validation artifact in founder interviews.

### Sales (CRO)

**Status:** reviewed
**Assessment:** Lead with replacement-stack frame ($49 vs. $50k+/mo in roles). Revenue share at Enterprise conflicts with anti-Polsia messaging — resolved by keeping rev share but not positioning against Polsia on it. $149 Startup is a 3x jump from Solo — justify via concrete feature differences.

### Product/UX Gate

**Tier:** blocking (new user-facing page with significant UI components)
**Decision:** reviewed (carried from brainstorm — CPO assessed, page structure decided via AskUserQuestion)
**Agents invoked:** cpo (brainstorm phase)
**Pencil available:** N/A (deferred — no wireframes for this implementation round)

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| Pricing numbers may change during founder interviews | All tiers marked "Coming Soon" — numbers are proposals, not commitments |
| 5-card tier layout may not fit well on mobile | Design mobile-first: stack vertically, feature Solo tier |
| Waitlist form may need separate list from newsletter | Use Buttondown tag or separate list if needed |
| Competitor pricing data could be stale | FAQ avoids specific competitor prices — comparison is against hiring, not tools |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-25-pricing-page-v2-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pricing-page-v2/spec.md`
- Pricing strategy: `knowledge-base/product/pricing-strategy.md`
- Current pricing page: `plugins/soleur/docs/pages/pricing.njk`
- Brand guide: `knowledge-base/marketing/brand-guide.md`
- Issue: #656
- Previous implementation: PR #1096
