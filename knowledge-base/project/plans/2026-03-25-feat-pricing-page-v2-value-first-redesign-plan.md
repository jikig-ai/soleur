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

1. **Hero** — "Every department. One price." + replacement value subline + breadth stat line
2. **Hiring comparison table** — Role costs vs. "Included" with scenario proof in each row (e.g., "General Counsel $15k/mo → Included — privacy policies, compliance audits, DPAs")
3. **Tier cards** — Solo ($49/2 slots), Startup ($149/5 slots), Scale ($499/unlimited), Enterprise (Contact), Self-hosted (Free)
4. **FAQ** — 5 objection-handling questions
5. **Final CTA** — Waitlist email capture reusing newsletter form pattern

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

Use `stats.agents`, `stats.departments`, and `stats.skills` from `_data/stats.js` for dynamic counts in the hero breadth line.

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

Update FAQPage JSON-LD with new question set. Drop SoftwareApplication + Offer — tiers are "Coming Soon" proposals, not purchasable offers. Add structured data when at least one tier is live.

### Implementation Tasks

Edit two files: `plugins/soleur/docs/pages/pricing.njk` and `plugins/soleur/docs/css/style.css`.

- [ ] Rewrite hero: "Every department. One price." + new subline + "{{ stats.agents }} agents across {{ stats.departments }} departments" breadth line
- [ ] Add hiring comparison table (6-8 roles with monthly cost, "Included" column, and scenario proof per row)
- [ ] Expand `.pricing-grid` from 2-card to 5-card responsive layout (Solo featured with gold border)
- [ ] All paid tier CTAs → waitlist buttons with "Coming Soon" badge
- [ ] Self-hosted tier CTA → "Install Now" linking to getting-started
- [ ] Rewrite FAQ (5 questions: cost, concurrent slots, Claude cost, free option, launch timeline)
- [ ] Rewrite final CTA with waitlist email capture (reuse newsletter form pattern)
- [ ] Update FAQPage JSON-LD with new 5 questions
- [ ] Update frontmatter: description, ogImageAlt (remove "$0")
- [ ] Replace all "plugin" with "platform" (FR10)
- [ ] CSS: `.pricing-hiring-table` styles, expand `.pricing-grid` for 5 cards, verify `.pricing-card-badge`
- [ ] Build validation: `npx @11ty/eleventy`, screenshot at 3 breakpoints, verify zero "plugin" instances

## Acceptance Criteria

### Functional Requirements

- [ ] Page has 5 sections in value-first order (hero → hiring table → tiers → FAQ → CTA)
- [ ] Hiring comparison table shows 6+ roles with monthly costs and scenario proof per row
- [ ] 5 tier cards: Solo ($49), Startup ($149), Scale ($499), Enterprise (Contact), Self-hosted (Free)
- [ ] All paid tiers show "Coming Soon" badge with waitlist CTAs
- [ ] Self-hosted tier links to getting-started page
- [ ] FAQ has 5 questions addressing top objections
- [ ] Zero instances of "plugin" in page content
- [ ] Waitlist form submits successfully via Buttondown

### Non-Functional Requirements

- [ ] FAQPage JSON-LD schema validates
- [ ] Page responsive at 1440px, 768px, 375px
- [ ] Eleventy build succeeds with no warnings
- [ ] OG meta tags reflect new messaging

## Test Scenarios

- Given a visitor on the pricing page, when they scroll, then they see value articulation (hiring table) before any price
- Given a visitor clicking a paid tier CTA, when the form submits, then they receive a waitlist confirmation
- Given a visitor clicking Self-hosted "Install Now", when they click, then they navigate to getting-started page
- Given a search engine crawling the page, when it parses JSON-LD, then it finds valid FAQPage schema
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
