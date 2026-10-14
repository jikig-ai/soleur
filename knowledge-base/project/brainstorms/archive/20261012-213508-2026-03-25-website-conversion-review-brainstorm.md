# Website Conversion Flow Review — Brainstorm

**Date:** 2026-03-25
**Status:** Complete
**Branch:** feat-website-conversion-review
**PR:** #1141

## What We're Building

A conversion-optimized website flow that makes **waitlist signups** the primary action across the site. The current site frames Soleur as a Claude Code plugin with install-first CTAs — this contradicts the hosted cross-platform pivot and actively anti-converts the target audience (founders who don't use Claude Code).

### Scope

1. **Homepage reframe** — Rewrite hero and CTAs for platform positioning, add inline waitlist email form, link to pricing as secondary CTA
2. **Navigation update** — Add Pricing to main nav
3. **Getting Started split** — Two-path page: Cloud Platform (primary, waitlist) and Self-Hosted (secondary, CLI install)
4. **Full plugin language cleanup** — Remove all "plugin," "terminal-first," "CLI" primary framing from homepage, Getting Started, meta descriptions, JSON-LD structured data, vision page, and all public-facing copy per brand guide
5. **Pricing page** — Keep existing v2 (4 tiers, no urgency). Ensure nav link and proper CTA flow from other pages

### Out of Scope

- Post-signup email sequences (separate initiative)
- A/B testing infrastructure
- Tier interest capture in waitlist form (#1139 tracks this separately)
- Waitlist counter or social proof (keeping honest, no urgency)
- Pricing tier simplification (keeping 4 tiers, adjust after 50+ users)

## Why This Approach

### Focused Funnel (Approach A)

Waitlist form on **homepage hero + pricing page only**. Other pages get CTA buttons linking to pricing. Two conversion surfaces to optimize and measure.

**Why not distributed forms (Approach B)?** Five forms to maintain, harder to measure which converts, premature optimization with zero traffic data.

**Why not sticky bar (Approach C)?** Pushy feel doesn't match the honest, transparent brand positioning. No urgency = no reason for aggressive capture.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Waitlist is the primary conversion goal** | The hosted platform is the future. Plugin install becomes a secondary path for technical users. |
| D2 | **Pricing page becomes the hero CTA destination** | It has the strongest value-first framing (hiring comparison, dept roster, tier cards). Homepage hero CTA says "See Pricing & Join Waitlist." |
| D3 | **Pricing added to main navigation** | Currently unreachable without a direct URL. The strongest conversion artifact must be discoverable. |
| D4 | **Full plugin language removal** | Brand guide already prohibits "plugin" and "terminal-first" in public content. This pass enforces that site-wide: homepage, Getting Started, meta tags, JSON-LD, vision page. |
| D5 | **Getting Started splits into two paths** | Cloud Platform (primary, coming soon, waitlist) and Self-Hosted (secondary, available now, CLI install). Serves both audiences without compromising either. |
| D6 | **Inline waitlist form on homepage** | Email capture directly in the hero. Captures visitors who'd never click through to pricing. |
| D7 | **No urgency or scarcity framing** | No "founder pricing lock-in," no waitlist counter. Build trust through transparency. "Coming Soon" badges stay as-is. |
| D8 | **Keep 4 pricing tiers** | The v2 pricing page is polished and shipped. Adjust tiers after gathering waitlist feedback and 50+ users. |

## Open Questions

1. **What happens after waitlist signup?** Currently just a Buttondown confirmation. Need a welcome email, "what to expect" messaging, and a link to the open-source version as a bridge. (Separate initiative.)
2. **Should the Vision page be deprioritized or rewritten?** Contains outdated "Success Tax" revenue model language that contradicts the pricing page. Low traffic but messaging contradiction.
3. **Footer newsletter vs. waitlist form differentiation** — The footer says "Stay in the loop — monthly updates" while the pricing form says "Join the waitlist for early access." Different value props, same Buttondown backend with different tags. Risk of confusion.
4. **About page** — CMO flagged the absence of an About page. Solo founders evaluate trust before committing even an email. No founder bio, no company story beyond "built by Soleur using Soleur."

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** The website hasn't caught up to the pivot. Homepage still says "Claude Code plugin," primary CTA goes to CLI install, pricing page is unreachable from nav. Two critical issues persist across audit cycles: broken OG tags/social sharing and "Claude Code plugin" meta descriptions violating the brand guide. The conversion funnel is fragmented — homepage CTA goes to self-hosted install while pricing page CTA goes to waitlist. CMO recommends: conversion-optimizer and ux-design-lead produce artifacts in parallel, then copywriter implements from approved artifacts. No implementation before specialist review.

### Product (CPO)

**Summary:** The website contradicts both the business validation (2026-03-22) and brand guide (2026-03-22). Homepage frames Soleur as a plugin; Getting Started is 100% CLI; JSON-LD structured data says "free" and "plugin." CPO recommends Option B (moderate reframe) as the right scope — addresses conversion-critical contradictions without pulling forward the entire Pre-Phase 4 marketing positioning gate. Notes the BLOCKING Product/UX Gate: user-facing pages require specialist artifacts (ux-design-lead wireframes, copywriter copy) before implementation. Milestone mismatches noted: #1139 (waitlist) and #656 (pricing) have milestone assignments inconsistent with the roadmap document.

## Pages Affected

| Page | Change Type | Priority |
|------|------------|----------|
| Homepage (index) | Major rewrite — hero, CTAs, inline form, all copy | P0 |
| Navigation (base layout) | Add Pricing link | P0 |
| Getting Started | Split into cloud/self-hosted paths | P0 |
| Pricing | Already shipped — ensure nav link works, minor copy alignment | P1 |
| Vision | Remove "Success Tax," align with platform positioning | P1 |
| Base layout (meta/JSON-LD) | Fix meta descriptions, OG tags, structured data | P1 |
| All pages (footer) | Differentiate newsletter vs. waitlist messaging | P2 |
